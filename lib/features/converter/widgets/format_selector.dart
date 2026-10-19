import 'package:flutter/material.dart';

import '../../../services/conversion_models.dart';

class FormatSelector extends StatelessWidget {
  const FormatSelector({
    required this.sourceFormat,
    required this.availableTargets,
    required this.targetFormat,
    required this.onTargetChanged,
    this.enabled = true,
    super.key,
  });

  final ConversionFormat sourceFormat;
  final List<ConversionFormat> availableTargets;
  final ConversionFormat targetFormat;
  final ValueChanged<ConversionFormat> onTargetChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final source = _ReadOnlyFormatField(
          key: const Key('source_format'),
          label: 'kaynak format',
          format: sourceFormat,
        );
        final target = DropdownButtonFormField<ConversionFormat>(
          key: const Key('target_format'),
          initialValue: targetFormat,
          decoration: const InputDecoration(labelText: 'hedef format'),
          items: [
            for (final format in availableTargets)
              DropdownMenuItem(
                value: format,
                child: Text(format.extension.toUpperCase()),
              ),
          ],
          onChanged: enabled
              ? (value) {
                  if (value != null) onTargetChanged(value);
                }
              : null,
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

class _ReadOnlyFormatField extends StatelessWidget {
  const _ReadOnlyFormatField({
    required this.label,
    required this.format,
    super.key,
  });

  final String label;
  final ConversionFormat format;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: Text(
        format.extension.toUpperCase(),
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );
  }
}
