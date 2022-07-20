// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:test/test.dart';
import 'package:vector_graphics_compiler/src/svg/path_ops.dart';
import 'package:vector_graphics_compiler/src/initialize_path_ops.dart'
    as vector_graphics;

void main() {
  setUpAll(() {
    if (!vector_graphics.initializePathOpsFromFlutterCache()) {
      fail('error in setup');
    }
  });
  test('Path tests', () {
    final Path path = Path()
      ..lineTo(10, 0)
      ..lineTo(10, 10)
      ..lineTo(0, 10)
      ..close()
      ..cubicTo(30, 30, 40, 40, 50, 50);

    expect(path.fillType, FillType.nonZero);
    expect(path.verbs.toList(), <PathVerb>[
      PathVerb.moveTo, // Skia inserts a moveTo here.
      PathVerb.lineTo,
      PathVerb.lineTo,
      PathVerb.lineTo,
      PathVerb.close,
      PathVerb.moveTo, // Skia inserts a moveTo here.
      PathVerb.cubicTo,
    ]);
    expect(path.points,
        <double>[0, 0, 10, 0, 10, 10, 0, 10, 0, 0, 30, 30, 40, 40, 50, 50]);

    final SvgPathProxy proxy = SvgPathProxy();
    path.replay(proxy);
    expect(proxy.toString(),
        'M0.0,0.0L10.0,0.0L10.0,10.0L0.0,10.0ZM0.0,0.0C30.0,30.0 40.0,40.0 50.0,50.0');
    path.dispose();
  });

  test('Ops test', () {
    final Path cubics = Path()
      ..moveTo(16, 128)
      ..cubicTo(16, 66, 66, 16, 128, 16)
      ..cubicTo(240, 66, 16, 66, 240, 128)
      ..close();

    final Path quad = Path()
      ..moveTo(55, 16)
      ..lineTo(200, 80)
      ..lineTo(198, 230)
      ..lineTo(15, 230)
      ..close();

    final Path intersection = cubics.applyOp(quad, PathOp.intersect);

    expect(intersection.verbs, <PathVerb>[
      PathVerb.moveTo,
      PathVerb.lineTo,
      PathVerb.cubicTo,
      PathVerb.lineTo,
      PathVerb.cubicTo,
      PathVerb.cubicTo,
      PathVerb.lineTo,
      PathVerb.lineTo,
      PathVerb.close
    ]);
    expect(intersection.points, <double>[
      34.06542205810547, 128.0, // move
      48.90797424316406, 48.59233856201172, // line
      57.80497360229492, 39.73065185546875, 68.189697265625, 32.3614387512207,
      79.66168212890625, 26.885154724121094, // cubic
      151.7936248779297, 58.72270584106445, // line
      150.66123962402344, 59.74142837524414, 149.49365234375,
      60.752471923828125, 148.32867431640625, 61.76123809814453, // cubic
      132.3506317138672, 75.59684753417969, 116.86703491210938,
      89.0042953491211, 199.52090454101562, 115.93260192871094, // cubic
      199.36000061035156, 128.0, // line
      34.06542205810547, 128.0, // line
      // close
    ]);
    cubics.dispose();
    quad.dispose();
    intersection.dispose();
  });
}
