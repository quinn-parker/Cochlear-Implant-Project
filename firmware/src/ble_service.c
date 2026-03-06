/*
 * SPDX-License-Identifier: Apache-2.0
 *
 * Cochlear Implant Project - BLE GATT Service for Hearing Aid Configuration
 * Target: nRF54L15
 *
 * Provides a custom GATT service that allows a host application to read/write
 * DSP configuration parameters over Bluetooth Low Energy. The same binary
 * protocol used over UART is tunneled through BLE characteristics.
 */

#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>
#include <zephyr/bluetooth/bluetooth.h>
#include <zephyr/bluetooth/hci.h>
#include <zephyr/bluetooth/conn.h>
#include <zephyr/bluetooth/uuid.h>
#include <zephyr/bluetooth/gatt.h>
#include <string.h>

LOG_MODULE_REGISTER(ble_service, LOG_LEVEL_INF);

/*
 * =============================================================================
 * External: command handler defined in hearing_aid_dsp.c
 * =============================================================================
 */
extern void handle_config_command(uint8_t cmd, uint8_t *payload, uint16_t len);

/*
 * =============================================================================
 * Custom Service UUIDs
 * =============================================================================
 * Service:         12345678-1234-5678-1234-56789abcdef0
 * Config Write:    12345678-1234-5678-1234-56789abcdef1
 * Config Notify:   12345678-1234-5678-1234-56789abcdef2
 */

#define HA_SERVICE_UUID_VAL \
    BT_UUID_128_ENCODE(0x12345678, 0x1234, 0x5678, 0x1234, 0x56789abcdef0)

#define HA_CONFIG_WRITE_UUID_VAL \
    BT_UUID_128_ENCODE(0x12345678, 0x1234, 0x5678, 0x1234, 0x56789abcdef1)

#define HA_CONFIG_NOTIFY_UUID_VAL \
    BT_UUID_128_ENCODE(0x12345678, 0x1234, 0x5678, 0x1234, 0x56789abcdef2)

static struct bt_uuid_128 ha_service_uuid = BT_UUID_INIT_128(HA_SERVICE_UUID_VAL);
static struct bt_uuid_128 ha_config_write_uuid = BT_UUID_INIT_128(HA_CONFIG_WRITE_UUID_VAL);
static struct bt_uuid_128 ha_config_notify_uuid = BT_UUID_INIT_128(HA_CONFIG_NOTIFY_UUID_VAL);

/*
 * =============================================================================
 * BLE State
 * =============================================================================
 */

static bool ble_connected = false;
static bool notify_enabled = false;
static struct bt_conn *current_conn = NULL;

/* Buffer for assembling multi-packet writes */
#define BLE_RX_BUFFER_SIZE 512
static uint8_t ble_rx_buffer[BLE_RX_BUFFER_SIZE];
static size_t ble_rx_pos = 0;
static size_t ble_rx_expected = 0;
static uint8_t ble_rx_cmd = 0;

/* Buffer for sending responses via notify */
#define BLE_TX_BUFFER_SIZE 512
static uint8_t ble_tx_buffer[BLE_TX_BUFFER_SIZE];

/*
 * =============================================================================
 * BLE Response Sending (via Notification)
 * =============================================================================
 */

/* Forward declaration of the GATT service for notification */
static struct bt_gatt_attr ha_service_attrs[];

void ble_send_response(const uint8_t *data, size_t len)
{
    if (!ble_connected || !notify_enabled || !current_conn) {
        return;
    }

    if (len > BLE_TX_BUFFER_SIZE) {
        LOG_WRN("BLE response too large: %d bytes", len);
        return;
    }

    memcpy(ble_tx_buffer, data, len);

    /* Attribute for notify characteristic (index 4 in service: svc, write_decl, write_val, notify_decl, notify_val, ccc) */
    struct bt_gatt_notify_params params = {
        .attr = &ha_service_attrs[4],
        .data = ble_tx_buffer,
        .len = len,
    };

    int err = bt_gatt_notify_cb(current_conn, &params);
    if (err) {
        LOG_WRN("BLE notify failed: %d", err);
    }
}

/*
 * =============================================================================
 * Config Write Characteristic Handler
 * =============================================================================
 * Receives protocol frames: [cmd:1][len:2 LE][payload:N]
 * Reassembles multi-packet writes for large payloads.
 */

static ssize_t config_write_handler(struct bt_conn *conn,
                                     const struct bt_gatt_attr *attr,
                                     const void *buf, uint16_t len,
                                     uint16_t offset, uint8_t flags)
{
    const uint8_t *data = buf;

    if (ble_rx_pos == 0 && len >= 3) {
        /* Start of a new command frame */
        ble_rx_cmd = data[0];
        ble_rx_expected = data[1] | ((uint16_t)data[2] << 8);

        if (ble_rx_expected == 0) {
            /* Commands with empty payload (R, S) */
            handle_config_command(ble_rx_cmd, NULL, 0);
            return len;
        }

        if (ble_rx_expected > BLE_RX_BUFFER_SIZE) {
            LOG_ERR("BLE payload too large: %d", ble_rx_expected);
            ble_rx_pos = 0;
            return len;
        }

        /* Copy remaining bytes after the 3-byte header */
        size_t payload_in_this_packet = len - 3;
        if (payload_in_this_packet > ble_rx_expected) {
            payload_in_this_packet = ble_rx_expected;
        }
        memcpy(ble_rx_buffer, &data[3], payload_in_this_packet);
        ble_rx_pos = payload_in_this_packet;

    } else if (ble_rx_pos > 0) {
        /* Continuation of a multi-packet write */
        size_t remaining = ble_rx_expected - ble_rx_pos;
        size_t to_copy = (len < remaining) ? len : remaining;
        memcpy(&ble_rx_buffer[ble_rx_pos], data, to_copy);
        ble_rx_pos += to_copy;
    }

    /* Check if we have received the full payload */
    if (ble_rx_pos >= ble_rx_expected && ble_rx_expected > 0) {
        handle_config_command(ble_rx_cmd, ble_rx_buffer, ble_rx_expected);
        ble_rx_pos = 0;
        ble_rx_expected = 0;
    }

    return len;
}

/*
 * =============================================================================
 * Notify CCC (Client Characteristic Configuration) Changed
 * =============================================================================
 */

static void notify_ccc_changed(const struct bt_gatt_attr *attr, uint16_t value)
{
    notify_enabled = (value == BT_GATT_CCC_NOTIFY);
    LOG_INF("BLE notifications %s", notify_enabled ? "enabled" : "disabled");
}

/*
 * =============================================================================
 * GATT Service Definition
 * =============================================================================
 */

BT_GATT_SERVICE_DEFINE(ha_service,
    /* Primary Service */
    BT_GATT_PRIMARY_SERVICE(&ha_service_uuid),

    /* Config Write Characteristic */
    BT_GATT_CHARACTERISTIC(&ha_config_write_uuid.uuid,
                           BT_GATT_CHRC_WRITE | BT_GATT_CHRC_WRITE_WITHOUT_RESP,
                           BT_GATT_PERM_WRITE,
                           NULL, config_write_handler, NULL),

    /* Config Notify Characteristic */
    BT_GATT_CHARACTERISTIC(&ha_config_notify_uuid.uuid,
                           BT_GATT_CHRC_NOTIFY,
                           BT_GATT_PERM_NONE,
                           NULL, NULL, NULL),
    BT_GATT_CCC(notify_ccc_changed,
                 BT_GATT_PERM_READ | BT_GATT_PERM_WRITE),
);

/* Save reference to service attrs for notify calls */
static struct bt_gatt_attr *ha_service_attrs = ha_service.attrs;

/*
 * =============================================================================
 * BLE Connection Callbacks
 * =============================================================================
 */

static void connected(struct bt_conn *conn, uint8_t err)
{
    if (err) {
        LOG_ERR("BLE connection failed (err %u)", err);
        return;
    }

    LOG_INF("BLE connected");
    ble_connected = true;
    current_conn = bt_conn_ref(conn);

    /* Request higher MTU for large config transfers */
    struct bt_conn_info info;
    bt_conn_get_info(conn, &info);
}

static void disconnected(struct bt_conn *conn, uint8_t reason)
{
    LOG_INF("BLE disconnected (reason %u)", reason);
    ble_connected = false;
    notify_enabled = false;
    ble_rx_pos = 0;

    if (current_conn) {
        bt_conn_unref(current_conn);
        current_conn = NULL;
    }
}

BT_CONN_CB_DEFINE(conn_callbacks) = {
    .connected = connected,
    .disconnected = disconnected,
};

/*
 * =============================================================================
 * Advertising Data
 * =============================================================================
 */

static const struct bt_data ad[] = {
    BT_DATA_BYTES(BT_DATA_FLAGS, (BT_LE_AD_GENERAL | BT_LE_AD_NO_BREDR)),
    BT_DATA_BYTES(BT_DATA_UUID128_ALL, HA_SERVICE_UUID_VAL),
};

static const struct bt_data sd[] = {
    BT_DATA(BT_DATA_NAME_COMPLETE, CONFIG_BT_DEVICE_NAME, sizeof(CONFIG_BT_DEVICE_NAME) - 1),
};

/*
 * =============================================================================
 * BLE Initialization
 * =============================================================================
 */

int ble_service_init(void)
{
    int err;

    err = bt_enable(NULL);
    if (err) {
        LOG_ERR("Bluetooth init failed (err %d)", err);
        return err;
    }

    LOG_INF("Bluetooth initialized");

    err = bt_le_adv_start(BT_LE_ADV_CONN, ad, ARRAY_SIZE(ad), sd, ARRAY_SIZE(sd));
    if (err) {
        LOG_ERR("Advertising failed to start (err %d)", err);
        return err;
    }

    LOG_INF("BLE advertising started as \"%s\"", CONFIG_BT_DEVICE_NAME);
    return 0;
}

bool ble_is_connected(void)
{
    return ble_connected;
}
