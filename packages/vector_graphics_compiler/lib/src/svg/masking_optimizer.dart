import 'package:vector_graphics_compiler/src/svg/node.dart';
import 'package:vector_graphics_compiler/src/svg/parser.dart';
import 'package:vector_graphics_compiler/src/svg/resolver.dart';
import 'package:vector_graphics_compiler/src/svg/visitor.dart';
import 'dart:core';
import 'dart:typed_data';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart';
import 'package:path_ops/path_ops.dart' as path_ops;

class _EmptyNode extends Node {
  const _EmptyNode();

  @override
  S accept<S, V>(Visitor<S, V> visitor, V data) {
    return visitor.visitEmptyNode(this, data);
  }

  @override
  void visitChildren(NodeCallback visitor) {}
}

// TODO: Edit result class to pass children information to parent
class _Result {
  _Result(this.node);

  final Node node;
  int childCount = 0;
  List<Node> children = [];
  Node parent = _EmptyNode();
  bool deleteMaskNode = true;
}

/// Converts vector_graphics Path to path_ops Path
path_ops.Path toPathOpsPath(Path path) {
  path_ops.Path newPath = path_ops.Path();

  if (path.fillType == PathFillType.evenOdd) {
    newPath = path_ops.Path(path_ops.FillType.evenOdd);
  }

  for (PathCommand command in path.commands) {
    switch (command.type) {
      case PathCommandType.line:
        {
          final LineToCommand lineToCommand = command as LineToCommand;
          newPath.lineTo(lineToCommand.x, lineToCommand.y);
        }
        break;
      case PathCommandType.cubic:
        {
          final CubicToCommand cubicToCommand = command as CubicToCommand;
          newPath.cubicTo(
              cubicToCommand.x1,
              cubicToCommand.y1,
              cubicToCommand.x2,
              cubicToCommand.y2,
              cubicToCommand.x3,
              cubicToCommand.y3);
        }
        break;
      case PathCommandType.move:
        {
          final MoveToCommand moveToCommand = command as MoveToCommand;
          newPath.moveTo(moveToCommand.x, moveToCommand.y);
        }
        break;
      case PathCommandType.close:
        {
          newPath.close();
        }
        break;
    }
  }

  return newPath;
}

/// Converts path_ops Path to VectorGraphicsPath
Path toVectorGraphicsPath(path_ops.Path path) {
  final List<PathCommand> newCommands = [];

  int index = 0;
  final Float32List points = path.points;
  for (path_ops.PathVerb verb in path.verbs.toList()) {
    switch (verb) {
      case path_ops.PathVerb.moveTo:
        {
          newCommands.add(MoveToCommand(points[index++], points[index++]));
        }
        break;
      case path_ops.PathVerb.lineTo:
        {
          newCommands.add(LineToCommand(points[index++], points[index++]));
        }
        break;
      case path_ops.PathVerb.cubicTo:
        {
          newCommands.add(CubicToCommand(
            points[index++],
            points[index++],
            points[index++],
            points[index++],
            points[index++],
            points[index++],
          ));
        }
        break;
      case path_ops.PathVerb.close:
        newCommands.add(const CloseCommand());
        break;
    }
  }

  Path newPath = Path(commands: newCommands);

  if (path.fillType == path_ops.FillType.evenOdd) {
    newPath = Path(commands: newCommands, fillType: PathFillType.evenOdd);
  }

  return newPath;
}

/// Gets the single child recursively,
/// returns null if there are 0 children or more than 1
ResolvedPathNode? getSingleChild(Node node) {
  if (node.runtimeType.toString() == 'ResolvedPathNode') {
    return node as ResolvedPathNode;
  } else if (node.runtimeType.toString() == 'ParentNode') {
    if ((node as ParentNode).children.length == 1) {
      return getSingleChild(node.children.single);
    } else {
      return null;
    }
  } else {
    return null;
  }
}

/// Traverses all children of a given node
List<T> queryChildren<T extends Node>(Node node) {
  final List<T> children = <T>[];
  void visitor(Node child) {
    if (child is T) {
      children.add(child);
    }
    child.visitChildren(visitor);
  }

  node.visitChildren(visitor);
  return children;
}

/// Checks if one shape is inside another using rectagle bounds
bool isInside(Rect outerShape, Rect innerShape) {
  return ((innerShape.left > outerShape.left) &&
      (innerShape.right < outerShape.right) &&
      (innerShape.top > outerShape.top) &&
      (innerShape.bottom < outerShape.bottom));
}

/// Parses SVG string to node tree and runs it through the resolver
Future<Node> parseAndResolve(String source) async {
  final Node node = await parseToNodeTree(source);
  final ResolvingVisitor visitor = ResolvingVisitor();
  return node.accept(visitor, AffineMatrix.identity);
}

/// Simplifies masking operations into PathNodes
class MaskingOptimizer extends Visitor<_Result, Node>
    with ErrorOnUnResolvedNode<_Result, Node> {
  ///List of masks to add.
  List<ResolvedPathNode> masksToApply = [];

  /// Applies visitor to given node
  Node apply(Node node) {
    final Node newNode = node.accept(this, null).node;
    return newNode;
  }

  /// Applies mask to a path node, and returns resulting path node.
  ResolvedPathNode applyMask(Node child, ResolvedPathNode maskPathNode) {
    final ResolvedPathNode pathNode = child as ResolvedPathNode;
    final path_ops.Path maskPathOpsPath = toPathOpsPath(maskPathNode.path);
    maskPathOpsPath.applyOp(
        toPathOpsPath(pathNode.path), path_ops.PathOp.intersect);
    final Path newPath = toVectorGraphicsPath(maskPathOpsPath);
    final ResolvedPathNode newPathNode = ResolvedPathNode(
        paint: pathNode.paint, bounds: maskPathNode.bounds, path: newPath);
    return newPathNode;
  }

  @override
  _Result visitEmptyNode(Node node, void data) {
    final _Result _result = _Result(node);
    return _result;
  }

  @override
  _Result visitChildren(Node node, void data) {
    throw UnimplementedError();
  }

  @override
  _Result visitParentNode(ParentNode parentNode, Node data) {
    final List<Node> newChildren = [];
    bool deleteMaskNode = true;

    for (Node child in parentNode.children) {
      final _Result childResult = child.accept(this, parentNode);
      newChildren.add(childResult.node);
      if (childResult.deleteMaskNode == false) {
        deleteMaskNode = false;
      }
    }

    final ParentNode newParentNode = ParentNode(parentNode.attributes,
        precalculatedTransform: parentNode.transform, children: newChildren);

    final _Result _result = _Result(newParentNode);

    _result.deleteMaskNode = deleteMaskNode;

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
    _Result _result = _Result(maskNode);
    final ResolvedPathNode? singleMaskPathNode = getSingleChild(maskNode.mask);
    //bool deleteMaskNode = true;

    if (singleMaskPathNode != null) {
      masksToApply.add(singleMaskPathNode);
      final _Result childResult = maskNode.child.accept(this, maskNode);
      masksToApply.removeLast();

      if (childResult.deleteMaskNode == true) {
        _result = _Result(childResult.node);
      } else {
        final ResolvedMaskNode newMaskNode = ResolvedMaskNode(
            child: childResult.node,
            mask: maskNode.mask,
            blendMode: maskNode.blendMode);
        _result = _Result(newMaskNode);
      }
    } else {
      final _Result childResult = maskNode.child.accept(this, maskNode);
      final ResolvedMaskNode newMaskNode = ResolvedMaskNode(
          child: childResult.node,
          mask: maskNode.mask,
          blendMode: maskNode.blendMode);
      _result = _Result(newMaskNode);
    }

    return _result;
  }

  @override
  _Result visitResolvedClipNode(ResolvedClipNode clipNode, Node data) {
    final _Result childResult = clipNode.child.accept(this, clipNode);
    final ResolvedClipNode newClipNode =
        ResolvedClipNode(clips: clipNode.clips, child: childResult.node);
    final _Result _result = _Result(newClipNode);
    _result.children.add(childResult.node);
    _result.childCount = 1;

    return _result;
  }

  @override
  _Result visitResolvedPath(ResolvedPathNode pathNode, Node data) {
    _Result _result = _Result(pathNode);
    bool hasStrokeWidth = false;

    if (pathNode.paint.stroke != null) {
      if (pathNode.paint.stroke!.width != null) {
        hasStrokeWidth = true;
        _result.deleteMaskNode = false;
      }
    }

    if (masksToApply.isNotEmpty && !hasStrokeWidth) {
      ResolvedPathNode newPathNode = pathNode;
      for (ResolvedPathNode maskPathNode in masksToApply) {
        final ResolvedPathNode intersection =
            applyMask(newPathNode, maskPathNode);
        if (intersection.path.commands.isNotEmpty) {
          newPathNode = intersection;
        } else {
          _result = _Result(pathNode);
          _result.deleteMaskNode = false;
          break;
        }
      }

      _result = _Result(newPathNode);
    }

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
    final List<Node> newChildren = [];
    for (Node child in layerNode.children) {
      final _Result childResult = child.accept(this, layerNode);
      newChildren.add(childResult.node);
    }
    final SaveLayerNode newLayerNode = SaveLayerNode(layerNode.attributes,
        paint: layerNode.paint, children: newChildren);

    final _Result _result = _Result(newLayerNode);
    _result.children = newChildren;
    _result.childCount = newChildren.length;
    return _result;
  }

  @override
  _Result visitViewportNode(ViewportNode viewportNode, void data) {
    final List<Node> children = [];
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
    _result.children = children;
    _result.childCount = children.length;
    return _result;
  }
}

//void main() async {}
