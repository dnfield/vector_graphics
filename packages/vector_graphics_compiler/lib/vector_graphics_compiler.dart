import 'dart:io';

import 'package:vector_graphics_codec/vector_graphics_codec.dart';
import 'package:vector_graphics_compiler/src/geometry/vertices.dart';

import 'src/geometry/path.dart';
import 'src/optimizers.dart';
import 'src/paint.dart';
import 'src/svg/theme.dart';
import 'src/svg/parser.dart';
import 'src/vector_instructions.dart';

export 'src/geometry/basic_types.dart';
export 'src/geometry/matrix.dart';
export 'src/geometry/path.dart';
export 'src/geometry/vertices.dart';
export 'src/optimizers.dart';
export 'src/paint.dart';
export 'src/svg/theme.dart';
export 'src/vector_instructions.dart';

/// Parses an SVG string into a [VectorInstructions] object.
Future<VectorInstructions> parse(
  String xml, {
  String key = '',
  bool warningsAsErrors = false,
  SvgTheme theme = const SvgTheme(),
}) async {
  final SvgParser parser = SvgParser(xml, theme, key, warningsAsErrors);
  return const PaintDeduplicator().optimize(await parser.parse());
}

const VectorGraphicsCodec _codec = VectorGraphicsCodec();

void main(List<String> args) async {
  if (args.length != 2) {
    print('Usage: dart vector_graphics.dart input.svg output.bin');
    exit(1);
  }
  final String xml = File(args[0]).readAsStringSync();
  final File outputFile = File(args[1]);
  final VectorInstructions instructions = await parse(xml, key: args.first);
  final VectorGraphicsBuffer buffer = VectorGraphicsBuffer();

  final Map<int, int> fillIds = <int, int>{};
  final Map<int, int> strokeIds = <int, int>{};

  int nextPaintId = 0;
  for (final Paint paint in instructions.paints) {
    final Fill? fill = paint.fill;
    final Stroke? stroke = paint.stroke;

    if (fill != null) {
      final int fillId = _codec.writeFill(
        buffer,
        fill.color?.value ?? 0,
        paint.blendMode?.index ?? 0,
      );
      fillIds[nextPaintId] = fillId;
    }
    if (stroke != null) {
      final int strokeId = _codec.writeStroke(
        buffer,
        stroke.color?.value ?? 0,
        stroke.cap?.index ?? 0,
        stroke.join?.index ?? 0,
        paint.blendMode?.index ?? 0,
        stroke.miterLimit ?? 4,
        stroke.width ?? 1,
      );
      strokeIds[nextPaintId] = strokeId;
    }
    nextPaintId += 1;
  }

  final Map<int, int> pathIds = <int, int>{};
  int nextPathId = 0;
  for (final Path path in instructions.paths) {
    final int id = _codec.writeStartPath(buffer, path.fillType.index);
    for (final PathCommand command in path.commands) {
      switch (command.type) {
        case PathCommandType.move:
          final MoveToCommand move = command as MoveToCommand;
          _codec.writeLineTo(buffer, move.x, move.y);
          break;
        case PathCommandType.line:
          final LineToCommand line = command as LineToCommand;
          _codec.writeLineTo(buffer, line.x, line.y);
          break;
        case PathCommandType.cubic:
          final CubicToCommand cubic = command as CubicToCommand;
          _codec.writeCubicTo(buffer, cubic.x1, cubic.y1, cubic.x2, cubic.y2,
              cubic.x3, cubic.y3);
          break;
        case PathCommandType.close:
          _codec.writeClose(buffer);
          break;
      }
    }
    _codec.writeFinishPath(buffer);
    pathIds[nextPathId] = id;
    nextPathId += 1;
  }

  for (final DrawCommand command in instructions.commands) {
    switch (command.type) {
      case DrawCommandType.path:
        if (fillIds.containsKey(command.paintId)) {
          _codec.writeDrawPath(
            buffer,
            pathIds[command.objectId]!,
            fillIds[command.paintId]!,
          );
        }
        if (strokeIds.containsKey(command.paintId)) {
          _codec.writeDrawPath(
            buffer,
            pathIds[command.objectId]!,
            strokeIds[command.paintId]!,
          );
        }
        break;
      case DrawCommandType.vertices:
        final IndexedVertices vertices =
            instructions.vertices[command.objectId];
        _codec.writeDrawVertices(
            buffer, vertices.vertices, vertices.indices, command.paintId);
        break;
    }
  }

  outputFile.writeAsBytesSync(buffer.done().buffer.asUint8List());
}
