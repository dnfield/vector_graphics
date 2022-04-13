// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart';

final ArgParser argParser = ArgParser()
  ..addOption(
    'libtesselator',
    help: 'The path to a libtesselator dynamic library.\n'
        'When this value is provided, fill paths will be tesselated \n'
        'into vertices.',
    valueHelp: 'path/to/libtesselator.dylib',
    hide: true,
  )
  ..addOption('input',
      abbr: 'i',
      help: 'The path to a file containing a single SVG',
      mandatory: true)
  ..addOption(
    'output',
    abbr: 'o',
    help:
        'The path to a file where the resulting vector_graphic will be written.\n'
        'If not provided, defaults to <input-file>.vg',
  );

Future<void> main(List<String> args) async {
  final ArgResults results;
  try {
    results = argParser.parse(args);
  } on FormatException catch (err) {
    print(err.message);
    print(argParser.usage);
    exit(1);
  }
  if (results.wasParsed('libtesselator')) {
    initializeLibTesselator(results['libtesselator'] as String);
  }

  final String inputFilePath = results['input'] as String;
  final String xml = File(inputFilePath).readAsStringSync();
  final File outputFile =
      File(results['output'] as String? ?? '$inputFilePath.vg');
  final Uint8List bytes = await encodeSvg(xml, args[0]);

  outputFile.writeAsBytesSync(bytes);
}
