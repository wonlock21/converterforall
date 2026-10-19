import 'package:flutter/material.dart';

import '../models/selected_input_file.dart';

class FileInfoCard extends StatelessWidget {
  const FileInfoCard({
    required this.file,
    required this.onRemove,
    required this.onReplace,
    this.enabled = true,
    super.key,
  });

  final SelectedInputFile file;
  final VoidCallback onRemove;
  final VoidCallback onReplace;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(17),
            ),
            child: Icon(
              Icons.picture_as_pdf_outlined,
              color: colorScheme.onPrimaryContainer,
              size: 30,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            file.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 5),
          Text(
            '${file.extension.toUpperCase()} · ${formatFileSize(file.sizeBytes)}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              TextButton.icon(
                key: const Key('replace_file_button'),
                onPressed: enabled ? onReplace : null,
                icon: const Icon(Icons.swap_horiz_rounded, size: 19),
                label: const Text('değiştir'),
              ),
              TextButton.icon(
                key: const Key('remove_file_button'),
                onPressed: enabled ? onRemove : null,
                icon: const Icon(Icons.close_rounded, size: 19),
                label: const Text('kaldır'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kilobytes = bytes / 1024;
    if (kilobytes < 1024) return '${kilobytes.toStringAsFixed(1)} KB';
    final megabytes = kilobytes / 1024;
    if (megabytes < 1024) return '${megabytes.toStringAsFixed(1)} MB';
    return '${(megabytes / 1024).toStringAsFixed(1)} GB';
  }
}
