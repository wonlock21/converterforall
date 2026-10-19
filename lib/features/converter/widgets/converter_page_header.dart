import 'package:flutter/material.dart';

class ConverterPageHeader extends StatelessWidget {
  const ConverterPageHeader({
    required this.compact,
    required this.isDarkMode,
    required this.onThemeToggle,
    super.key,
  });

  final bool compact;
  final bool isDarkMode;
  final VoidCallback? onThemeToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.swap_horiz_rounded,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    'convertforall',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  key: const Key('theme_toggle_button'),
                  tooltip: isDarkMode ? 'açık temaya geç' : 'koyu temaya geç',
                  onPressed: onThemeToggle,
                  icon: Icon(
                    isDarkMode
                        ? Icons.light_mode_outlined
                        : Icons.dark_mode_outlined,
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: compact ? 38 : 54),
        Text(
          'dosyalarını dönüştür.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.headlineLarge?.copyWith(fontSize: compact ? 31 : null),
        ),
        const SizedBox(height: 9),
        Text(
          'hızlı, basit ve tamamen çevrimdışı.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
