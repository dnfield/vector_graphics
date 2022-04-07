import 'package:vector_graphics_compiler/src/svg/parser.dart';
import 'package:vector_graphics_compiler/src/svg/resolver.dart';
import 'package:vector_graphics_compiler/src/svg/visitor.dart';

import '../geometry/basic_types.dart';
import 'node.dart';

class _Result {
  _Result(this.canForwardOpacity, this.node, this.bounds);

  final bool canForwardOpacity;
  final Node node;
  final List<Rect> bounds;
}

/// This visitor will process the tree and apply opacity forward.
class OpacityPeepholeOptimizer extends Visitor<_Result, double?>
    with ErrorOnUnResolvedNode<_Result, double?> {
  static int removedLayer = 0;

  /// Apply the optimization to the given node tree.
  Node apply(Node node) {
    final _Result _result = node.accept(this, null);
    return _result.node;
  }

  @override
  _Result visitEmptyNode(Node node, double? data) {
    return _Result(true, node, <Rect>[Rect.zero]);
  }

  @override
  _Result visitParentNode(ParentNode parentNode, double? data) {
    final List<_Result> childResults = <_Result>[
      for (Node child in parentNode.children) child.accept(this, data)
    ];
    bool canForwardOpacity = true;
    for (_Result result in childResults) {
      if (!result.canForwardOpacity) {
        canForwardOpacity = false;
      }
    }
    final List<Node> children =
        childResults.map((_Result result) => result.node).toList();
    final List<Rect> bounds = childResults
        .map((_Result result) => result.bounds)
        .expand((List<Rect> bounds) => bounds)
        .toList();

    return _Result(
      canForwardOpacity,
      ParentNode(
        SvgAttributes.empty,
        children: children,
      ),
      bounds,
    );
  }

  @override
  _Result visitResolvedClipNode(ResolvedClipNode clipNode, double? data) {
    // If there are multiple clip paths, then we don't currently know how to calculate
    // the exact bounds.
    final Node child = clipNode.child.accept(this, data).node;
    if (clipNode.clips.length > 1) {
      return _Result(false, child, <Rect>[]);
    }
    return _Result(true, child, <Rect>[clipNode.clips.single.bounds()]);
  }

  @override
  _Result visitResolvedMaskNode(ResolvedMaskNode maskNode, double? data) {
    // We don't currently know how to compute bounds for a mask.
    // Don't process children to avoid breaking mask.
    return _Result(false, maskNode, <Rect>[]);
  }

  @override
  _Result visitResolvedPath(ResolvedPathNode pathNode, double? data) {
    return _Result(true, pathNode, <Rect>[pathNode.bounds]);
  }

  @override
  _Result visitResolvedText(ResolvedTextNode textNode, double? data) {
    // Text cannot apply the opacity optimization since we cannot accurately
    // learn its bounds ahead of time.
    return _Result(false, textNode, <Rect>[]);
  }

  @override
  _Result visitSaveLayerNode(SaveLayerNode layerNode, double? data) {
    final List<_Result> childResults = <_Result>[
      for (Node child in layerNode.children) child.accept(this, data)
    ];
    bool canForwardOpacity = true;
    for (_Result result in childResults) {
      if (!result.canForwardOpacity) {
        canForwardOpacity = false;
      }
    }

    final List<Rect> flattenedBounds = childResults
        .map((_Result result) => result.bounds)
        .expand((List<Rect> rects) => rects)
        .toList();
    for (int i = 0; i < flattenedBounds.length; i++) {
      final Rect current = flattenedBounds[i];
      for (int j = 0; j < flattenedBounds.length; j++) {
        if (i == j) {
          continue;
        }
        final Rect candidate = flattenedBounds[j];
        if (candidate.intersects(current)) {
          canForwardOpacity = false;
        }
      }
    }

    if (!canForwardOpacity) {
      return _Result(
        false,
        SaveLayerNode(SvgAttributes.empty,
            paint: layerNode.paint,
            children: <Node>[for (_Result result in childResults) result.node]),
        <Rect>[],
      );
    }

    removedLayer += 1;
    final Node result = ParentNode(SvgAttributes.empty,
        children: <Node>[for (_Result result in childResults) result.node]);
    return _Result(canForwardOpacity, result, flattenedBounds);
  }

  @override
  _Result visitViewportNode(ViewportNode viewportNode, double? data) {
    final ViewportNode node = ViewportNode(
      viewportNode.attributes,
      width: viewportNode.width,
      height: viewportNode.height,
      transform: viewportNode.transform,
      children: <Node>[
        for (Node child in viewportNode.children) child.accept(this, null).node
      ],
    );
    return _Result(false, node, <Rect>[]);
  }
}
