import 'dart:typed_data';

import 'package:tessellator/tessellator.dart';

import 'geometry/path.dart';
import 'geometry/vertices.dart';
import 'paint.dart';
import 'vector_instructions.dart';

/// An optimization pass for a [VectorInstructions] object.
///
/// For example, an optimizer may de-duplicate objects or transform objects
/// into more efficiently drawable objects.
///
/// Optimizers are composable, but may expect certain ordering to reach maximum
/// efficiency.
abstract class Optimizer {
  /// Allows inheriting classes to create const instances.
  const Optimizer();

  /// Takes `original` and produces a new object that is optimized.
  VectorInstructions optimize(VectorInstructions original);
}

/// An optimizer that removes duplicate [Paint] objects and rewrites
/// [DrawCommand]s to refer to the updated paint index.
///
/// The resulting [VectorInstructions.paints] is effectively the original paint
/// list converted to a set and then back to a list.
class PaintDeduplicator extends Optimizer {
  /// Creates a new paint deduplicator.
  const PaintDeduplicator();

  @override
  VectorInstructions optimize(VectorInstructions original) {
    final VectorInstructions result = VectorInstructions(
      width: original.width,
      height: original.height,
      paths: original.paths,
      vertices: original.vertices,
      paints: <Paint>[],
      commands: <DrawCommand>[],
    );

    final Map<Paint, int> paints = <Paint, int>{};
    for (final DrawCommand command in original.commands) {
      if (command.paintId == -1) {
        result.commands.add(command);
        continue;
      }
      final Paint originalPaint = original.paints[command.paintId];
      final int paintId = paints.putIfAbsent(
        original.paints[command.paintId],
        () {
          result.paints.add(originalPaint);
          return result.paints.length - 1;
        },
      );
      result.commands.add(DrawCommand(
        command.objectId,
        paintId,
        command.type,
        command.debugString,
      ));
    }
    return result;
  }
}

class PathTessellator extends Optimizer {
  const PathTessellator();

  @override
  VectorInstructions optimize(VectorInstructions original) {
    final Map<int, Path> combinedPaths = <int, Path>{};

    final VectorInstructions result = VectorInstructions(
      width: original.width,
      height: original.height,
      paints: original.paints,
      vertices: <IndexedVertices>[],
      commands: <DrawCommand>[],
    );

    for (final DrawCommand command in original.commands) {
      final Path originalPath = original.paths[command.objectId];
      if (combinedPaths.containsKey(command.paintId)) {
        combinedPaths[command.paintId] =
            (PathBuilder.fromPath(combinedPaths[command.paintId]!)
                  ..addPath(originalPath))
                .toPath();
      } else {
        combinedPaths[command.paintId] = originalPath;
      }
    }

    for (final MapEntry<int, Path> entry in combinedPaths.entries) {
      final VerticesBuilder builder = VerticesBuilder();
      for (final PathCommand pathCommand in entry.value.commands) {
        switch (pathCommand.type) {
          case PathCommandType.move:
            final MoveToCommand move = pathCommand as MoveToCommand;
            builder.moveTo(move.x, move.y);
            break;
          case PathCommandType.line:
            final LineToCommand line = pathCommand as LineToCommand;
            builder.lineTo(line.x, line.y);
            break;
          case PathCommandType.cubic:
            final CubicToCommand cubic = pathCommand as CubicToCommand;
            builder.cubicTo(
              cubic.x1,
              cubic.y1,
              cubic.x2,
              cubic.y2,
              cubic.x3,
              cubic.y3,
            );
            break;
          case PathCommandType.close:
            builder.close();
            break;
        }
      }
      final Float32List vertices = builder.tessellate(
        smoothing: const SmoothingApproximation(scale: 0.1),
      );
      result.commands.add(DrawCommand(
          result.vertices.length, entry.key, DrawCommandType.vertices, ''));
      result.vertices.add(Vertices.fromFloat32List(vertices).createIndex());
      builder.dispose();
    }
    return result;
  }
}
