import 'package:flutter/material.dart';

import '../../../services/conversion_models.dart';

class FormatSelector extends StatelessWidget {
  const FormatSelector({
    required this.availableSources,
    required this.sourceFormat,
    required this.availableTargets,
    required this.targetFormat,
    required this.onSourceChanged,
    required this.onTargetChanged,
    this.isLoading = false,
    this.enabled = true,
    super.key,
  });

  final List<ConversionFormat> availableSources;
  final ConversionFormat? sourceFormat;
  final List<ConversionFormat> availableTargets;
  final ConversionFormat? targetFormat;
  final ValueChanged<ConversionFormat> onSourceChanged;
  final ValueChanged<ConversionFormat> onTargetChanged;
  final bool enabled;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final source = _FormatDropdown(
          fieldKey: const Key('source_format'),
          label: 'kaynak format',
          formats: availableSources,
          value: availableSources.contains(sourceFormat) ? sourceFormat : null,
          enabled: enabled,
          isLoading: isLoading,
          onChanged: onSourceChanged,
        );
        final target = _FormatDropdown(
          fieldKey: const Key('target_format'),
          label: 'hedef format',
          formats: availableTargets,
          value: availableTargets.contains(targetFormat) ? targetFormat : null,
          enabled: enabled,
          isLoading: isLoading,
          onChanged: onTargetChanged,
        );

        if (constraints.maxWidth < 480) {
          return Column(
            children: [
              source,
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Icon(
                  Icons.arrow_downward_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              target,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: source),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Icon(
                Icons.arrow_forward_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            Expanded(child: target),
          ],
        );
      },
    );
  }
}

class _FormatDropdown extends StatelessWidget {
  const _FormatDropdown({
    required this.fieldKey,
    required this.label,
    required this.formats,
    required this.value,
    required this.enabled,
    required this.isLoading,
    required this.onChanged,
  });

  final Key fieldKey;
  final String label;
  final List<ConversionFormat> formats;
  final ConversionFormat? value;
  final bool enabled;
  final bool isLoading;
  final ValueChanged<ConversionFormat> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      key: fieldKey,
      decoration: InputDecoration(labelText: label),
      isEmpty: value == null,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<ConversionFormat>(
          value: value,
          isDense: true,
          isExpanded: true,
          hint: Text(
            isLoading
                ? 'yükleniyor…'
                : (formats.isEmpty ? 'format yok' : 'format seç'),
          ),
          items: [
            for (final format in formats)
              DropdownMenuItem(
                value: format,
                child: Text(format.extension.toUpperCase()),
              ),
          ],
          onChanged: enabled && formats.isNotEmpty
              ? (selected) {
                  if (selected != null) onChanged(selected);
                }
              : null,
        ),
      ),
    );
  }
}
