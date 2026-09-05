import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:limeimage/models/image_metadata.dart';
import 'package:limeimage/ui/metadata_panel.dart';
import 'package:limeimage/ui/theme.dart';

const technical = MetadataField(
  'XMP',
  'xmpMM:DocumentID',
  'hidden-id',
  namespace: 'http://ns.adobe.com/xap/1.0/mm/',
);

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('no toolbar or technical fields in $brightness', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: LimeTheme.build(brightness, 0xff8bc34a),
          home: const Scaffold(
            body: SizedBox(
              width: 320,
              child: MetadataPanel(
                data: ImageMetadata(
                  fields: [
                    MetadataField('EXIF', 'Image Copyright', 'Author'),
                    technical,
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.byTooltip('复制全部'), findsNothing);
      expect(find.byTooltip('显示技术字段'), findsNothing);
      expect(find.text('hidden-id'), findsNothing);
      expect(find.text('XMP (1)'), findsNothing);
      expect(find.text('Author'), findsOneWidget);
      expect(find.byTooltip('复制'), findsOneWidget);
      await tester.tap(find.text('EXIF (1)'));
      await tester.pump();
      expect(find.text('Author'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('technical-only metadata has a clear empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 294,
            child: MetadataPanel(data: ImageMetadata(fields: [technical])),
          ),
        ),
      ),
    );
    expect(find.text('无可显示的元数据'), findsOneWidget);
    expect(find.text('hidden-id'), findsNothing);
  });
  testWidgets('PNG text is displayed as its own group', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 294,
            child: MetadataPanel(
              data: ImageMetadata(
                fields: [MetadataField('PNG Text', 'parameters', 'steps: 30')],
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('PNG 文本 (1)'), findsOneWidget);
    expect(find.text('steps: 30'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('narrow panel retains long text expansion', (tester) async {
    final long = '描述' * 200;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 294,
            child: MetadataPanel(
              data: ImageMetadata(
                fields: [MetadataField('XMP', 'dc:description', long)],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('展开全文'));
    await tester.pump();
    expect(find.widgetWithText(SelectableText, long), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
