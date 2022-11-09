// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert' show base64;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_graphics/src/listener.dart';
import 'package:vector_graphics/vector_graphics_compat.dart';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart';

void main() {
  const String svgString = '''
<svg width="10" height="10">
  <rect x="0" y="0" height="15" width="15" fill="black" />
</svg>
''';

  const String bluePngPixel =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPj/HwADBwIAMCbHYQAAAABJRU5ErkJggg==';

  late ByteData vectorGraphicBuffer;

  setUpAll(() async {
    final Uint8List bytes = await encodeSvg(
      xml: svgString,
      debugName: 'test',
      enableClippingOptimizer: false,
      enableMaskingOptimizer: false,
      enableOverdrawOptimizer: false,
    );
    vectorGraphicBuffer = bytes.buffer.asByteData();
  });

  test('decode without clip', () async {
    final PictureInfo info = await decodeVectorGraphics(
      vectorGraphicBuffer,
      locale: ui.PlatformDispatcher.instance.locale,
      textDirection: ui.TextDirection.ltr,
      clipViewbox: true,
      loader: const AssetBytesLoader('test'),
    );
    final ui.Image image = info.picture.toImageSync(15, 15);
    final Uint32List imageBytes =
        (await image.toByteData())!.buffer.asUint32List();
    expect(imageBytes.first, 0xFF000000);
    expect(imageBytes.last, 0x00000000);
  }, skip: kIsWeb);

  test('decode with clip', () async {
    final PictureInfo info = await decodeVectorGraphics(
      vectorGraphicBuffer,
      locale: ui.PlatformDispatcher.instance.locale,
      textDirection: ui.TextDirection.ltr,
      clipViewbox: false,
      loader: const AssetBytesLoader('test'),
    );
    final ui.Image image = info.picture.toImageSync(15, 15);
    final Uint32List imageBytes =
        (await image.toByteData())!.buffer.asUint32List();
    expect(imageBytes.first, 0xFF000000);
    expect(imageBytes.last, 0xFF000000);
  }, skip: kIsWeb);

  test('Scales image correctly', () async {
    final TestPictureFactory factory = TestPictureFactory();
    final FlutterVectorGraphicsListener listener =
        FlutterVectorGraphicsListener(
      pictureFactory: factory,
    );
    listener.onImage(0, 0, base64.decode(bluePngPixel));
    await listener.waitForImageDecode();
    listener.onDrawImage(0, 10, 10, 30, 30, null);
    final Invocation drawRect = factory.fakeCanvases.first.invocations.single;
    expect(drawRect.isMethod, true);
    expect(drawRect.memberName, #drawImageRect);
    expect(drawRect.positionalArguments[1], const ui.Rect.fromLTRB(0, 0, 1, 1));
    expect(drawRect.positionalArguments[2],
        const ui.Rect.fromLTRB(10, 10, 40, 40));
  });
}

class TestPictureFactory implements PictureFactory {
  final List<FakeCanvas> fakeCanvases = <FakeCanvas>[];
  @override
  ui.Canvas createCanvas(ui.PictureRecorder recorder) {
    fakeCanvases.add(FakeCanvas());
    return fakeCanvases.last;
  }

  @override
  ui.PictureRecorder createPictureRecorder() => FakePictureRecorder();
}

class FakePictureRecorder extends Fake implements ui.PictureRecorder {}

class FakeCanvas implements ui.Canvas {
  final List<Invocation> invocations = <Invocation>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    invocations.add(invocation);
  }
}
