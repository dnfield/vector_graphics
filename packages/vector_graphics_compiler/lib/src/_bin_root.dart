// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ffi';
import 'dart:io';

/// Get executable root directory
String binRootDir() {
  final Directory cacheRoot;
  if (Platform.resolvedExecutable.contains('flutter_tester')) {
    cacheRoot = File(Platform.resolvedExecutable).parent.parent.parent.parent;
  } else if (Platform.resolvedExecutable.contains('dart')) {
    cacheRoot = File(Platform.resolvedExecutable).parent.parent.parent;
  } else {
    throw Exception('Unknown executable: ${Platform.resolvedExecutable}');
  }
  final String platform;
  if (Platform.isWindows) {
    if (Abi.current() == Abi.windowsX64) {
      platform = 'windows-x64';
    } else if (Abi.current() == Abi.windowsArm64) {
      platform = 'windows-arm64';
    } else {
      throw Exception('Unsupported ABI: ${Abi.current()}');
    }
  } else if (Platform.isMacOS) {
    platform = 'darwin-x64';
  } else if (Platform.isLinux) {
    if (Abi.current() == Abi.linuxX64) {
      platform = 'linux-x64';
    } else if (Abi.current() == Abi.linuxArm64) {
      platform = 'linux-arm64';
    } else {
      throw Exception('Unsupported ABI: ${Abi.current()}');
    }
  } else {
    throw Exception('Cannot identify platform ${Platform.localeName}');
  }
  final String output = '${cacheRoot.path}/artifacts/engine/$platform/';
  if (!Directory(output).existsSync()) {
    throw Exception('Could not find directory $output for executables');
  }
  return output;
}
