import '../draw_command_builder.dart';
import '../geometry/basic_types.dart';
import '../geometry/matrix.dart';
import '../geometry/path.dart';
import '../paint.dart';
import 'parser.dart' show SvgAttributes;

/// A node in a tree of graphics operations.
///
/// Nodes describe painting attributes, clips, transformations, paths, and
/// vertices to draw in depth-first order.
abstract class Node {
  /// Allows subclasses to be const.
  const Node();

  /// Subclasses that have additional transformation information will
  /// concatenate their transform to the supplied `currentTransform`.
  AffineMatrix concatTransform(AffineMatrix currentTransform) {
    return currentTransform;
  }

  /// Calls `build` for all nodes contained in this subtree with the
  /// specified `transform` in painting order.
  ///
  /// The transform will be multiplied with any transforms present on
  /// [ParentNode]s in the subtree, and applied to any [Path] objects in leaf
  /// nodes in the tree. It may be [AffineMatrix.identity] to indicate that no
  /// additional transformation is needed.
  void build(DrawCommandBuilder builder, AffineMatrix transform);
}

/// A node that has attributes in the tree of graphics operations.
abstract class AttributedNode extends Node {
  /// Constructs a new tree node with [id] and [paint].
  const AttributedNode(this.attributes);

  /// A collection of painting attributes.
  ///
  /// Painting attributes inherit down the tree.
  final SvgAttributes attributes;

  /// Creates a new compatible node with this as if the `newPaint` had
  /// the current paint applied as a parent.
  AttributedNode applyAttributes(SvgAttributes newAttributes);
}

/// A graphics node describing a viewport area, which has a [width] and [height]
/// for the viewable portion it describes.
///
/// A viewport node is effectively a [ParentNode] with a width and height to
/// describe child coordinate space. It is typically used as the root of a tree,
/// but may also appear as a subtree root.
class ViewportNode extends ParentNode {
  /// Creates a new viewport node.
  ///
  /// See [ViewportNode].
  ViewportNode(
    SvgAttributes attributes, {
    required this.width,
    required this.height,
    required AffineMatrix transform,
  }) : super(attributes, precalculatedTransform: transform);

  /// The width of the viewport in pixels.
  final double width;

  /// The height of the viewport in pixels.
  final double height;

  /// The viewport rect described by [width] and [height].
  Rect get viewport => Rect.fromLTWH(0, 0, width, height);
}

/// The signature for a visitor callback to [ParentNode.visitChildren].
typedef NodeCallback = void Function(Node child);

/// A node that contains children, transformed by [transform].
class ParentNode extends AttributedNode {
  /// Creates a new [ParentNode].
  ParentNode(
    SvgAttributes attributes, {
    AffineMatrix? precalculatedTransform,
  })  : transform = precalculatedTransform ?? attributes.transform,
        super(attributes);

  /// The transform to apply to this subtree, if any.
  final AffineMatrix transform;

  /// The child nodes of this node.
  final List<Node> _children = <Node>[];

  /// The color, if any, to pass on to children for inheritence purposes.
  ///
  /// This color will be applied to any [Stroke] or [Fill] properties on child
  /// paints.
  // final Color? color;

  /// Calls `visitor` for each child node of this parent group.
  ///
  /// This call does not recursively call `visitChildren`. Callers must decide
  /// whether to do BFS or DFS by calling `visitChildren` if the visited child
  /// is a [ParentNode].
  void visitChildren(NodeCallback visitor) {
    _children.forEach(visitor);
  }

  /// Adds a child to this parent node.
  ///
  /// If `clips` is empty, the child is directly appended. Otherwise, a
  /// [ClipNode] is inserted.
  void addChild(
    Node child, {
    List<Path> clips = const <Path>[],
    Node? mask,
  }) {
    if (clips.isNotEmpty) {
      child = ClipNode(clips: clips, child: child);
    }
    if (mask != null) {
      child = MaskNode(mask: mask, child: child);
    }
    _children.add(child);
  }

  @override
  AffineMatrix concatTransform(AffineMatrix currentTransform) {
    if (transform == AffineMatrix.identity) {
      return currentTransform;
    }
    return currentTransform.multiplied(transform);
  }

  @override
  AttributedNode applyAttributes(SvgAttributes newAttributes) {
    return ParentNode(
      newAttributes.applyParent(attributes),
      precalculatedTransform: transform,
    ).._children.addAll(_children);
  }

  Paint? _createLayerPaint() {
    if (attributes.blendMode != null) {
      return Paint(
        blendMode: attributes.blendMode,
        fill: attributes.fill!.toFill(Rect.largest, transform) ??
            const Fill(color: Color.opaqueBlack),
      );
    }
    return null;
  }

  @override
  void build(DrawCommandBuilder builder, AffineMatrix transform) {
    final Paint? layerPaint = _createLayerPaint();
    if (layerPaint != null) {
      builder.addSaveLayer(layerPaint);
    }

    for (final Node child in _children) {
      child.build(builder, concatTransform(transform));
    }

    if (layerPaint != null) {
      builder.restore();
    }
  }
}

/// A parent node that applies a clip to its children.
class ClipNode extends Node {
  /// Creates a new clip node that applies [clips] to [child].
  ClipNode({required this.child, required this.clips, String? id})
      : assert(
          clips.isNotEmpty,
          'Do not use a ClipNode without any clip paths.',
        );

  /// The clips to apply to the child node.
  ///
  /// Normally, there will only be one clip to apply. However, if multiple paths
  /// with differeing [PathFillType]s are used, multiple clips must be
  /// specified.
  final List<Path> clips;

  /// The child to clip.
  final Node child;

  @override
  void build(DrawCommandBuilder builder, AffineMatrix transform) {
    for (final Path clip in clips) {
      final Path transformedClip = clip.transformed(transform);
      builder.addClip(transformedClip);
      child.build(builder, transform);
      builder.restore();
    }
  }
}

/// A parent node that applies a mask to its child.
class MaskNode extends Node {
  /// Creates a new mask node that applies [mask] to [child].
  MaskNode({required this.child, required this.mask});

  /// The mask to apply.
  final Node mask;

  /// The child to mask.
  final Node child;

  @override
  void build(DrawCommandBuilder builder, AffineMatrix transform) {
    // Save layer expects to use the fill paint, and will unconditionally set
    // the color on the dart:ui.Paint object.
    builder.addSaveLayer(const Paint(fill: Fill(color: Color.opaqueBlack)));
    child.build(builder, transform);
    {
      builder.addMask();
      mask.build(builder, child.concatTransform(transform));
      builder.restore();
    }
    builder.restore();
  }
}

/// A leaf node in the graphics tree.
///
/// Leaf nodes get added with all paint and transform accumulations from their
/// parents applied.
class PathNode extends AttributedNode {
  /// Creates a new leaf node for the graphics tree with the specified [path]
  /// and attributes
  PathNode(this.path, SvgAttributes attributes) : super(attributes);

  /// The description of the geometry this leaf node draws.
  final Path path;

  Paint? _paint(Rect bounds, AffineMatrix transform) {
    final Fill? fill = attributes.fill?.toFill(bounds, transform);
    final Stroke? stroke = attributes.stroke?.toStroke(bounds, transform);
    if (fill == null && stroke == null) {
      return null;
    }
    return Paint(
      blendMode: attributes.blendMode,
      fill: fill,
      stroke: stroke,
    );
  }

  @override
  AttributedNode applyAttributes(SvgAttributes newAttributes) {
    return PathNode(
      path,
      attributes.applyParent(newAttributes),
    );
  }

  @override
  void build(DrawCommandBuilder builder, AffineMatrix transform) {
    final Path transformedPath = path.transformed(transform);
    final Rect bounds = transformedPath.bounds();
    final Paint? paint = _paint(bounds, transform);
    if (paint != null) {
      builder.addPath(transformedPath, paint, attributes.id);
    }
  }
}
