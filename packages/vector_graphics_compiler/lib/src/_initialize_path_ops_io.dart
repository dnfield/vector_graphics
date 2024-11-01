// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ffi';
import 'dart:io';

import 'svg/path_ops.dart';

/// Look up the location of the pathops from flutter's artifact cache.
bool initializePathOpsFromFlutterCache() {
  final Directory cacheRoot;
  if (Platform.resolvedExecutable.contains('flutter_tester')) {
    cacheRoot = File(Platform.resolvedExecutable).parent.parent.parent.parent;
  } else if (Platform.resolvedExecutable.contains('dart')) {
    cacheRoot = File(Platform.resolvedExecutable).parent.parent.parent;
  } else {
    print('Unknown executable: ${Platform.resolvedExecutable}');
    return false;
  }

  final String platform;
  final String executable;
  if (Platform.isWindows) {
    if (Abi.current() == Abi.windowsX64) {
      platform = 'windows-x64';
    } else if (Abi.current() == Abi.windowsArm64) {
      platform = 'windows-arm64';
    } else {
      throw Exception('Unsupported ABI: ${Abi.current()}');
    }
    executable = 'path_ops.dll';
  } else if (Platform.isMacOS) {
    if (Abi.current() == Abi.macosX64) {
      platform = 'darwin-x64';
    } else if (Abi.current() == Abi.macosArm64) {
      platform = 'darwin-arm64';
    } else {
      throw Exception('Unsupported ABI: ${Abi.current()}');
    }
    executable = 'libpath_ops.dylib';
  } else if (Platform.isLinux) {
    if (Abi.current() == Abi.linuxX64) {
      platform = 'linux-x64';
    } else if (Abi.current() == Abi.linuxArm64) {
      platform = 'linux-arm64';
    } else {
      throw Exception('Unsupported ABI: ${Abi.current()}');
    }
    executable = 'libpath_ops.so';
  } else {
    print('path_ops not supported on ${Platform.localeName}');
    return false;
  }
  final String pathops =
      '${cacheRoot.path}/artifacts/engine/$platform/$executable';
  if (!File(pathops).existsSync()) {
    print('Could not locate libpathops at $pathops.');
    print('Ensure you are on a supported version of flutter and then run ');
    print('"flutter precache".');
    return false;
  }
  initializeLibPathOps(pathops);
  return true;
}
