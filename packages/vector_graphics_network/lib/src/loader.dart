// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart';

import '_loader_io.dart' if (dart.library.html) '_loader_web.dart' as loader;

/// A debug only testing override to control the network response string.
@visibleForTesting
String? debugLoadDataResultOverride;

/// Load the network bytes from the given [url].
Future<ByteData> loadBytes(
  String url,
  Map<String, String>? headers,
) async {
  return compute(
    (List<Object?> args) async {
      final String data;
      if (kDebugMode && args[2] != null) {
        data = args[2] as String;
      } else {
        data = await loader.loadData(
          args[0] as String,
          args[1] as Map<String, String>?,
        );
      }
      final Uint8List compiledBytes = await encodeSvg(
        xml: data,
        debugName: args[0] as String,
        enableClippingOptimizer: false,
        enableMaskingOptimizer: false,
        enableOverdrawOptimizer: false,
      );
      return compiledBytes.buffer.asByteData();
    },
    <Object?>[url, headers, debugLoadDataResultOverride],
    debugLabel: 'NetworkSvgLoader|$url',
  );
}
