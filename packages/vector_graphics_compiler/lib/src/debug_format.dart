// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:typed_data';

import 'package:vector_graphics_codec/vector_graphics_codec.dart';

/// Write an unstable but human readable form of the vector graphics binary
/// package intended to be used for debugging and development.
Uint8List dumpToDebugFormat(Uint8List bytes) {
  const VectorGraphicsCodec codec = VectorGraphicsCodec();
  final _DebugVectorGraphicsListener listener = _DebugVectorGraphicsListener();
  final DecodeResponse response =
      codec.decode(bytes.buffer.asByteData(), listener);
  if (!response.complete) {
    codec.decode(bytes.buffer.asByteData(), listener, response: response);
  }
  return utf8.encode(listener.buffer.toString()) as Uint8List;
}

class _DebugVectorGraphicsListener extends VectorGraphicsCodecListener {
  final StringBuffer buffer = StringBuffer();

  @override
  void onClipPath(int pathId) {
    buffer.writeln('ApplyClip: $pathId');
  }

  @override
  void onDrawImage(int imageId, double x, double y, double width, double height,
      Float64List? transform) {
    buffer.writeln(
        'DrawImage: $imageId (Rect.fromLTWH($x, $y, $width, $height), transform: $transform)');
  }

  @override
  void onDrawPath(int pathId, int? paintId, int? patternId) {
    buffer.writeln('DrawPath: $pathId ($paintId, $patternId)');
  }

  @override
  void onDrawText(int textId, int paintId, int? patternId) {
    buffer.writeln('DrawText: $textId ($paintId, $patternId)');
  }

  @override
  void onDrawVertices(Float32List vertices, Uint16List? indices, int? paintId) {
    buffer.writeln(
        'DrawVertices: ${vertices.lengthInBytes} (${indices?.lengthInBytes ?? 0}, $paintId)');
  }

  @override
  void onImage(int imageId, int format, Uint8List data) {
    buffer.writeln('StoreImage: $imageId ($format, ${data.lengthInBytes}');
  }

  @override
  void onLinearGradient(double fromX, double fromY, double toX, double toY,
      Int32List colors, Float32List? offsets, int tileMode, int id) {
    buffer.writeln(
        'StoreGradient: $id Linear(from: ($fromX, $fromY), to: ($toX, $toY), '
        'colors: $colors, offsets: $offsets, tileMode: $tileMode');
  }

  @override
  void onMask() {
    buffer.writeln('BeginMask:');
  }

  @override
  void onPaintObject({
    required int color,
    required int? strokeCap,
    required int? strokeJoin,
    required int blendMode,
    required double? strokeMiterLimit,
    required double? strokeWidth,
    required int paintStyle,
    required int id,
    required int? shaderId,
  }) {
    // Fill
    if (paintStyle == 0) {
      buffer.writeln(
          'StorePaint: $id Fill($color, blendMode: $blendMode, shader: $shaderId');
    } else {
      buffer.writeln(
          'StorePaint: $id Stroke($color, strokeCap: $strokeCap, $strokeJoin: $strokeJoin, '
          'blendMode: $blendMode, strokeMiterLimit: $strokeMiterLimit, strokeWidth: $strokeWidth, shader: $shaderId');
    }
  }

  @override
  void onPathClose() {
    buffer.writeln('  close()');
  }

  @override
  void onPathCubicTo(
      double x1, double y1, double x2, double y2, double x3, double y3) {
    buffer.writeln('  cubicTo(($x1, $y1), ($x2, $y2), ($x3, $y3)');
  }

  @override
  void onPathFinished() {
    buffer.writeln('EndPath:');
  }

  @override
  void onPathLineTo(double x, double y) {
    buffer.writeln('  lineTo($x, $y)');
  }

  @override
  void onPathMoveTo(double x, double y) {
    buffer.writeln('  moveTo($x, $y)');
  }

  @override
  void onPathStart(int id, int fillType) {
    buffer.writeln('PathStart: $id ${fillType == 0 ? 'Fill' : 'Stroke'}');
  }

  @override
  void onPatternStart(int patternId, double x, double y, double width,
      double height, Float64List transform) {
    buffer.writeln(
        'StorePattern: $patternId (Rect.fromLTWH($x, $y, $width, $height), transform: $transform)');
  }

  @override
  void onRadialGradient(
      double centerX,
      double centerY,
      double radius,
      double? focalX,
      double? focalY,
      Int32List colors,
      Float32List? offsets,
      Float64List? transform,
      int tileMode,
      int id) {
    buffer.writeln(
        'StoreGradient: $id Radial(center: ($centerX, $centerY), radius: $radius,'
        ' focal: ($focalX, $focalY), colors: $colors, offsets: $offsets, '
        'transform: $transform, tileMode: $tileMode');
  }

  @override
  void onRestoreLayer() {
    buffer.writeln('Restore:');
  }

  @override
  void onSaveLayer(int paintId) {
    buffer.writeln('SaveLayer: $paintId');
  }

  @override
  void onSize(double width, double height) {
    buffer.writeln('RecordSize: Size($width, $height)');
  }

  @override
  void onTextConfig(
    String text,
    String? fontFamily,
    double x,
    double y,
    int fontWeight,
    double fontSize,
    Float64List? transform,
    int id,
  ) {
    buffer.writeln(
        'RecordText: $id ($text, ($x, $y), weight: $fontWeight, size: $fontSize, family: $fontFamily, transform: $transform)');
  }
}
