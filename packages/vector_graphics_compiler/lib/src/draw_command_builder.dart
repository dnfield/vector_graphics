import 'geometry/path.dart';
import 'paint.dart';
import 'vector_instructions.dart';

/// An interface for building up a stack of vector commands.
abstract class DrawCommandBuilder {
  /// Add a save layer to the command stack.
  void addSaveLayer(Paint paint);

  /// Add a restore to the command stack.
  void restore();

  /// Adds a clip to the command stack.
  void addClip(Path path);

  /// Adds a mask to the command stack.
  void addMask();

  /// Add a path to the current draw command stack
  void addPath(Path path, Paint paint, String? debugString);

  /// Create a new [VectorInstructions] with the given width and height.
  VectorInstructions toInstructions(double width, double height);
}

/// An implementation of the [DrawCommandBuilder] that does not attempt to dedup
/// paints and paths.
class FastDrawCommandBuilder implements DrawCommandBuilder {
  final List<Paint> _paints = <Paint>[];
  final List<Path> _paths = <Path>[];
  final List<DrawCommand> _commands = <DrawCommand>[];

  int _getOrGenerateId<T>(T object, List<T> items) {
    final int id = items.length;
    items.add(object);
    return id;
  }

  @override
  void addSaveLayer(Paint paint) {
    assert(paint.fill!.color != null);

    final int paintId = _getOrGenerateId(paint, _paints);
    _commands.add(DrawCommand(
      DrawCommandType.saveLayer,
      paintId: paintId,
    ));
  }

  @override
  void restore() {
    _commands.add(const DrawCommand(DrawCommandType.restore));
  }

  @override
  void addClip(Path path) {
    final int pathId = _getOrGenerateId(path, _paths);
    _commands.add(DrawCommand(DrawCommandType.clip, objectId: pathId));
  }

  @override
  void addMask() {
    _commands.add(const DrawCommand(DrawCommandType.mask));
  }

  @override
  void addPath(Path path, Paint paint, String? debugString) {
    final int pathId = _getOrGenerateId(path, _paths);
    final int paintId = _getOrGenerateId(paint, _paints);
    _commands.add(DrawCommand(
      DrawCommandType.path,
      objectId: pathId,
      paintId: paintId,
      debugString: debugString,
    ));
  }

  @override
  VectorInstructions toInstructions(double width, double height) {
    return VectorInstructions(
      width: width,
      height: height,
      paints: _paints,
      paths: _paths,
      commands: _commands,
    );
  }
}

/// An implementation of the [DrawCommandBuilder] that attempts to de-duplicate paths
/// and paints.
class DedupDrawCommandBuilder implements DrawCommandBuilder {
  final Map<Paint, int> _paints = <Paint, int>{};
  final Map<Path, int> _paths = <Path, int>{};
  final List<DrawCommand> _commands = <DrawCommand>[];

  int _getOrGenerateId<T>(T object, Map<T, int> map) =>
      map.putIfAbsent(object, () => map.length);

  @override
  void addSaveLayer(Paint paint) {
    assert(paint.fill!.color != null);

    final int paintId = _getOrGenerateId(paint, _paints);
    _commands.add(DrawCommand(
      DrawCommandType.saveLayer,
      paintId: paintId,
    ));
  }

  @override
  void restore() {
    _commands.add(const DrawCommand(DrawCommandType.restore));
  }

  @override
  void addClip(Path path) {
    final int pathId = _getOrGenerateId(path, _paths);
    _commands.add(DrawCommand(DrawCommandType.clip, objectId: pathId));
  }

  @override
  void addMask() {
    _commands.add(const DrawCommand(DrawCommandType.mask));
  }

  @override
  void addPath(Path path, Paint paint, String? debugString) {
    final int pathId = _getOrGenerateId(path, _paths);
    final int paintId = _getOrGenerateId(paint, _paints);
    _commands.add(DrawCommand(
      DrawCommandType.path,
      objectId: pathId,
      paintId: paintId,
      debugString: debugString,
    ));
  }

  @override
  VectorInstructions toInstructions(double width, double height) {
    return VectorInstructions(
      width: width,
      height: height,
      paints: _paints.keys.toList(),
      paths: _paths.keys.toList(),
      commands: _commands,
    );
  }
}
