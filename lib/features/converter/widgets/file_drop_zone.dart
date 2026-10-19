import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

class FileDropZone extends StatefulWidget {
  const FileDropZone({
    required this.onChooseFile,
    required this.onFileDropped,
    this.selectedContent,
    this.enabled = true,
    this.dragAndDropEnabled = true,
    super.key,
  });

  final VoidCallback onChooseFile;
  final ValueChanged<String> onFileDropped;
  final Widget? selectedContent;
  final bool enabled;
  final bool dragAndDropEnabled;

  @override
  State<FileDropZone> createState() => _FileDropZoneState();
}

class _FileDropZoneState extends State<FileDropZone> {
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final content = Container(
      key: const Key('file_drop_zone'),
      constraints: const BoxConstraints(minHeight: 210),
      decoration: BoxDecoration(
        color: _isDragging
            ? colorScheme.primaryContainer.withValues(alpha: 0.42)
            : colorScheme.surfaceContainerLow.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(20),
      ),
      child: CustomPaint(
        foregroundPainter: _DashedRoundedBorderPainter(
          color: _isDragging ? colorScheme.primary : colorScheme.outline,
          radius: 20,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: widget.selectedContent ?? _buildEmptyState(context),
        ),
      ),
    );

    if (!widget.dragAndDropEnabled) {
      return content;
    }

    return DropTarget(
      enable: widget.enabled,
      onDragEntered: (_) => setState(() => _isDragging = true),
      onDragExited: (_) => setState(() => _isDragging = false),
      onDragDone: (details) {
        setState(() => _isDragging = false);
        final files = details.files.whereType<DropItemFile>();
        if (files.isNotEmpty) {
          widget.onFileDropped(files.first.path);
        }
      },
      child: content,
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.note_add_outlined,
              color: colorScheme.onPrimaryContainer,
              size: 28,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.dragAndDropEnabled
                ? 'dosyanı buraya sürükle'
                : 'dönüştürülecek dosyayı seç',
            textAlign: TextAlign.center,
            style: textTheme.titleMedium,
          ),
          const SizedBox(height: 5),
          Text(
            widget.dragAndDropEnabled
                ? 'veya bilgisayarından bir dosya seç'
                : 'dosyan yalnızca bu cihazda işlenir',
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const Key('select_file_button'),
            onPressed: widget.enabled ? widget.onChooseFile : null,
            icon: const Icon(Icons.folder_open_outlined, size: 19),
            label: const Text('dosya seç'),
          ),
        ],
      ),
    );
  }
}

class _DashedRoundedBorderPainter extends CustomPainter {
  const _DashedRoundedBorderPainter({
    required this.color,
    required this.radius,
  });

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius)),
      );

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = math.min(distance + 8, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += 14;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRoundedBorderPainter oldDelegate) {
    return color != oldDelegate.color || radius != oldDelegate.radius;
  }
}
