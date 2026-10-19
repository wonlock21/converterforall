import 'package:flutter/material.dart';

import '../../../services/conversion_models.dart';

class ConversionStatus extends StatelessWidget {
  const ConversionStatus({
    required this.result,
    this.onOpenFile,
    this.onRevealFile,
    super.key,
  });

  final ConversionResult result;
  final VoidCallback? onOpenFile;
  final VoidCallback? onRevealFile;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final success = result.success;
    final background = success
        ? colorScheme.primaryContainer.withValues(alpha: 0.55)
        : colorScheme.errorContainer;
    final foreground = success
        ? colorScheme.onPrimaryContainer
        : colorScheme.onErrorContainer;

    return Semantics(
      liveRegion: true,
      child: Container(
        key: const Key('conversion_status'),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  success
                      ? Icons.check_circle_outline_rounded
                      : Icons.error_outline_rounded,
                  color: foreground,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        success
                            ? 'dönüştürme tamamlandı'
                            : 'dönüştürme başarısız',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        success
                            ? 'dosyan hazır · ${result.durationMs} ms'
                            : result.message,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(color: foreground),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (success && (onOpenFile != null || onRevealFile != null)) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (onOpenFile != null)
                    FilledButton.tonalIcon(
                      key: const Key('open_file_button'),
                      onPressed: onOpenFile,
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('dosyayı aç'),
                    ),
                  if (onRevealFile != null)
                    TextButton.icon(
                      key: const Key('reveal_file_button'),
                      onPressed: onRevealFile,
                      icon: const Icon(Icons.folder_open_outlined, size: 18),
                      label: const Text('klasörde göster'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
