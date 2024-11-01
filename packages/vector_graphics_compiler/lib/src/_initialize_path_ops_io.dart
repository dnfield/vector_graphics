// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import '_bin_root.dart';
import 'svg/path_ops.dart';

/// Look up the location of the pathops from flutter's artifact cache.
bool initializePathOpsFromFlutterCache() {
  final String executable;
  if (Platform.isWindows) {
    executable = 'path_ops.dll';
  } else if (Platform.isMacOS) {
    executable = 'libpath_ops.dylib';
  } else if (Platform.isLinux) {
    executable = 'libpath_ops.so';
  } else {
    print('path_ops not supported on ${Platform.localeName}');
    return false;
  }
  final String pathops = '${binRootDir()}/$executable';
  if (!File(pathops).existsSync()) {
    print('Could not locate libpathops at $pathops.');
    print('Ensure you are on a supported version of flutter and then run ');
    print('"flutter precache".');
    return false;
  }
  initializeLibPathOps(pathops);
  return true;
}
