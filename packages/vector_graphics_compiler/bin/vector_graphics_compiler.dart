// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:args/args.dart';
import 'package:pool/pool.dart';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart';

final ArgParser argParser = ArgParser()
  ..addOption(
    'libtessellator',
    help: 'The path to a libtessellator dynamic library',
    valueHelp: 'path/to/libtessellator.dylib',
    hide: true,
  )
  ..addOption(
    'libpathops',
    help: 'The path to a libpathops dynamic library',
    valueHelp: 'path/to/libpath_ops.dylib',
    hide: true,
  )
  ..addFlag(
    'tessellate',
    help: 'Convert path fills into a tessellated shape. This will improve '
        'raster times at the cost of slightly larger file sizes.',
  )
  ..addFlag(
    'optimize-masks',
    help: 'Allows for masking optimizer to be enabled or disabled',
    defaultsTo: true,
  )
  ..addFlag(
    'optimize-clips',
    help: 'Allows for clipping optimizer to be enabled or disabled',
    defaultsTo: true,
  )
  ..addFlag(
    'optimize-overdraw',
    help: 'Allows for overdraw optimizer to be enabled or disabled',
    defaultsTo: true,
  )
  ..addOption(
    'input-dir',
    help: 'The path to a directory containing one or more SVGs. '
        'Only includes files that end with .svg. '
        'Cannot be combined with --input or --output.',
  )
  ..addOption('input',
      abbr: 'i',
      help: 'The path to a file containing a single SVG',
  )
  ..addOption(
    'output',
    abbr: 'o',
    help:
        'The path to a file where the resulting vector_graphic will be written.\n'
        'If not provided, defaults to <input-file>.vg',
  );

void loadPathOpsIfNeeded(ArgResults results) {
  if (results['optimize-masks'] == true ||
      results['optimize-clips'] == true ||
      results['optimize-overdraw'] == true) {
    if (results.wasParsed('libpathops')) {
      initializeLibPathOps(results['libpathops'] as String);
    } else {
      if (!initializePathOpsFromFlutterCache()) {
        exit(1);
      }
    }
  }
}

void validateOptions(ArgResults results) {
  if (results.wasParsed('input-dir') &&
      (results.wasParsed('input') || results.wasParsed('output'))) {
    print(
        '--input-dir cannot be combined with --input and/or --output options.');
    exit(1);
  }
  if (!results.wasParsed('input') && !results.wasParsed('input-dir')) {
    print('One of --input or --input-dir must be specified.');
    exit(1);
  }
}

Future<void> main(List<String> args) async {
  final ArgResults results;
  try {
    results = argParser.parse(args);
  } on FormatException catch (err) {
    print(err.message);
    print(argParser.usage);
    exit(1);
  }
  validateOptions(results);

  if (results['tessellate'] == true) {
    if (results.wasParsed('libtessellator')) {
      initializeLibTesselator(results['libtessellator'] as String);
    } else {
      if (!initializeTessellatorFromFlutterCache()) {
        exit(1);
      }
    }
  }

  loadPathOpsIfNeeded(results);

  final List<Pair> pairs = <Pair>[];
  if (results.wasParsed('--input-dir')) {
    final Directory directory = Directory(results['input-dir'] as String);
    for (final File file
        in directory.listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.svg')) {
        continue;
      }
      final String outputPath = '${file.path}.vg';
      pairs.add(Pair(file.path, outputPath));
    }
  } else {
    final String inputFilePath = results['input'] as String;
    final String outputFilePath =
        results['output'] as String? ?? '$inputFilePath.vg';
    pairs.add(Pair(inputFilePath, outputFilePath));
  }

  bool maskingOptimizerEnabled = true;
  bool clippingOptimizerEnabled = true;
  bool overdrawOptimizerEnabled = true;

  if (results['optimize-masks'] == false) {
    maskingOptimizerEnabled = false;
  }

  if (results['optimize-clips'] == false) {
    clippingOptimizerEnabled = false;
  }

  if (results['optimize-overdraw'] == false) {
    overdrawOptimizerEnabled = false;
  }

  if (pairs.length == 1) {
    final Uint8List bytes = await encodeSvg(
      xml: File(pairs[0].inputPath).readAsStringSync(),
      debugName: args[0],
      enableMaskingOptimizer: maskingOptimizerEnabled,
      enableClippingOptimizer: clippingOptimizerEnabled,
      enableOverdrawOptimizer: overdrawOptimizerEnabled,
    );

    File(pairs[0].outputPath).writeAsBytesSync(bytes);
  } else {
    final IsolateProcessor processor = IsolateProcessor();
    await processor.process(
      pairs,
      maskingOptimizerEnabled: maskingOptimizerEnabled,
      clippingOptimizerEnabled: clippingOptimizerEnabled,
      overdrawOptimizerEnabled: overdrawOptimizerEnabled,
    );
  }
}

class IsolateProcessor {
  final Pool pool = Pool(4);
  int _total = 0;
  int _current = 0;

  Future<void> process(
    List<Pair> pairs, {
    required bool maskingOptimizerEnabled,
    required bool clippingOptimizerEnabled,
    required bool overdrawOptimizerEnabled,
  }) async {
    _total = pairs.length;
    _current = 0;
    await Future.wait(<Future<void>>[
      for (Pair pair in pairs)
        _process(
          pair,
          maskingOptimizerEnabled: maskingOptimizerEnabled,
          clippingOptimizerEnabled: clippingOptimizerEnabled,
          overdrawOptimizerEnabled: overdrawOptimizerEnabled,
        )
    ]);
  }

  Future<void> _process(
    Pair pair, {
    required bool maskingOptimizerEnabled,
    required bool clippingOptimizerEnabled,
    required bool overdrawOptimizerEnabled,
  }) async {
    PoolResource? resource;
    try {
      resource = await pool.request();
      await Isolate.run(() async {
        final Uint8List bytes = await encodeSvg(
          xml: File(pair.inputPath).readAsStringSync(),
          debugName: pair.inputPath,
          enableMaskingOptimizer: maskingOptimizerEnabled,
          enableClippingOptimizer: clippingOptimizerEnabled,
          enableOverdrawOptimizer: overdrawOptimizerEnabled,
        );
        File(pair.outputPath).writeAsBytesSync(bytes);
      });
      _current++;
      print('Progress: $_current/$_total');
    } finally {
      resource?.release();
    }
  }
}

class Pair {
  const Pair(this.inputPath, this.outputPath);

  final String inputPath;
  final String outputPath;
}
