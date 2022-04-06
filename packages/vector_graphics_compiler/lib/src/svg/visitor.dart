import '../draw_command_builder.dart';
import '../geometry/path.dart';
import '../paint.dart';
import '../vector_instructions.dart';
import 'node.dart';
import 'resolver.dart';

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
