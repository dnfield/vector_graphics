// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:developer';
// ignore: unnecessary_import
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vector_graphics/vector_graphics.dart';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vector Graphics Demo',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const Scaffold(
        body: Center(
          child: VectorGraphic(
            loader: NetworkSvgLoader(
              'https://upload.wikimedia.org/wikipedia/commons/f/fd/Ghostscript_Tiger.svg',
            ),
          ),
        ),
      ),
    );
  }
}

class NetworkSvgLoader extends BytesLoader {
  const NetworkSvgLoader(this.url);

  final String url;

  @override
  Future<ByteData> loadBytes(BuildContext context) async {
    return await compute((String svgUrl) async {
      final http.Response request = await http.get(Uri.parse(svgUrl));
      final TimelineTask task = TimelineTask()..start('encodeSvg');
      final Uint8List compiledBytes = await encodeSvg(request.body, svgUrl);
      task.finish();
      // sendAndExit will make sure this isn't copied.
      return compiledBytes.buffer.asByteData();
    }, url, debugLabel: 'Load Bytes');
  }

  @override
  int get hashCode => url.hashCode;

  @override
  bool operator ==(Object other) {
    return other is NetworkSvgLoader && other.url == url;
  }
}
