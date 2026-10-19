import 'package:flutter/material.dart';

import '../../../services/conversion_models.dart';
import '../models/selected_input_file.dart';
import 'conversion_action_button.dart';
import 'conversion_status.dart';
import 'file_drop_zone.dart';
import 'file_info_card.dart';
import 'format_selector.dart';
import 'output_location_selector.dart';

class ConverterCard extends StatelessWidget {
  const ConverterCard({
    required this.compact,
    required this.inputFile,
    required this.availableTargets,
    required this.targetFormat,
    required this.outputDirectory,
    required this.outputDirectoryName,
    required this.usesSourceDirectory,
    required this.overwrite,
    required this.isConverting,
    required this.canConvert,
    required this.canSelectFiles,
    required this.dragAndDropEnabled,
    required this.result,
    required this.onChooseFile,
    required this.onFileDropped,
    required this.onRemoveFile,
    required this.onTargetChanged,
    required this.onChooseOutputDirectory,
    required this.onOverwriteChanged,
    required this.onConvert,
    this.onOpenFile,
    this.onRevealFile,
    super.key,
  });

  final bool compact;
  final SelectedInputFile? inputFile;
  final List<ConversionFormat> availableTargets;
  final ConversionFormat targetFormat;
  final String? outputDirectory;
  final String? outputDirectoryName;
  final bool usesSourceDirectory;
  final bool overwrite;
  final bool isConverting;
  final bool canConvert;
  final bool canSelectFiles;
  final bool dragAndDropEnabled;
  final ConversionResult? result;
  final VoidCallback onChooseFile;
  final ValueChanged<String> onFileDropped;
  final VoidCallback onRemoveFile;
  final ValueChanged<ConversionFormat> onTargetChanged;
  final VoidCallback onChooseOutputDirectory;
  final ValueChanged<bool> onOverwriteChanged;
  final VoidCallback onConvert;
  final VoidCallback? onOpenFile;
  final VoidCallback? onRevealFile;

  @override
  Widget build(BuildContext context) {
    final input = inputFile;
    final directory = outputDirectory;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(compact ? 18 : 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FileDropZone(
              onChooseFile: onChooseFile,
              onFileDropped: onFileDropped,
              enabled: canSelectFiles,
              dragAndDropEnabled: dragAndDropEnabled,
              selectedContent: input == null
                  ? null
                  : FileInfoCard(
                      file: input,
                      enabled: !isConverting,
                      onRemove: onRemoveFile,
                      onReplace: onChooseFile,
                    ),
            ),
            if (input != null && availableTargets.isNotEmpty) ...[
              const SizedBox(height: 26),
              FormatSelector(
                sourceFormat: input.sourceFormat,
                availableTargets: availableTargets,
                targetFormat: targetFormat,
                enabled: !isConverting,
                onTargetChanged: onTargetChanged,
              ),
              const SizedBox(height: 26),
              if (directory != null && outputDirectoryName != null)
                OutputLocationSelector(
                  directoryName: outputDirectoryName!,
                  fullPath: directory,
                  isSourceDirectory: usesSourceDirectory,
                  overwrite: overwrite,
                  enabled: !isConverting,
                  onChooseDirectory: onChooseOutputDirectory,
                  onOverwriteChanged: onOverwriteChanged,
                ),
            ],
            const SizedBox(height: 18),
            ConversionActionButton(
              isConverting: isConverting,
              onPressed: canConvert ? onConvert : null,
            ),
            if (result != null) ...[
              const SizedBox(height: 16),
              ConversionStatus(
                result: result!,
                onOpenFile: onOpenFile,
                onRevealFile: onRevealFile,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
