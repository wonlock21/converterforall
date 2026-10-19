import 'package:flutter/material.dart';

class ConversionActionButton extends StatelessWidget {
  const ConversionActionButton({
    required this.isConverting,
    required this.onPressed,
    super.key,
  });

  final bool isConverting;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        key: const Key('convert_button'),
        onPressed: isConverting ? null : onPressed,
        icon: isConverting
            ? SizedBox.square(
                dimension: 19,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Theme.of(context).colorScheme.onPrimary,
                ),
              )
            : const Icon(Icons.sync_rounded),
        label: Text(isConverting ? 'dönüştürülüyor…' : 'dönüştür'),
      ),
    );
  }
}
