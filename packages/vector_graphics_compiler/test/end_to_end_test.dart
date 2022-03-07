import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_graphics/vector_graphics.dart';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart';

class TestBytesLoader extends BytesLoader {
  TestBytesLoader(this.data);

  final ByteData data;

  @override
  Future<ByteData> loadBytes() async {
    return data;
  }
}

const List<String> kTestAssets =  <String>[
  'assets/bars.svg',
  'assets/Ghostscript_Tiger.svg',
];

void main() {
  testWidgets('Can endcode and decode simple SVG with no errors', (WidgetTester tester) async {
    for (final String filename in kTestAssets) {
      final String svg = File(filename).readAsStringSync();
      final Uint8List bytes = await encodeSVG(svg, filename);

      await tester.pumpWidget(VectorGraphic(bytesLoader: TestBytesLoader(bytes.buffer.asByteData())));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    }
  });
}
