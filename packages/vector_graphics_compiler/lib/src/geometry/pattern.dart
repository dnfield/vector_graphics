import '../../src/svg/resolver.dart';
import 'matrix.dart';

/// Pattern information for encoding.
class PatternData {
  /// Constructs new [PatternData].
  PatternData(this.x, this.y, this.width, this.height, this.transform);

  /// The x coordinate shift of the pattern tile in px.
  /// Values must be > = 1.
  double x;

  /// The y coordinate shift of the pattern tile in px.
  /// Values must be > = 1.
  double y;

  /// The width of the pattern's viewbox in px.
  double width;

  /// The height of the pattern's viewbox in px.
  double height;

  /// The transform of the pattern generated from its children.
  AffineMatrix transform;

  /// Creates a [PatternData] object from a [ResolvedPatternNode].
  static PatternData fromNode(ResolvedPatternNode patternNode) {
    return PatternData(patternNode.x!, patternNode.y!, patternNode.width,
        patternNode.height, patternNode.transform);
  }
}
