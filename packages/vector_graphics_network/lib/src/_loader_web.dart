// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:html';

/// Load an SVG string from the given [url] and with optional [headers].
///
/// The web implementation does not support loading with headers.
Future<String> loadData(String url, Map<String, String>? headers) async {
  return HttpRequest.getString(url);
}
