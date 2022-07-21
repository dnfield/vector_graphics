// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:typed_data';

import 'package:vector_graphics_codec/vector_graphics_codec.dart';
import 'package:vector_graphics_compiler/src/geometry/matrix.dart';

import 'src/geometry/vertices.dart';
import 'src/geometry/path.dart';
import 'src/paint.dart';
import 'src/svg/theme.dart';
import 'src/svg/parser.dart';
import 'src/vector_instructions.dart';

export 'src/geometry/basic_types.dart';
export 'src/geometry/matrix.dart';
export 'src/geometry/path.dart';
export 'src/geometry/vertices.dart';
export 'src/paint.dart';
export 'src/svg/theme.dart';
export 'src/vector_instructions.dart';
export 'src/svg/tessellator.dart' show initializeLibTesselator;
export 'src/svg/path_ops.dart' show initializeLibPathOps;

export 'src/initialize_tessellator.dart'
    show initializeTessellatorFromFlutterCache;
export 'src/initialize_path_ops.dart' show initializePathOpsFromFlutterCache;

/// Parses an SVG string into a [VectorInstructions] object.
Future<VectorInstructions> parse(
  String xml, {
  String key = '',
  bool warningsAsErrors = false,
  SvgTheme theme = const SvgTheme(),
  bool enableMaskingOptimizer = true,
}) async {
  final SvgParser parser = SvgParser(xml, theme, key, warningsAsErrors);
  parser.enableMaskingOptimizer = enableMaskingOptimizer;
  return parser.parse();
}

Float64List? _encodeMatrix(AffineMatrix? matrix) {
  if (matrix == null || matrix == AffineMatrix.identity) {
    return null;
  }
  return matrix.toMatrix4();
}

void _encodeShader(
  Gradient? shader,
  Map<Gradient, int> shaderIds,
  VectorGraphicsCodec codec,
  VectorGraphicsBuffer buffer,
) {
  if (shader == null) {
    return;
  }
  int shaderId;
  if (shader is LinearGradient) {
    shaderId = codec.writeLinearGradient(
      buffer,
      fromX: shader.from.x,
      fromY: shader.from.y,
      toX: shader.to.x,
      toY: shader.to.y,
      colors: Int32List.fromList(
          <int>[for (Color color in shader.colors!) color.value]),
      offsets: Float32List.fromList(shader.offsets!),
      tileMode: shader.tileMode!.index,
    );
  } else if (shader is RadialGradient) {
    shaderId = codec.writeRadialGradient(
      buffer,
      centerX: shader.center.x,
      centerY: shader.center.y,
      radius: shader.radius,
      focalX: shader.focalPoint?.x,
      focalY: shader.focalPoint?.y,
      colors: Int32List.fromList(
          <int>[for (Color color in shader.colors!) color.value]),
      offsets: Float32List.fromList(shader.offsets!),
      tileMode: shader.tileMode!.index,
      transform: _encodeMatrix(shader.transform),
    );
  } else {
    assert(false);
    throw StateError('illegal shader type: $shader');
  }
  shaderIds[shader] = shaderId;
}

/// String input, String filename
/// Encode an SVG [input] string into a vector_graphics binary format.
Future<Uint8List> encodeSvg(String xml, String debugName,
    {bool? enableMaskingOptimizer}) async {
  const VectorGraphicsCodec codec = VectorGraphicsCodec();
  final VectorInstructions instructions = await parse(xml,
      key: debugName, enableMaskingOptimizer: enableMaskingOptimizer!);
  final VectorGraphicsBuffer buffer = VectorGraphicsBuffer();

  codec.writeSize(buffer, instructions.width, instructions.height);

  final Map<int, int> fillIds = <int, int>{};
  final Map<int, int> strokeIds = <int, int>{};
  final Map<Gradient, int> shaderIds = <Gradient, int>{};

  for (final Paint paint in instructions.paints) {
    _encodeShader(paint.fill?.shader, shaderIds, codec, buffer);
    _encodeShader(paint.stroke?.shader, shaderIds, codec, buffer);
  }

  int nextPaintId = 0;
  for (final Paint paint in instructions.paints) {
    final Fill? fill = paint.fill;
    final Stroke? stroke = paint.stroke;

    if (fill != null) {
      final int? shaderId = shaderIds[fill.shader];
      final int fillId = codec.writeFill(
        buffer,
        fill.color.value,
        paint.blendMode.index,
        shaderId,
      );
      fillIds[nextPaintId] = fillId;
    }
    if (stroke != null) {
      final int? shaderId = shaderIds[stroke.shader];
      final int strokeId = codec.writeStroke(
        buffer,
        stroke.color.value,
        stroke.cap?.index ?? 0,
        stroke.join?.index ?? 0,
        paint.blendMode.index,
        stroke.miterLimit ?? 4,
        stroke.width ?? 1,
        shaderId,
      );
      strokeIds[nextPaintId] = strokeId;
    }
    nextPaintId += 1;
  }

  final Map<int, int> pathIds = <int, int>{};
  int nextPathId = 0;
  for (final Path path in instructions.paths) {
    final List<int> controlPointTypes = <int>[];
    final List<double> controlPoints = <double>[];

    for (final PathCommand command in path.commands) {
      switch (command.type) {
        case PathCommandType.move:
          final MoveToCommand move = command as MoveToCommand;
          controlPointTypes.add(ControlPointTypes.moveTo);
          controlPoints.addAll(<double>[move.x, move.y]);
          break;
        case PathCommandType.line:
          final LineToCommand line = command as LineToCommand;
          controlPointTypes.add(ControlPointTypes.lineTo);
          controlPoints.addAll(<double>[line.x, line.y]);
          break;
        case PathCommandType.cubic:
          final CubicToCommand cubic = command as CubicToCommand;
          controlPointTypes.add(ControlPointTypes.cubicTo);
          controlPoints.addAll(<double>[
            cubic.x1,
            cubic.y1,
            cubic.x2,
            cubic.y2,
            cubic.x3,
            cubic.y3,
          ]);
          break;
        case PathCommandType.close:
          controlPointTypes.add(ControlPointTypes.close);
          break;
      }
    }
    final int id = codec.writePath(
      buffer,
      Uint8List.fromList(controlPointTypes),
      Float32List.fromList(controlPoints),
      path.fillType.index,
    );
    pathIds[nextPathId] = id;
    nextPathId += 1;
  }

  for (final TextConfig textConfig in instructions.text) {
    codec.writeTextConfig(
      buffer: buffer,
      text: textConfig.text,
      fontFamily: textConfig.fontFamily,
      x: textConfig.baselineStart.x,
      y: textConfig.baselineStart.y,
      fontWeight: textConfig.fontWeight.index,
      fontSize: textConfig.fontSize,
      transform: _encodeMatrix(textConfig.transform),
    );
  }

  for (final DrawCommand command in instructions.commands) {
    switch (command.type) {
      case DrawCommandType.path:
        if (fillIds.containsKey(command.paintId)) {
          codec.writeDrawPath(
            buffer,
            pathIds[command.objectId]!,
            fillIds[command.paintId]!,
          );
        }
        if (strokeIds.containsKey(command.paintId)) {
          codec.writeDrawPath(
            buffer,
            pathIds[command.objectId]!,
            strokeIds[command.paintId]!,
          );
        }
        break;
      case DrawCommandType.vertices:
        final IndexedVertices vertices =
            instructions.vertices[command.objectId!];
        final int fillId = fillIds[command.paintId]!;
        codec.writeDrawVertices(
            buffer, vertices.vertices, vertices.indices, fillId);
        break;
      case DrawCommandType.saveLayer:
        codec.writeSaveLayer(buffer, fillIds[command.paintId]!);
        break;
      case DrawCommandType.restore:
        codec.writeRestoreLayer(buffer);
        break;
      case DrawCommandType.clip:
        codec.writeClipPath(buffer, pathIds[command.objectId]!);
        break;
      case DrawCommandType.mask:
        codec.writeMask(buffer);
        break;
      case DrawCommandType.text:
        if (fillIds.containsKey(command.paintId)) {
          codec.writeDrawText(
            buffer,
            command.objectId!,
            fillIds[command.paintId]!,
          );
        }
        if (strokeIds.containsKey(command.paintId)) {
          codec.writeDrawText(
            buffer,
            command.objectId!,
            strokeIds[command.paintId]!,
          );
        }
        break;
    }
  }
  return buffer.done().buffer.asUint8List();
}
