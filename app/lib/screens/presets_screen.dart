import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';

import '../services/dsp_config_service.dart';

/// Profile management screen for saving/loading .haprofile files.
class ProfileManagementScreen extends StatefulWidget {
  const ProfileManagementScreen({super.key});

  @override
  State<ProfileManagementScreen> createState() =>
      _ProfileManagementScreenState();
}

class _ProfileManagementScreenState extends State<ProfileManagementScreen> {
  List<String> _savedProfiles = [];

  @override
  void initState() {
    super.initState();
    _loadProfileList();
  }

  Future<void> _loadProfileList() async {
    final dspService = context.read<DspConfigService>();
    final profiles = await dspService.listSavedProfiles();
    setState(() => _savedProfiles = profiles);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DspConfigService>(
      builder: (context, dspService, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Current profile info
              _buildCurrentProfileCard(dspService),
              const SizedBox(height: 16),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _saveProfile(dspService),
                      icon: const Icon(Icons.save),
                      label: const Text('Save Profile'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _importProfile(dspService),
                      icon: const Icon(Icons.file_open),
                      label: const Text('Import'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _exportProfile(dspService),
                      icon: const Icon(Icons.ios_share),
                      label: const Text('Export'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Built-in presets
              const Text('Built-in Presets',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _presetChip('Mild Loss', 'mild', dspService),
                  _presetChip('Moderate Loss', 'moderate', dspService),
                  _presetChip('Severe Loss', 'severe', dspService),
                  _presetChip('High-Freq Loss', 'high_freq', dspService),
                ],
              ),
              const SizedBox(height: 20),

              // Saved profiles
              const Text('Saved Profiles',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (_savedProfiles.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No saved profiles yet',
                        style: TextStyle(color: Colors.grey)),
                  ),
                )
              else
                ..._savedProfiles.map((path) => _buildSavedProfileTile(
                    dspService, path)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCurrentProfileCard(DspConfigService dspService) {
    final meta = dspService.metadata;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Current Profile',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _infoRow('Patient', meta.patientName.isEmpty
                ? '(not set)' : meta.patientName),
            _infoRow('Audiologist', meta.audiologistName.isEmpty
                ? '(not set)' : meta.audiologistName),
            _infoRow('Modified', meta.dateModified.toString().split('.')[0]),
            _infoRow('Channels', '${dspService.channels.length}'),
            if (meta.notes.isNotEmpty) _infoRow('Notes', meta.notes),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => _editMetadata(dspService),
              child: const Text('Edit Patient Info'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text('$label:',
                style: const TextStyle(
                    fontWeight: FontWeight.w500, fontSize: 13)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _presetChip(
      String label, String type, DspConfigService dspService) {
    return ActionChip(
      label: Text(label),
      avatar: const Icon(Icons.hearing, size: 18),
      onPressed: () {
        dspService.loadBuiltInPreset(type);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Loaded $label preset')),
        );
      },
    );
  }

  Widget _buildSavedProfileTile(DspConfigService dspService, String path) {
    final fileName =
        path.split(Platform.pathSeparator).last.replaceAll('.haprofile', '');
    return ListTile(
      leading: const Icon(Icons.description),
      title: Text(fileName),
      subtitle: Text(path, style: const TextStyle(fontSize: 11)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.file_open),
            onPressed: () async {
              final ok = await dspService.loadProfile(path);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(ok ? 'Profile loaded' : 'Load failed')));
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final file = File(path);
              if (await file.exists()) {
                await file.delete();
                _loadProfileList();
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _saveProfile(DspConfigService dspService) async {
    // Ensure patient name is set
    if (dspService.metadata.patientName.isEmpty) {
      await _editMetadata(dspService);
      if (dspService.metadata.patientName.isEmpty) return;
    }

    final path = await dspService.saveProfile();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              path != null ? 'Saved to $path' : 'Save failed')));
      _loadProfileList();
    }
  }

  Future<void> _importProfile(DspConfigService dspService) async {
    final ok = await dspService.importProfile();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok ? 'Profile imported' : 'Import cancelled')));
    }
  }

  Future<void> _exportProfile(DspConfigService dspService) async {
    final ok = await dspService.exportProfile();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(ok ? 'Profile exported' : 'Export cancelled')));
    }
  }

  Future<void> _editMetadata(DspConfigService dspService) async {
    final nameCtrl =
        TextEditingController(text: dspService.metadata.patientName);
    final idCtrl =
        TextEditingController(text: dspService.metadata.patientId);
    final audioCtrl =
        TextEditingController(text: dspService.metadata.audiologistName);
    final notesCtrl =
        TextEditingController(text: dspService.metadata.notes);

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Patient Info'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: nameCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Patient Name')),
              TextField(
                  controller: idCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Patient ID')),
              TextField(
                  controller: audioCtrl,
                  decoration:
                      const InputDecoration(labelText: 'Audiologist')),
              TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(labelText: 'Notes'),
                  maxLines: 3),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              dspService.updateMetadata(
                patientName: nameCtrl.text,
                patientId: idCtrl.text,
                audiologistName: audioCtrl.text,
                notes: notesCtrl.text,
              );
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
