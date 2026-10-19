import 'package:flutter/material.dart';

class OutputLocationSelector extends StatelessWidget {
  const OutputLocationSelector({
    required this.directoryName,
    required this.fullPath,
    required this.isSourceDirectory,
    required this.overwrite,
    required this.onChooseDirectory,
    required this.onOverwriteChanged,
    this.enabled = true,
    super.key,
  });

  final String directoryName;
  final String fullPath;
  final bool isSourceDirectory;
  final bool overwrite;
  final VoidCallback onChooseDirectory;
  final ValueChanged<bool> onOverwriteChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('çıktı konumu', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        Container(
          key: const Key('output_location'),
          padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(Icons.folder_outlined, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Tooltip(
                  message: fullPath,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        directoryName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      if (isSourceDirectory)
                        Text(
                          'kaynak dosyanın klasörü',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                key: const Key('choose_output_button'),
                onPressed: enabled ? onChooseDirectory : null,
                child: const Text('değiştir'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        CheckboxListTile(
          key: const Key('overwrite_checkbox'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          controlAffinity: ListTileControlAffinity.leading,
          value: overwrite,
          title: const Text('aynı adlı dosyanın üzerine yazmaya izin ver'),
          onChanged: enabled
              ? (value) => onOverwriteChanged(value ?? false)
              : null,
        ),
      ],
    );
  }
}
