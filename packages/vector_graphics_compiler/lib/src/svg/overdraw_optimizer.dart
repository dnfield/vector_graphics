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

/// Simplifies masking operations into PathNodes.
/// Note this will not optimize cases where 'stroke-width' is set,
/// there are multiple path nodes in a mask or cases where
/// the intersection of the mask and the path results in
/// Path.commands being empty.
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

  @override
  _Result visitEmptyNode(Node node, void data) {
    final _Result _result = _Result(node);
    return _result;
  }

  /// Visits applies optimizer to all children of ResolvedMaskNode.
  _Result visitChildren(Node node, _Result data) {
    if (node is ResolvedMaskNode) {
      data = node.child.accept(this, data);
    }
    return data;
  }

  /// DETLETE LATER:
  /// YOU MUST MAINTAIN THE ORDER OF THE NODES
  @override
  _Result visitParentNode(ParentNode parentNode, Node data) {
    final List<int> pathNodeIndices = <int>[];
    final List<ResolvedPathNode> pathNodesList = <ResolvedPathNode>[];
    List<Node> newChildren = <Node>[];

    int index = 0;
    for (Node child in parentNode.children) {
      if (child is ResolvedPathNode) {
        pathNodeIndices.add(index++);
        pathNodesList.add(child);
      }
    }

    print("PATHNODE LIST LENGTH IS " + pathNodesList.length.toString());
    print("OPACITY IS " + parentNode.attributes.opacity.toString());

    if (pathNodesList.length >= 2 &&
        (parentNode.attributes.opacity == 1 ||
            parentNode.attributes.opacity == null)) {
      for (int i = 0; i < pathNodesList.length - 1; i++) {
        pathNodesList[i] =
            removeOverlap(pathNodesList[i], pathNodesList[i + 1]);
        print("NEW PATHNODES LIST IS");
        print(pathNodesList);
      }
      index = 0;
      for (Node child in parentNode.children) {
        if (child is ResolvedPathNode) {
          newChildren.add(pathNodesList[pathNodeIndices[index++]]);
        } else {
          newChildren.add(child.accept(this, parentNode).node);
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
