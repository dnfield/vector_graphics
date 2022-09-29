// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';

import '_loader_io.dart' if (dart.library.html) '_loader_web.dart' as loader;

/// Load the network bytes from the given [url].
Future<ByteData> loadBytes(
  String url,
  Map<String, String>? headers,
) =>
    loader.loadBytes(url, headers);
