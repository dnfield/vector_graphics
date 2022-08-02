import 'path.dart';

/// An element in a pattern, either a path or an image.
class PatternElement {
  /// Creates a pattern element.
  PatternElement(
    this.path,
    this.image,
  );

  /// A path in the pattern.
  final Path path;

  /// An image in the pattern.
  final Image image;
}
