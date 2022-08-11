// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Load an SVG string from the given [url] and with optional [headers].
///
/// The web implementation does not support loading with headers.
Future<String> loadData(String url, Map<String, String>? headers) async {
  final HttpClient client = HttpClient()..autoUncompress = false;
  final Uri resolved = Uri.base.resolve(url);
  final HttpClientRequest request = await client.getUrl(resolved);
  headers?.forEach(request.headers.add);
  final HttpClientResponse response = await request.close();
  if (response.statusCode != HttpStatus.ok) {
    // The network may be only temporarily unavailable, or the file will be
    // added on the server later. Avoid having future calls to resolve
    // fail to check the network again.
    await response.drain<List<int>>(<int>[]);
    throw Exception('statusCode: ${response.statusCode}, uri: $resolved');
  }
  final Uint8List bytes = await consolidateHttpClientResponseBytes(
    response,
  );
  return utf8.decode(bytes);
}
