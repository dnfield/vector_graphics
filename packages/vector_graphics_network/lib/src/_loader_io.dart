// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'network_isolate.dart';

NetworkIsolate? _isolate;
final Future<NetworkIsolate> _pendingIsolate =
    NetworkIsolate.create().then((NetworkIsolate isolate) {
  return _isolate = isolate;
});

/// Load an SVG string from the given [url] and with optional [headers].
///
/// The web implementation does not support loading with headers.
Future<ByteData> loadBytes(String url, Map<String, String>? headers) async {
  if (_isolate == null) {
    await _pendingIsolate;
  }
  return _isolate!.getUrl(url, headers);
}
