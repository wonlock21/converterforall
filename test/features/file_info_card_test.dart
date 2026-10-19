import 'package:convertforall_flutter/features/converter/models/selected_input_file.dart';
import 'package:convertforall_flutter/features/converter/widgets/file_info_card.dart';
import 'package:convertforall_flutter/services/conversion_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('uses a format-specific selected file icon', (tester) async {
    final cases = <String, IconData>{
      'pdf': Icons.picture_as_pdf_outlined,
      'docx': Icons.description_outlined,
      'jpg': Icons.image_outlined,
      'jpeg': Icons.image_outlined,
      'png': Icons.image_outlined,
      'txt': Icons.text_snippet_outlined,
    };

    for (final entry in cases.entries) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileInfoCard(
              file: SelectedInputFile(
                path: 'C:/files/sample.${entry.key}',
                name: 'sample.${entry.key}',
                extension: entry.key,
                sizeBytes: 10,
                sourceFormat: ConversionFormat.fromExtension(entry.key),
              ),
              onRemove: () {},
              onReplace: () {},
            ),
          ),
        ),
      );

      final icon = tester.widget<Icon>(
        find.byKey(const Key('selected_file_type_icon')),
      );
      expect(icon.icon, entry.value, reason: entry.key);
    }
  });
}
