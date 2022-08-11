// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:vector_graphics/vector_graphics.dart';
import 'package:vector_graphics_network/src/loader.dart';
import 'package:vector_graphics_network/vector_graphics_network.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Can "download" and compile a simple SVG',
      (WidgetTester tester) async {
    debugLoadDataResultOverride = r'''
<svg height="100" width="100">
  <circle cx="50" cy="50" r="40" stroke="black" stroke-width="3" fill="red" />
</svg>
''';
    final NetworkSvgLoader loader = NetworkSvgLoader(
      url: 'https://github.com/dnfield/vector_graphics',
      headers: <String, String>{'foo': 'bar'},
    );
    await tester.pumpWidget(VectorGraphic(loader: loader));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
