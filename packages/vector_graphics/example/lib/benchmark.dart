// ignore this while we wait for framework to catch up with g3.
// ignore: unnecessary_import
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vector_graphics/vector_graphics.dart';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart';
import 'package:vector_graphics/src/listener.dart';

const String svgUrl =
    'https://upload.wikimedia.org/wikipedia/commons/f/fd/Ghostscript_Tiger.svg';

void main() async {
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: Center(
          child: TextButton(
            child: Text('START'),
            onPressed: bench,
          ),
        ),
      ),
    ),
  );
}

Future<void> bench() async {
  final http.Response request = await http.get(Uri.parse(svgUrl));
  final Uint8List compiledBytes = await encodeSvg(request.body, svgUrl);
  print('start');
  for (var i = 0; i < 1000; i++) {
    final PictureInfo pictureInfo = decodeVectorGraphics(
      compiledBytes.buffer.asByteData(),
      locale: null,
      textDirection: null,
    );
  }
  print('done');
}
