// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:html';
import 'dart:typed_data';

import 'package:vector_graphics_compiler/vector_graphics_compiler.dart';

/// Load an SVG string from the given [url] and with optional [headers].
///
/// The web implementation does not support loading with headers.
Future<ByteData> loadBytes(String url, Map<String, String>? headers) async {
  final String data = await HttpRequest.getString(url);
  final Uint8List compiledBytes = await encodeSvg(
    xml: data,
    debugName: url,
    enableClippingOptimizer: false,
    enableMaskingOptimizer: false,
    enableOverdrawOptimizer: false,
  );
  return compiledBytes.buffer.asByteData();
}
