import '../draw_command_builder.dart';
import '../geometry/basic_types.dart';
import '../geometry/matrix.dart';
import '../geometry/path.dart';
import '../paint.dart';
import '../vector_instructions.dart';
import 'node.dart';
import 'parser.dart';

/// A visitor implementation used to process the tree.
abstract class Visitor<S> {
  /// Const constructor so subclasses can be const.
  const Visitor();

  /// Visit a [ViewportNode].
  S visitViewportNode(ViewportNode viewportNode);

  /// Visit a [MaskNode].
  S visitMaskNode(MaskNode maskNode);

  /// Visit a [ClipNode].
  S visitClipNode(ClipNode clipNode);

  /// Visit a [TextNode].
  S visitTextNode(TextNode textNode);

  /// Visit a [PathNode].
  S visitPathNode(PathNode pathNode);

  /// Visit a [ParentNode].
  S visitParentNode(ParentNode parentNode);

  /// Visit a [DeferredNode].
  S visitDeferredNode(DeferredNode deferredNode);

  /// Visit a [Node] that has no meaningful content.
  S visitEmptyNode(Node node);

  /// Visit a [ResolvedTextNode].
  S visitResolvedText(ResolvedTextNode textNode);

  /// Visit a [ResolvedPathNode].
  S visitResolvedPath(ResolvedPathNode pathNode);

  /// Visit a [ResolvedClipNode].
  S visitResolvedClipNode(ResolvedClipNode clipNode);

  /// Visit a [ResolvedMaskNode].
  S visitResolvedMaskNode(ResolvedMaskNode maskNode);

  /// Visit a [SaveLayerNode].
  S visitSaveLayerNode(SaveLayerNode layerNode);
}

/// A visitor class that processes relative coordinates in the tree into a
/// single coordinate space, removing extra attributes, empty nodes, resolving
/// references/masks/clips.
class ResolvingVisitor extends Visitor<Node> {
  late Rect _bounds;
  final List<AffineMatrix> _transformStack = <AffineMatrix>[
    AffineMatrix.identity,
  ];

  @override
  Node visitClipNode(ClipNode clipNode) {
    final List<Path> transformedClips = <Path>[
      for (Path clip in clipNode.resolver(clipNode.clipId))
        clip.transformed(_transformStack.last)
    ];
    if (transformedClips.isEmpty) {
      return clipNode.child.accept(this);
    }
    return ResolvedClipNode(
      clips: transformedClips,
      child: clipNode.child.accept(this),
    );
  }

  @override
  Node visitMaskNode(MaskNode maskNode) {
    final AttributedNode? resolvedMask = maskNode.resolver(maskNode.maskId);
    if (resolvedMask == null) {
      return maskNode.child.accept(this);
    }
    final Node child = maskNode.child.accept(this);
    final AffineMatrix childTransform =
        maskNode.concatTransform(_transformStack.last);

    _transformStack.add(childTransform);
    final Node mask = resolvedMask.accept(this);
    _transformStack.removeLast();

    return ResolvedMaskNode(
      child: child,
      mask: mask,
      blendMode: maskNode.blendMode,
    );
  }

  @override
  Node visitParentNode(ParentNode parentNode) {
    final AffineMatrix current = _transformStack.last;
    final AffineMatrix nextTransform = parentNode.concatTransform(current);
    _transformStack.add(nextTransform);

    final Paint? saveLayerPaint = parentNode.createLayerPaint();
    final Node result;
    if (saveLayerPaint == null) {
      result = ParentNode(
        SvgAttributes.empty,
        precalculatedTransform: AffineMatrix.identity,
        children: <Node>[
          for (Node child in parentNode.children) child.accept(this),
        ],
      );
    } else {
      result = SaveLayerNode(
        SvgAttributes.empty,
        paint: saveLayerPaint,
        children: <Node>[
          for (Node child in parentNode.children) child.accept(this),
        ],
      );
    }
    _transformStack.removeLast();
    return result;
  }

  @override
  Node visitPathNode(PathNode pathNode) {
    final AffineMatrix transform =
        _transformStack.last.multiplied(pathNode.attributes.transform);
    final Path transformedPath = pathNode.path.transformed(transform);
    final Rect originalBounds = pathNode.path.bounds();
    final Rect newBounds = transformedPath.bounds();
    final Paint? paint = pathNode.computePaint(originalBounds, transform);
    if (paint != null) {
      return ResolvedPathNode(
        paint: paint,
        bounds: newBounds,
        path: transformedPath,
      );
    }
    return Node.zero;
  }

  @override
  Node visitTextNode(TextNode textNode) {
    final Paint? paint = textNode.computePaint(_bounds, _transformStack.last);
    final TextConfig textConfig =
        textNode.computeTextConfig(_bounds, _transformStack.last);
    if (paint != null && textConfig.text.trim().isNotEmpty) {
      return ResolvedTextNode(
        textConfig: textConfig,
        paint: paint,
      );
    }
    return Node.zero;
  }

  @override
  Node visitViewportNode(ViewportNode viewportNode) {
    _bounds = Rect.fromLTWH(0, 0, viewportNode.width, viewportNode.height);
    _transformStack.add(viewportNode.transform);
    return ViewportNode(
      SvgAttributes.empty,
      width: viewportNode.width,
      height: viewportNode.height,
      transform: AffineMatrix.identity,
      children: <Node>[
        for (Node child in viewportNode.children) child.accept(this),
      ],
    );
  }

  @override
  Node visitDeferredNode(DeferredNode deferredNode) {
    final AttributedNode? resolvedNode =
        deferredNode.resolver(deferredNode.refId);
    if (resolvedNode == null) {
      return Node.zero;
    }
    final AttributedNode concreteRef =
        resolvedNode.applyAttributes(deferredNode.attributes);
    return concreteRef.accept(this);
  }

  @override
  Node visitEmptyNode(Node node) => node;

  @override
  Node visitResolvedText(ResolvedTextNode textNode) {
    assert(false);
    return textNode;
  }

  @override
  Node visitResolvedPath(ResolvedPathNode pathNode) {
    assert(false);
    return pathNode;
  }

  @override
  Node visitResolvedClipNode(ResolvedClipNode clipNode) {
    assert(false);
    return clipNode;
  }

  @override
  Node visitResolvedMaskNode(ResolvedMaskNode maskNode) {
    assert(false);
    return maskNode;
  }

  @override
  Node visitSaveLayerNode(SaveLayerNode layerNode) {
    assert(false);
    return layerNode;
  }
}

/// A visitor that builds up a [VectorInstructions] for binary encoding.
class CommandBuilderVisitor extends Visitor<void> {
  final DrawCommandBuilder _builder = DrawCommandBuilder();
  late double _width;
  late double _height;

  /// Return the vector instructions encoded by the visitor given to this tree.
  VectorInstructions toInstructions() {
    return _builder.toInstructions(_width, _height);
  }

  @override
  void visitClipNode(ClipNode clipNode) {
    assert(false);
  }

  @override
  void visitDeferredNode(DeferredNode deferredNode) {
    assert(false);
  }

  @override
  void visitEmptyNode(Node node) {}

  @override
  void visitMaskNode(MaskNode maskNode) {
    assert(false);
  }

  @override
  void visitParentNode(ParentNode parentNode) {
    for (Node child in parentNode.children) {
      child.accept(this);
    }
  }

  @override
  void visitPathNode(PathNode pathNode) {
    assert(false);
  }

  @override
  void visitResolvedClipNode(ResolvedClipNode clipNode) {
    for (final Path clip in clipNode.clips) {
      _builder.addClip(clip);
      clipNode.child.accept(this);
      _builder.restore();
    }
  }

  @override
  void visitResolvedMaskNode(ResolvedMaskNode maskNode) {
    _builder.addSaveLayer(Paint(
      blendMode: maskNode.blendMode,
      fill: const Fill(),
    ));
    maskNode.child.accept(this);
    _builder.addMask();
    maskNode.mask.accept(this);
    _builder.restore();
    _builder.restore();
  }

  @override
  void visitResolvedPath(ResolvedPathNode pathNode) {
    _builder.addPath(pathNode.path, pathNode.paint, null);
  }

  @override
  void visitResolvedText(ResolvedTextNode textNode) {
    _builder.addText(textNode.textConfig, textNode.paint, null);
  }

  @override
  void visitTextNode(TextNode textNode) {
    assert(false);
  }

  @override
  void visitViewportNode(ViewportNode viewportNode) {
    _width = viewportNode.width;
    _height = viewportNode.height;
    for (Node child in viewportNode.children) {
      child.accept(this);
    }
  }

  @override
  void visitSaveLayerNode(SaveLayerNode layerNode) {
    _builder.addSaveLayer(layerNode.paint);
    for (Node child in layerNode.children) {
      child.accept(this);
    }
    _builder.restore();
  }
}
