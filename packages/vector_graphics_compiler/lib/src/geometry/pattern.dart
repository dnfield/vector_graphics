import '../../src/svg/resolver.dart';
import 'matrix.dart';

/// Pattern information for encoding.
class PatternData {
  /// Constructs new [PatternData].
  PatternData(this.x, this.y, this.width, this.height, this.transform);

  /// The x coordinate shift of the pattern tile.
  double x;

  /// The y coordinate shift of the pattern tile.
  double y;

  /// The width of the pattern.
  double width;

  /// The height of the pattern.
  double height;

  /// The transform of the pattern.
  AffineMatrix transform;

  /// Creates a [PatternData] object from a [ResolvedPatternNode].
  static PatternData fromNode(ResolvedPatternNode patternNode) {
    return PatternData(patternNode.x!, patternNode.y!, patternNode.width,
        patternNode.height, patternNode.transform);
  }
}
