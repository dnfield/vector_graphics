import 'dart:typed_data';

import 'package:tessellator/tessellator.dart';

import 'geometry/path.dart';
import 'geometry/vertices.dart';
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

/// Optimizes path fills into tessellated vertices.
class PathTessellator extends Optimizer {
  /// Creates an optimizer that optimizes path fills into vertices.
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
      final Path originalPath = original.paths[command.objectId!];
      if (combinedPaths.containsKey(command.paintId)) {
        combinedPaths[command.paintId!] =
            (PathBuilder.fromPath(combinedPaths[command.paintId]!)
                  ..addPath(originalPath))
                .toPath();
      } else {
        combinedPaths[command.paintId!] = originalPath;
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
      result.commands.add(DrawCommand(DrawCommandType.vertices,
          objectId: result.vertices.length, paintId: entry.key));
      result.vertices.add(Vertices.fromFloat32List(vertices).createIndex());
      builder.dispose();
    }
    return result;
  }
}
