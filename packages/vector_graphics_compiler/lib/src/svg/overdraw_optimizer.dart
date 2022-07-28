// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'node.dart';
import 'resolver.dart';
import 'visitor.dart';
import '../../vector_graphics_compiler.dart';
import 'masking_optimizer.dart';
import 'path_ops.dart' as path_ops;

class _Result {
  _Result(this.node);

  final Node node;
  final List<Node> children = <Node>[];
  Node parent = Node.empty;
  bool deleteMaskNode = true;
}

/// Holds value of index and a matching node list.
class Tuple<T1, T2> {
  /// Constructor for Tuple class.
  Tuple(this.index, this.nodeList);

  /// Original index of node(s)
  final T1 index;

  /// List of nodes.
  final T2 nodeList;
}

/// Removes unnecessary overlappping.
class OverdrawOptimizer extends Visitor<_Result, Node>
    with ErrorOnUnResolvedNode<_Result, Node> {
  /// Applies visitor to given node.
  Node apply(Node node) {
    final Node newNode = node.accept(this, null).node;
    return newNode;
  }

  /// Removes overlap between top and bottom path from bottom.
  ResolvedPathNode removeOverlap(
      ResolvedPathNode bottomPathNode, ResolvedPathNode topPathNode) {
    final path_ops.Path topPathOpsPath = toPathOpsPath(topPathNode.path);
    final path_ops.Path bottomPathOpsPath = toPathOpsPath(bottomPathNode.path);
    final path_ops.Path intersection =
        bottomPathOpsPath.applyOp(topPathOpsPath, path_ops.PathOp.intersect);
    final path_ops.Path newBottomPath =
        bottomPathOpsPath.applyOp(intersection, path_ops.PathOp.difference);
    final Path newPath = toVectorGraphicsPath(newBottomPath);
    final ResolvedPathNode newPathNode = ResolvedPathNode(
        paint: bottomPathNode.paint,
        bounds: bottomPathNode.bounds,
        path: newPath);

    bottomPathOpsPath.dispose();
    topPathOpsPath.dispose();
    intersection.dispose();
    newBottomPath.dispose();

    return newPathNode;
  }

  /// Resolves overlapping between top and bottom path on
  /// nodes where opacity is not 1 or null.
  List<ResolvedPathNode> resolveOpacityOverlap(
      ResolvedPathNode bottomPathNode, ResolvedPathNode topPathNode) {
    final Color? bottomColor = bottomPathNode.paint.fill?.color;
    final Color? topColor = topPathNode.paint.fill?.color;
    if (bottomColor != null && topColor != null) {
      final double a0 = topColor.a / 255;
      final double a1 = bottomColor.a / 255;
      final int r0 = topColor.r;
      final int b0 = topColor.b;
      final int g0 = topColor.g;
      final int r1 = bottomColor.r;
      final int b1 = bottomColor.b;
      final int g1 = bottomColor.g;

      final double a = (1 - a0) * a1 + a0;
      final double r = ((1 - a0) * a1 * r1 + a0 * r0) / a;
      final double g = ((1 - a0) * a1 * g1 + a0 * g0) / a;
      final double b = ((1 - a0) * a1 * b1 + a0 * b0) / a;

      final Color overlapColor =
          Color.fromARGB((a * 255).round(), r.round(), g.round(), b.round());

      final path_ops.Path topPathOpsPath = toPathOpsPath(topPathNode.path);
      final path_ops.Path bottomPathOpsPath =
          toPathOpsPath(bottomPathNode.path);
      final path_ops.Path intersection =
          bottomPathOpsPath.applyOp(topPathOpsPath, path_ops.PathOp.intersect);
      final path_ops.Path newBottomPath =
          bottomPathOpsPath.applyOp(intersection, path_ops.PathOp.difference);
      final path_ops.Path newTopPath =
          topPathOpsPath.applyOp(intersection, path_ops.PathOp.difference);

      final Path newBottomVGPath = toVectorGraphicsPath(newBottomPath);
      final Path newTopVGPath = toVectorGraphicsPath(newTopPath);
      final Path newOverlapVGPath = toVectorGraphicsPath(intersection);

      final ResolvedPathNode newBottomPathNode = ResolvedPathNode(
          paint: bottomPathNode.paint,
          bounds: bottomPathNode.bounds,
          path: newBottomVGPath);
      final ResolvedPathNode newTopPathNode = ResolvedPathNode(
          paint: topPathNode.paint,
          bounds: bottomPathNode.bounds,
          path: newTopVGPath);
      final ResolvedPathNode newOverlapPathNode = ResolvedPathNode(
          paint: Paint(
              blendMode: bottomPathNode.paint.blendMode,
              stroke: bottomPathNode.paint.stroke,
              fill: Fill(
                  color: overlapColor,
                  shader: bottomPathNode.paint.fill?.shader)),
          bounds: bottomPathNode.bounds,
          path: newOverlapVGPath);

      bottomPathOpsPath.dispose();
      topPathOpsPath.dispose();
      intersection.dispose();
      newBottomPath.dispose();

      return <ResolvedPathNode>[
        newBottomPathNode,
        newTopPathNode,
        newOverlapPathNode
      ];
    } else {
      return <ResolvedPathNode>[bottomPathNode];
    }
  }

  @override
  _Result visitEmptyNode(Node node, void data) {
    final _Result _result = _Result(node);
    return _result;
  }

  /// Visits applies optimizer to all children of ParentNode.
  _Result visitChildren(Node node, _Result data) {
    if (node is ParentNode) {
      data = node.accept(this, data);
    }
    return data;
  }

  @override
  _Result visitParentNode(ParentNode parentNode, Node data) {
    int pathNodeCount = 0;
    final List<List<Node>> newChildList = <List<Node>>[];
    List<Node> newChildren = <Node>[];

    for (Node child in parentNode.children) {
      if (child is ResolvedPathNode) {
        pathNodeCount++;
      }
      newChildList.add(<Node>[child]);
    }

    int index = 0;
    ResolvedPathNode? lastPathNode;
    int? lastPathNodeIndex;

    if (pathNodeCount >= 2) {
      for (Node child in parentNode.children) {
        if (child is ResolvedPathNode && child.paint.stroke?.width == null) {
          if (lastPathNode == null || lastPathNodeIndex == null) {
            lastPathNode = child;
            lastPathNodeIndex = index;
          } else {
            if (child.paint.fill?.color.a == 255) {
              newChildList[lastPathNodeIndex] = <Node>[
                removeOverlap(lastPathNode, child)
              ];
            } else {
              newChildList[lastPathNodeIndex] = resolveOpacityOverlap(
                  (newChildList[lastPathNodeIndex].first as ResolvedPathNode),
                  child);
              newChildList[index] = <Node>[];
              lastPathNode = null;
              lastPathNodeIndex = null;
            }
          }
        }
        index++;
      }
      index = 0;
      for (List<Node> child in newChildList) {
        if (child.isNotEmpty) {
          if (child.first is ResolvedPathNode) {
            newChildren.addAll(child);
          } else {
            newChildren.add(child.first.accept(this, parentNode).node);
          }
        }
      }
    } else {
      newChildren = parentNode.children.toList();
    }
    final _Result _result = _Result(ParentNode(parentNode.attributes,
        children: newChildren, precalculatedTransform: parentNode.transform));

    return _result;
  }

  @override
  _Result visitMaskNode(MaskNode maskNode, Node data) {
    final _Result _result = _Result(maskNode);

    return _result;
  }

  @override
  _Result visitPathNode(PathNode pathNode, Node data) {
    final _Result _result = _Result(pathNode);
    return _result;
  }

  @override
  _Result visitResolvedMaskNode(ResolvedMaskNode maskNode, void data) {
    final _Result childResult = maskNode.child.accept(this, maskNode);
    final ResolvedMaskNode newMaskNode = ResolvedMaskNode(
        child: childResult.node,
        mask: maskNode.mask,
        blendMode: maskNode.blendMode);
    final _Result _result = _Result(newMaskNode);
    _result.children.add(childResult.node);
    return _result;
  }

  @override
  _Result visitResolvedClipNode(ResolvedClipNode clipNode, Node data) {
    final _Result childResult = clipNode.child.accept(this, clipNode);
    final ResolvedClipNode newClipNode =
        ResolvedClipNode(clips: clipNode.clips, child: childResult.node);
    final _Result _result = _Result(newClipNode);
    _result.children.add(childResult.node);

    return _result;
  }

  @override
  _Result visitResolvedPath(ResolvedPathNode pathNode, Node data) {
    final _Result _result = _Result(pathNode);
    return _result;
  }

  @override
  _Result visitResolvedText(ResolvedTextNode textNode, Node data) {
    final _Result _result = _Result(textNode);
    return _result;
  }

  @override
  _Result visitResolvedVerticesNode(
      ResolvedVerticesNode verticesNode, Node data) {
    final _Result _result = _Result(verticesNode);
    return _result;
  }

  @override
  _Result visitSaveLayerNode(SaveLayerNode layerNode, Node data) {
    final List<Node> newChildren = <Node>[];
    for (Node child in layerNode.children) {
      final _Result childResult = child.accept(this, layerNode);
      newChildren.add(childResult.node);
    }
    final SaveLayerNode newLayerNode = SaveLayerNode(layerNode.attributes,
        paint: layerNode.paint, children: newChildren);

    final _Result _result = _Result(newLayerNode);
    _result.children.addAll(newChildren);
    return _result;
  }

  @override
  _Result visitResolvedImageNode(
      ResolvedImageNode resolvedImageNode, Node data) {
    final _Result _result = _Result(resolvedImageNode);
    return _result;
  }

  @override
  _Result visitViewportNode(ViewportNode viewportNode, void data) {
    final List<Node> children = <Node>[];
    for (Node child in viewportNode.children) {
      final _Result childNode = child.accept(this, viewportNode);
      children.add(childNode.node);
    }

    final ViewportNode node = ViewportNode(
      viewportNode.attributes,
      width: viewportNode.width,
      height: viewportNode.height,
      transform: viewportNode.transform,
      children: children,
    );

    final _Result _result = _Result(node);
    _result.children.addAll(children);
    return _result;
  }
}
