import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/dsp_config_service.dart';
import '../models/dsp_preset.dart';

/// Screen for managing patient presets
class PresetsScreen extends StatelessWidget {
  const PresetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dspService = context.watch<DspConfigService>();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with actions
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Saved Presets',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Row(
                children: [
                  IconButton(
                    onPressed: () => _showSavePresetDialog(context, dspService),
                    icon: const Icon(Icons.add),
                    tooltip: 'Save Current as Preset',
                  ),
                  IconButton(
                    onPressed: () => dspService.importPreset(),
                    icon: const Icon(Icons.file_upload),
                    tooltip: 'Import Preset',
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Preset list
          Expanded(
            child: dspService.presets.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.folder_open, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('No presets saved yet'),
                      SizedBox(height: 8),
                      Text(
                        'Configure DSP parameters and save them as presets\nfor quick access later.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: dspService.presets.length,
                  itemBuilder: (context, index) {
                    final preset = dspService.presets[index];
                    return _PresetCard(
                      preset: preset,
                      onLoad: () => dspService.loadPreset(preset),
                      onExport: () => dspService.exportPreset(preset),
                      onDelete: () => _confirmDelete(context, dspService, preset),
                    );
                  },
                ),
          ),

          const Divider(),

          // Built-in presets section
          Text(
            'Built-in Presets',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _BuiltInPresetChip(
                label: 'Mild Loss',
                onTap: () => dspService.loadBuiltInPreset('mild'),
              ),
              _BuiltInPresetChip(
                label: 'Moderate Loss',
                onTap: () => dspService.loadBuiltInPreset('moderate'),
              ),
              _BuiltInPresetChip(
                label: 'Severe Loss',
                onTap: () => dspService.loadBuiltInPreset('severe'),
              ),
              _BuiltInPresetChip(
                label: 'High Freq Emphasis',
                onTap: () => dspService.loadBuiltInPreset('high_freq'),
              ),
              _BuiltInPresetChip(
                label: 'Speech Focus',
                onTap: () => dspService.loadBuiltInPreset('speech'),
              ),
              _BuiltInPresetChip(
                label: 'Music',
                onTap: () => dspService.loadBuiltInPreset('music'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showSavePresetDialog(BuildContext context, DspConfigService dspService) {
    final nameController = TextEditingController();
    final notesController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Preset'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'Preset Name',
                hintText: 'e.g., Patient Name - Date',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: notesController,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                hintText: 'e.g., Audiogram details, preferences',
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                dspService.saveCurrentAsPreset(
                  nameController.text,
                  notesController.text,
                );
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(
    BuildContext context, 
    DspConfigService dspService, 
    DspPreset preset,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Preset?'),
        content: Text('Are you sure you want to delete "${preset.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              dspService.deletePreset(preset);
              Navigator.pop(context);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

/// Card widget for displaying a saved preset
class _PresetCard extends StatelessWidget {
  final DspPreset preset;
  final VoidCallback onLoad;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  const _PresetCard({
    required this.preset,
    required this.onLoad,
    required this.onExport,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const CircleAvatar(
          child: Icon(Icons.tune),
        ),
        title: Text(preset.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Created: ${_formatDate(preset.createdAt)}'),
            if (preset.notes.isNotEmpty) 
              Text(
                preset.notes,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        isThreeLine: preset.notes.isNotEmpty,
        trailing: PopupMenuButton<String>(
          onSelected: (value) {
            switch (value) {
              case 'load':
                onLoad();
                break;
              case 'export':
                onExport();
                break;
              case 'delete':
                onDelete();
                break;
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'load', child: Text('Load Preset')),
            const PopupMenuItem(value: 'export', child: Text('Export')),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
        onTap: onLoad,
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}

/// Chip widget for built-in presets
class _BuiltInPresetChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _BuiltInPresetChip({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      onPressed: onTap,
      avatar: const Icon(Icons.auto_fix_high, size: 18),
    );
  }
}
