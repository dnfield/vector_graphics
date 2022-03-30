import '../draw_command_builder.dart';
import '../geometry/basic_types.dart';
import '../geometry/matrix.dart';
import '../geometry/path.dart';
import '../paint.dart';
import 'parser.dart' show SvgAttributes;

/// Signature of a method that resolves a string identifier to an object.
///
/// Used by [ClipNode] and [MaskNode] to defer resolution of clips and masks.
typedef Resolver<T> = T Function(String id);

/// A node in a tree of graphics operations.
///
/// Nodes describe painting attributes, clips, transformations, paths, and
/// vertices to draw in depth-first order.
abstract class Node {
  /// This node's parent, or `null` if it is the root element.
  Node? parent;

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

  /// Look up the bounds for the nearest sized parent.
  Rect nearestParentBounds() => parent?.nearestParentBounds() ?? Rect.zero;
}

/// A node that has attributes in the tree of graphics operations.
abstract class AttributedNode extends Node {
  /// Constructs a new tree node with [id] and [paint].
  AttributedNode(this.attributes);

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

  @override
  Rect nearestParentBounds() => viewport;
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
    AttributedNode child, {
    String? clipId,
    String? maskId,
    required Resolver<List<Path>> clipResolver,
    required Resolver<AttributedNode> maskResolver,
  }) {
    Node wrappedChild = child;
    if (clipId != null) {
      final Node childNode = wrappedChild;
      wrappedChild = ClipNode(
        resolver: clipResolver,
        clipId: clipId,
        child: wrappedChild,
      );
      childNode.parent = wrappedChild;
    }
    if (maskId != null) {
      final Node childNode = wrappedChild;
      wrappedChild = MaskNode(
        resolver: maskResolver,
        maskId: maskId,
        child: wrappedChild,
        blendMode: child.attributes.blendMode,
      );
      childNode.parent = wrappedChild;
    }
    wrappedChild.parent = this;
    _children.add(wrappedChild);
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
    final bool needsLayer = attributes.blendMode != null ||
        (attributes.opacity != null &&
            attributes.opacity != 1.0 &&
            attributes.opacity != 0.0);
    if (needsLayer) {
      return Paint(
        blendMode: attributes.blendMode,
        fill: attributes.fill!.toFill(Rect.largest, transform) ??
            Fill(
              color: Color.opaqueBlack.withOpacity(attributes.opacity ?? 1.0),
            ),
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
  /// Creates a new clip node that applies clip paths to [child].
  ClipNode({
    required this.resolver,
    required this.child,
    required this.clipId,
    String? id,
  });

  /// Called by [build] to resolve [clipId] to a list of paths.
  final Resolver<List<Path>> resolver;

  /// The clips to apply to the child node.
  ///
  /// Normally, there will only be one clip to apply. However, if multiple paths
  /// with differeing [PathFillType]s are used, multiple clips must be
  /// specified.
  final String clipId;

  /// The child to clip.
  final Node child;

  @override
  void build(DrawCommandBuilder builder, AffineMatrix transform) {
    for (final Path clip in resolver(clipId)) {
      final Path transformedClip = clip.transformed(transform);
      builder.addClip(transformedClip);
      child.build(builder, transform);
      builder.restore();
    }
  }
}

/// A parent node that applies a mask to its child.
class MaskNode extends Node {
  /// Creates a new mask node that applies [mask] to [child] using [blendMode].
  MaskNode({
    required this.child,
    required this.maskId,
    this.blendMode,
    required this.resolver,
  });

  /// The mask to apply.
  final String maskId;

  /// The child to mask.
  final Node child;

  /// The blend mode to apply when saving a layer for the mask, if any.
  final BlendMode? blendMode;

  /// Called by [build] to resolve [maskId] to an [AttributedNode].
  final Resolver<AttributedNode> resolver;

  @override
  void build(DrawCommandBuilder builder, AffineMatrix transform) {
    // Save layer expects to use the fill paint, and will unconditionally set
    // the color on the dart:ui.Paint object.
    builder.addSaveLayer(Paint(
      blendMode: blendMode,
      fill: const Fill(color: Color.opaqueBlack),
    ));
    child.build(builder, transform);
    {
      builder.addMask();
      resolver(maskId).build(builder, child.concatTransform(transform));
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
    transform = transform.multiplied(attributes.transform);
    final Path transformedPath = path.transformed(transform);
    final Rect bounds = path.bounds();
    final Paint? paint = _paint(bounds, transform);
    if (paint != null) {
      builder.addPath(transformedPath, paint, attributes.id);
    }
  }
}

/// A node that refers to another node, and uses [resolver] at [build] time
/// to materialize the referenced node into the tree.
class DeferredNode extends AttributedNode {
  /// Creates a new deferred node with [attributes] that will call [resolver]
  /// with [refId] at [build] time.
  DeferredNode(
    SvgAttributes attributes, {
    required this.refId,
    required this.resolver,
  }) : super(attributes);

  /// The reference id to pass to [resolver].
  final String refId;

  /// The callback that materializes an [AttributedNode] for [refId] at [build]
  /// time.
  final Resolver<AttributedNode> resolver;
  @override
  AttributedNode applyAttributes(SvgAttributes newAttributes) {
    return DeferredNode(
      attributes.applyParent(newAttributes),
      refId: refId,
      resolver: resolver,
    );
  }

  @override
  void build(DrawCommandBuilder builder, AffineMatrix transform) {
    final AttributedNode concreteRef =
        resolver(refId).applyAttributes(attributes);
    concreteRef.build(builder, transform);
  }
}

/// A leaf node in the tree that represents inline text.
///
/// Leaf nodes get added with all paint and transform accumulations from their
/// parents applied.
class TextNode extends AttributedNode {
  /// Create a new [TextNode] with the given [text].
  TextNode(
    this.text,
    this.baseline,
    this.absolute,
    SvgAttributes attributes,
  ) : super(attributes);

  /// The text this node contains.
  final String text;

  /// The x, y coordinate of the starting point of the text baseline.
  final Point baseline;

  /// Whether the [baseline] is in absolute or relative units.
  final bool absolute;

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

  static final Map<String, double> _kTextSizeMap = <String, double>{
    'xx-small': 10,
    'x-small': 12,
    'small': 14,
    'medium': 18,
    'large': 22,
    'x-large': 26,
    'xx-large': 32,
  };

  double _computeFontSize() {
    final String? fontSize = attributes.fontSize;
    if (fontSize == null) {
      return 1.0; // TODO what is default
    }
    if (_kTextSizeMap.containsKey(fontSize)) {
      return _kTextSizeMap[fontSize]!;
    }
    // TODO support units.
    return double.tryParse(fontSize) ?? 12;
  }

  int _computeFontWeight() {
    final String? fontWeightValue = attributes.fontWeight;
    if (fontWeightValue == null || fontWeightValue == 'normal') {
      return normalFontWeight.index;
    }
    if (fontWeightValue == 'bold') {
      return boldFontWeight.index;
    }
    switch (fontWeightValue) {
      case '100':
        return FontWeight.w100.index;
      case '200':
        return FontWeight.w200.index;
      case '300':
        return FontWeight.w300.index;
      case '400':
        return FontWeight.w400.index;
      case '500':
        return FontWeight.w500.index;
      case '600':
        return FontWeight.w600.index;
      case '700':
        return FontWeight.w700.index;
      case '800':
        return FontWeight.w800.index;
      case '900':
        return FontWeight.w900.index;
    }
    throw StateError('Invalid "font-weight": $fontWeightValue');
  }

  TextConfig _textConfig(Rect bounds, AffineMatrix transform) {
    final Point newBaseline = absolute
        ? baseline
        : Point(baseline.x * bounds.width, baseline.y * bounds.height);
    return TextConfig(
      text,
      transform.transformPoint(newBaseline),
      attributes.fontFamily ?? '',
      _computeFontWeight(),
      _computeFontSize(),
      attributes.transform,
    );
  }

  @override
  AttributedNode applyAttributes(SvgAttributes newAttributes) {
    return TextNode(
      text,
      baseline,
      absolute,
      attributes.applyParent(newAttributes),
    );
  }

  @override
  void build(DrawCommandBuilder builder, AffineMatrix transform) {
    final Rect bounds = nearestParentBounds();
    final Paint? paint = _paint(bounds, transform);
    final TextConfig textConfig = _textConfig(bounds, transform);
    if (paint != null && textConfig.text.trim().isNotEmpty) {
      builder.addText(textConfig, paint, attributes.id);
    }
  }
}
