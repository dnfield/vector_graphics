// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:vector_graphics/vector_graphics.dart';

import 'src/loader.dart' as loader;

/// A [BytesLoader] that downloads and compiles an SVG from the network.
///
/// Unlike bundled vector graphics, this loader must compile the SVG to the
/// vector graphic on device. As a result, fewer optimizations can be applied
/// and the initial load is significantly more expensive. The impact of this
/// expense is limited by running the download and compilation on a background
/// isolate on Flutter mobile and desktop.
///
/// In general, the usage of this loader should be minimized and the
/// [AssetBytesLoader] or [NetworkBytesLoader] should be used instead.
class NetworkSvgLoader extends BytesLoader {
  /// Create a new [NetworkSvgLoader] from a [url] and optional [headers].
  const NetworkSvgLoader({required this.url, this.headers});

  /// The URL at which an SVG asset is expected to be located.
  final String url;

  /// Additional headers that may be added to the network request.
  ///
  /// This functionality is not supported on the web.
  final Map<String, String>? headers;

  @override
  Future<ByteData> loadBytes(BuildContext context) async {
    return loader.loadBytes(url, headers);
  }

  @override
  int get hashCode => Object.hash(
      url, headers != null ? Object.hashAll(headers!.entries) : null);

  @override
  bool operator ==(Object other) {
    return other is NetworkSvgLoader &&
        other.url == url &&
        _mapEquals(other.headers, headers);
  }
}

bool _mapEquals(Map<String, String>? left, Map<String, String>? right) {
  if (left == right) {
    return true;
  }
  if (left == null && right != null) {
    return false;
  }
  if (right == null && left != null) {
    return false;
  }
  right!;
  left!;
  if (left.length != right.length) {
    return false;
  }
  for (final String key in left.keys) {
    if (right[key] != left[key]) {
      return false;
    }
  }
  return true;
}
