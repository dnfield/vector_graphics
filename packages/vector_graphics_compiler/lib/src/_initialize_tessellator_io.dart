// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import '_bin_root.dart';
import 'svg/tessellator.dart';

/// Look up the location of the tessellator from flutter's artifact cache.
bool initializeTessellatorFromFlutterCache() {
  final String executable;
  if (Platform.isWindows) {
    executable = 'libtessellator.dll';
  } else if (Platform.isMacOS) {
    executable = 'libtessellator.dylib';
  } else if (Platform.isLinux) {
    executable = 'libtessellator.so';
  } else {
    print('Tesselation not supported on ${Platform.localeName}');
    return false;
  }
  final String tessellator = '${binRootDir()}/$executable';
  if (!File(tessellator).existsSync()) {
    print('Could not locate libtessellator at $tessellator.');
    print('Ensure you are on a supported version of flutter and then run ');
    print('"flutter precache".');
    return false;
  }
  initializeLibTesselator(tessellator);
  return true;
}
