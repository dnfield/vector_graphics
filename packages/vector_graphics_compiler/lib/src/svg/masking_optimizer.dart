import 'dart:ui';

import 'package:vector_graphics_compiler/src/svg/node.dart';
import 'package:vector_graphics_compiler/src/svg/parser.dart';
import 'package:vector_graphics_compiler/src/svg/resolver.dart';
import 'package:vector_graphics_compiler/src/svg/visitor.dart';
import 'dart:core';
import 'dart:typed_data';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart';
import 'package:pathkit/pathkit.dart' as pathkit;

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
  int grandchildCount = 0;
  List<Node> children = [];
  Node parent = _EmptyNode();
  bool deleteNode = false;
}

/// Converts vector_graphics Path to PathKit Path
pathkit.Path toPathKitPath(Path path) {
  pathkit.Path newPath = pathkit.Path();

  if (path.fillType == PathFillType.evenOdd) {
    newPath = pathkit.Path(pathkit.FillType.evenOdd);
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

/// Converts PathKit Path to VectorGraphicsPath
Path toVectorGraphicsPath(pathkit.Path path) {
  final List<PathCommand> newCommands = [];

  int index = 0;
  final Float32List points = path.points;
  for (pathkit.PathVerb verb in path.verbs.toList()) {
    switch (verb) {
      case pathkit.PathVerb.moveTo:
        {
          newCommands.add(MoveToCommand(points[index++], points[index++]));
        }
        break;
      case pathkit.PathVerb.lineTo:
        {
          newCommands.add(LineToCommand(points[index++], points[index++]));
        }
        break;
      case pathkit.PathVerb.cubicTo:
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
      case pathkit.PathVerb.close:
        newCommands.add(const CloseCommand());
        break;
    }
  }

  Path newPath = Path(commands: newCommands);

  if (path.fillType == pathkit.FillType.evenOdd) {
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
      return getSingleChild((node as ParentNode).children.single);
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
  ///Holds ResolvedMaskNode Type for children refrences between function calls.
  Map<String, ResolvedMaskNode> resolvedMaskDict = {};

  Map<String, ResolvedMaskNode> maskDict = {};

  /// Dictionary of known PathNodes that have masks applied to them.
  /// Key: ResolvedMaskNode, Value: List of PathNodes
  Map<ResolvedMaskNode, List<ResolvedPathNode>> pathNodesWithMasks = {};

  /// Dictionary of known PathNodes that create a mask.
  /// Key: ResolvedMaskNode, Value: List of PathNodes
  Map<ResolvedMaskNode, List<ResolvedPathNode>> maskInstructions = {};

  /// Dictionary of known PathNodes key: commands as a string, value: PathNode
  Map<String, PathNode> pathDict = {};

  /// List of pathNodes that are not attatched to a parent Node
  List<Node> orphanPathNodes = [];

  /// Applies visitor to given node
  Node apply(Node node) {
    final Node newNode = node.accept(this, null).node;
    return newNode;
  }

  /// Applies mask to a path node, and returns resulting path node.
  ResolvedPathNode applyMask(Node child, ResolvedPathNode maskPathNode) {
    final ResolvedPathNode pathNode = child as ResolvedPathNode;
    final pathkit.Path maskPathKitPath = toPathKitPath(maskPathNode.path);
    maskPathKitPath.applyOp(
        toPathKitPath(pathNode.path), pathkit.PathOp.intersect);
    final Path newPath = toVectorGraphicsPath(maskPathKitPath);
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
    List<Node> newChildren = [];

    try {
      pathNodesWithMasks[resolvedMaskDict[parentNode.hashCode.toString()]
          as ResolvedMaskNode] = [];
    } catch (e) {
      try {
        maskInstructions[
            maskDict[parentNode.hashCode.toString()] as ResolvedMaskNode] = [];
      } catch (e) {
        print(parentNode.children);
        print(data.runtimeType);
      }
    }

    for (Node child in parentNode.children) {
      if (child.runtimeType.toString() == 'ResolvedPathNode') {
        if (resolvedMaskDict.containsKey(parentNode.hashCode.toString())) {
          pathNodesWithMasks[resolvedMaskDict[parentNode.hashCode.toString()]
                  as ResolvedMaskNode]
              ?.add(child as ResolvedPathNode);
        } else if (maskDict.containsKey(parentNode.hashCode.toString())) {
          maskInstructions[
                  maskDict[parentNode.hashCode.toString()] as ResolvedMaskNode]
              ?.add(child as ResolvedPathNode);
        }
      } else {
        _Result childResult = child.accept(this, parentNode);
        newChildren.add(childResult.node);
      }
    }

    ParentNode newParentNode = ParentNode(parentNode.attributes,
        precalculatedTransform: parentNode.transform, children: newChildren);

    _Result _result = _Result(newParentNode);
    _result.children = newChildren;
    _result.childCount = _result.children.length;

    return _result;
  }

  @override
  _Result visitMaskNode(MaskNode maskNode, Node data) {
    final _Result _result = _Result(maskNode);

    final _Result parentNode = maskNode.child.accept(this, maskNode);
    _result.grandchildCount = parentNode.childCount;

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

    resolvedMaskDict[maskNode.child.hashCode.toString()] = maskNode;
    maskDict[maskNode.mask.hashCode.toString()] = maskNode;

    if (maskNode.child.runtimeType.toString() == 'ResolvedMaskNode' ||
        maskNode.child.runtimeType.toString() == 'ParentNode' ||
        maskNode.child.runtimeType.toString() == 'ResolvedPathNode') {
      ResolvedPathNode? maskResult = getSingleChild(maskNode.mask);
      final _Result childResult = maskNode.child.accept(this, maskNode);

      if (maskResult != null) {
        final ResolvedPathNode maskPathNode = maskResult;

        if (childResult.childCount == 0) {
          ResolvedPathNode pathNode = ResolvedPathNode(
              paint: const Paint(),
              bounds: const Rect.fromCircle(0, 0, 0),
              path: Path());

          //if (childResult.childCount == 0) {
          pathNode = childResult.node as ResolvedPathNode;
          // } else if (childResult.childCount == 1) {
          // pathNode = pathNodesWithMasks[maskNode]?.single as ResolvedPathNode;
          //}
          final ResolvedPathNode newPathNode =
              applyMask(pathNode, maskPathNode);
          _result = _Result(newPathNode);
        } else {
          final ParentNode parentNode = childResult.node as ParentNode;
          final List<Node> newChildren = [];
          for (Node child in parentNode.children) {
            if (child.runtimeType.toString() == 'ResolvedPathNode') {
              final ResolvedPathNode newPathNode =
                  applyMask(child, maskPathNode);
              newChildren.add(newPathNode);
            } else {
              final _Result recurseResult = child.accept(this, parentNode);
              newChildren.add(recurseResult.node);
            }
          }
          final ParentNode newParentNode = ParentNode(parentNode.attributes,
              precalculatedTransform: parentNode.transform,
              children: newChildren);
          _result = _Result(newParentNode);
          _result.children = newChildren;
          _result.childCount = newChildren.length;
        }
      }
    } else if (maskNode.child.runtimeType.toString() == 'ResolvedClipNode') {
      final _Result maskResult = maskNode.mask.accept(this, maskNode);
      if (maskResult.childCount <= 1) {
        ResolvedPathNode maskPathNode;
        try {
          maskPathNode = maskResult.node as ResolvedPathNode;
        } catch (e) {
          maskPathNode = (maskResult.node as ParentNode).children.single
              as ResolvedPathNode;
        }
        ResolvedClipNode clipNode = maskNode.child as ResolvedClipNode;
        if (clipNode.child.runtimeType.toString() == 'ParentNode') {
          ParentNode parentNode = clipNode.child as ParentNode;
          List<Node> newChildren = [];
          for (Node child in parentNode.children) {
            if (child.runtimeType.toString() == 'ResolvedPathNode') {
              newChildren.add(applyMask(child, maskPathNode));
            } else {
              _Result recurseResult = child.accept(this, clipNode);
              newChildren.add(recurseResult.node);
            }
          }
          ParentNode newParentNode = ParentNode(parentNode.attributes,
              precalculatedTransform: parentNode.transform,
              children: newChildren);
          ResolvedClipNode newClipNode =
              ResolvedClipNode(clips: clipNode.clips, child: newParentNode);

          _result = _Result(newClipNode);
          _result.children.add(newParentNode);
          _result.childCount = 1;
        } else if (clipNode.child.runtimeType.toString() ==
            'ResolvedPathNode') {
          ResolvedClipNode newClipNode = ResolvedClipNode(
              clips: clipNode.clips,
              child: applyMask(clipNode.child, maskPathNode));
          _result = _Result(newClipNode);
          _result.children.add(newClipNode.child);
          _result.childCount = 1;
        }
      }
    } else {
      final _Result childResult = maskNode.child.accept(this, maskNode);
      ResolvedMaskNode newMaskNode = ResolvedMaskNode(
          child: childResult.node,
          mask: maskNode.mask,
          blendMode: maskNode.blendMode);

      _result = _Result(newMaskNode);
      _result.children.add(childResult.node);
      _result.childCount = 1;
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
    List<Node> newChildren = [];
    for (Node child in layerNode.children) {
      _Result childResult = child.accept(this, layerNode);
      newChildren.add(childResult.node);
    }
    SaveLayerNode newLayerNode = SaveLayerNode(layerNode.attributes,
        paint: layerNode.paint, children: newChildren);

    _Result _result = _Result(layerNode);
    _result.children = newChildren;
    _result.childCount = newChildren.length;
    return _result;
  }

  @override
  _Result visitViewportNode(ViewportNode viewportNode, void data) {
    final List<Node> children = [];

    /*
    for (Node child in viewportNode.children) {
      if (child.runtimeType.toString() == 'ResolvedMaskNode') {
        final _Result childNode = child.accept(this, viewportNode);
        children.add(childNode.node);
      } else {
        children.add(child);
      }
    }
    */
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

    //print("New viewPortNode childCount : " + node.children.length.toString());

    final _Result _result = _Result(node);
    _result.children = children;
    _result.childCount = children.length;
    return _result;
  }
}

void main() async {
  /*
  test('Resolve case of when singular pathnode is made into mask', () async {
    final Node node = await parseAndResolve('''
<svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
  
  <mask id="a" maskUnits="userSpaceOnUse" x="3" y="7" width="18" height="11">
    <path fill-rule="evenodd" clip-rule="evenodd" d="M15.094 17.092a.882.882 0 01-.623-1.503l2.656-2.66H4.28a.883.883 0 010-1.765h12.846L14.47 8.503a.88.88 0 011.245-1.245l4.611 4.611a.252.252 0 010 .354l-4.611 4.611a.876.876 0 01-.622.258z" fill="#fff" />
  </mask>

  <g mask="url(#a)">
    <path fill-rule="evenodd" clip-rule="evenodd" d="M0 0h24v24.375H0V0z" fill="#fff" />
  </g>

</svg>''');

    final List<ResolvedPathNode> pathNodesOld =
        queryChildren<ResolvedPathNode>(node);
    final List<ResolvedMaskNode> maskNodesOld =
        queryChildren<ResolvedMaskNode>(node);
    final List<ParentNode> parentNodesOld = queryChildren<ParentNode>(node);

    // final String test = pathNodesOld.first.path.commands.toString();

    final MaskingOptimizer visitor = MaskingOptimizer();

    final Node newNode = visitor.apply(node);
    final List<ResolvedPathNode> pathNodes =
        queryChildren<ResolvedPathNode>(newNode);
    final List<ResolvedMaskNode> maskNodes =
        queryChildren<ResolvedMaskNode>(newNode);
    final List<ParentNode> parentNodes = queryChildren<ParentNode>(newNode);

    //Confirm this was old structure
    //
    //           ViewportNode
    //                |
    //          ResolvedMaskNode
    //         /              \
    //    ParentNode(Mask)    ParentNode
    //         |                    |
    //      PathNode             PathNode

    expect(pathNodesOld.length, 1);
    expect(maskNodesOld.length, 1);
    expect(parentNodesOld.length, 1);

    //Confirm this is the new structure
    //
    //      ViewportNode
    //            |
    //        PathNode

    print('In the resolved node...');
    print('There are ' + (pathNodes.length).toString() + ' PathNodes');
    print('There are ' + (maskNodes.length).toString() + ' MaskNodes');
    print('There are ' + (parentNodes.length).toString() + ' ParentNodes');

    expect(pathNodes.length, 1);
    expect(maskNodes.length, 0);
    expect(parentNodes.length, 0);
  });
  */

  /*

  //NEED TO CORRECT SVG SAMPLE

  test('Confirm mask with singular pathNode works for multiple masks',
      () async {
    final Node node = await parseAndResolve('''
<svg width="1024px" height="1024px" viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">

  <mask id="a" maskUnits="userSpaceOnUse" x="3" y="7" width="18" height="11">
    <path fill-rule="evenodd" clip-rule="evenodd" d="M15.094 17.092a.882.882 0 01-.623-1.503l2.656-2.66H4.28a.883.883 0 010-1.765h12.846L14.47 8.503a.88.88 0 011.245-1.245l4.611 4.611a.252.252 0 010 .354l-4.611 4.611a.876.876 0 01-.622.258z" fill="#fff" />
  </mask>


  <mask id="b" maskUnits="userSpaceOnUse" x="3" y="7" width="18" height="11">
    <path fill-rule="evenodd" clip-rule="evenodd" d="M15.094 17.092a.882.882 0 01-.622-1.503l2.656-2.66H4.28a.883.883 0 010-1.765h12.846L14.47 8.503a.88.88 0 011.245-1.245l4.611 4.611a.252.252 0 010 .354l-4.611 4.611a.876.876 0 01-.622.258z" fill="#fff" />
  </mask>

  <g mask="url(#a)">
    <path fill="#D8D8D8" d="M232 616h560V408H232v208zm112-144c22.1 0 40 17.9 40 40s-17.9 40-40 40-40-17.9-40-40 17.9-40 40-40zM232 888h560V680H232v208zm112-144c22.1 0 40 17.9 40 40s-17.9 40-40 40-40-17.9-40-40 17.9-40 40-40zM232 344h560V136H232v208zm112-144c22.1 0 40 17.9 40 40s-17.9 40-40 40-40-17.9-40-40 17.9-40 40-40z"/>
  </g>

  <g mask="url(#b)">
    <path d="M304 512a40 40 0 1 0 80 0 40 40 0 1 0-80 0zm0 272a40 40 0 1 0 80 0 40 40 0 1 0-80 0zm0-544a40 40 0 1 0 80 0 40 40 0 1 0-80 0z"/>
    <path d="M832 64H192c-17.7 0-32 14.3-32 32v832c0 17.7 14.3 32 32 32h640c17.7 0 32-14.3 32-32V96c0-17.7-14.3-32-32-32zm-40 824H232V680h560v208zm0-272H232V408h560v208zm0-272H232V136h560v208z"/>
  </g>

</svg>
''');

    //Confirm this was old structure

    final List<ResolvedPathNode> pathNodesOld =
        queryChildren<ResolvedPathNode>(node);
    final List<ResolvedMaskNode> maskNodesOld =
        queryChildren<ResolvedMaskNode>(node);
    final List<ParentNode> parentNodesOld = queryChildren<ParentNode>(node);

    print('There are ' + (pathNodesOld.length).toString() + ' PathNodes');
    print('There are ' + (maskNodesOld.length).toString() + ' MaskNodes');
    print('There are ' + (parentNodesOld.length).toString() + ' ParentNodes');

    expect(pathNodesOld.length, 3);
    expect(maskNodesOld.length, 2);
    expect(parentNodesOld.length, 2);

    // Confirm this is the new structure
    //
    //                   ViewPortNode
    //                   /         \
    //              MaskNode     PathNode
    //                 |
    //             ParentNode
    //             /       \
    //         PathNode  PathNode

    final MaskingOptimizer visitor = MaskingOptimizer();

    final Node newNode = visitor.apply(node);

    final List<ResolvedPathNode> pathNodes =
        queryChildren<ResolvedPathNode>(newNode);
    final List<ResolvedMaskNode> maskNodes =
        queryChildren<ResolvedMaskNode>(newNode);
    final List<ParentNode> parentNodes = queryChildren<ParentNode>(newNode);

    /*
  print('In the resolved node...');
  print('There are '+(pathNodes.length).toString()+' PathNodes');
  print('There are '+(maskNodes.length).toString()+' MaskNodes');
  print('There are '+(parentNodes.length).toString()+' ParentNodes');
  */

    expect(pathNodes.length, 3);
    expect(maskNodes.length, 1);
    expect(parentNodes.length, 1);
  });
  */

  /*
  //NOT SUPPORTED
  // WILL REVISIT LATER

  
  test(
      'Resolved case of when shape is punched out of larger shape with no intersecting bounds',
      () async {
    final Node node = await parseAndResolve('''
    <svg viewBox="-10 -10 120 120">
    <mask id="myMask">
    
    <rect x="0" y="0" width="100" height="100" fill="white" />

    <path d="M10,35 A20,20,0,0,1,50,35 A20,20,0,0,1,90,35 Q90,65,50,95 Q10,65,10,35 Z" fill="black" />
    </mask>

    <!-- <polygon points="-10,110 110,110 110,-10" fill="orange" /> -->

    <circle cx="50" cy="50" r="50" mask="url(#myMask)" />
    </svg>

  ''');

    final List<ResolvedPathNode> pathNodesOld =
        queryChildren<ResolvedPathNode>(node);
    final List<ResolvedMaskNode> maskNodesOld =
        queryChildren<ResolvedMaskNode>(node);
    final List<ParentNode> parentNodesOld = queryChildren<ParentNode>(node);

    print("RESOLVED NODE TREE");

    /*
  print('There are '+(pathNodesOld.length).toString()+' PathNodes');
  print('There are '+(maskNodesOld.length).toString()+' MaskNodes');
  print('There are '+(parentNodesOld.length).toString()+' ParentNodes');
  */




    final MaskingOptimizer visitor = MaskingOptimizer();

    final Node newNode = visitor.apply(node);

  

  
  });

  */

  final Node node = await parseAndResolve('''
<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64" fill="none"><mask id="a" style="mask-type:alpha" maskUnits="userSpaceOnUse" x="0" y="0" width="64" height="64"><circle cx="32" cy="32" r="32" fill="#C4C4C4"/></mask><g clip-path="url(#clip0_2630_58398)" mask="url(#a)"><path d="M65.564 0H-3.041v65.807h68.605V0z" fill="#669DF6"/><path d="M69.185-14.857h-77.29v65.143h77.29v-65.143z" fill="#D2E3FC"/><path d="M21.792 2.642l-24.045.056.124 51.288 24.028-.039-.107-51.305z" fill="#FBBC04"/><path d="M1.931 10.286a1.543 1.543 0 013.086-.008v2.26a1.543 1.543 0 01-3.086.007v-2.26zm1.571 12.292a1.545 1.545 0 01-1.544-1.537l-.006-2.26a1.543 1.543 0 013.086-.006v2.26a1.545 1.545 0 01-1.536 1.543zM8.33 10.27a1.543 1.543 0 013.086-.007l.006 2.26a1.543 1.543 0 01-3.086.006l-.006-2.26zM9.9 22.563a1.546 1.546 0 01-1.545-1.534v-2.261a1.543 1.543 0 113.086-.007v2.26a1.546 1.546 0 01-1.54 1.542zm4.828-12.308a1.544 1.544 0 012.13-1.431 1.542 1.542 0 01.956 1.423v2.26a1.54 1.54 0 01-1.54 1.546 1.542 1.542 0 01-1.546-1.539v-2.26zm1.57 12.292a1.545 1.545 0 01-1.544-1.537l-.005-2.26a1.544 1.544 0 012.63-1.096 1.542 1.542 0 01.455 1.09v2.26a1.545 1.545 0 01-1.536 1.543zM1.959 27.278a1.543 1.543 0 113.086-.007v2.26a1.543 1.543 0 11-3.086.007v-2.26zM3.53 39.571a1.544 1.544 0 01-1.545-1.537l-.006-2.263a1.543 1.543 0 113.086-.008v2.261a1.545 1.545 0 01-1.536 1.547zm4.826-12.308a1.543 1.543 0 113.086-.008v2.26a1.542 1.542 0 01-3.086.007v-2.26zm1.571 12.292a1.545 1.545 0 01-1.544-1.536v-2.26a1.543 1.543 0 113.086-.007l.005 2.26a1.544 1.544 0 01-1.547 1.543zm4.828-12.308a1.542 1.542 0 113.086-.007l.006 2.26a1.543 1.543 0 11-3.086.007l-.006-2.26zm1.571 12.296a1.544 1.544 0 01-1.544-1.537v-2.26a1.543 1.543 0 013.085-.008l.006 2.26a1.546 1.546 0 01-1.547 1.545z" fill="#FDE293"/><path d="M22.783 5.54a1.077 1.077 0 001.05-1.306L22.83-.393a1.387 1.387 0 00-1.325-.978l-23.456.037a1.39 1.39 0 00-1.322.98l-.989 4.633A1.077 1.077 0 00-3.208 5.58l25.99-.042z" fill="#F9AB00"/><path d="M43.051 53.973h65.009l.046-36.144a2.921 2.921 0 00-2.924-2.924l-59.16.404a2.924 2.924 0 00-2.925 2.923l-.046 35.74z" fill="#81C995"/><path d="M62.483 15.148h3.275l-.248 7.893c-.01.057-.019.114-.035.17v.014c-.03.11-.071.216-.12.319a1.744 1.744 0 01-2.244.895 1.989 1.989 0 01-1.282-2.136l.654-7.155zm-21.512 7.023v-.013c.01-.059.029-.115.043-.167l2.138-6.838h3.174l-2.124 7.967h-.006a1.7 1.7 0 01-1.581 1.29 1.793 1.793 0 01-1.674-1.896c0-.115.01-.23.03-.343zm12.132-7.023h3.187l-1.704 8.1h-.006a1.62 1.62 0 01-1.581 1.29 1.793 1.793 0 01-1.675-1.891c.002-.077.009-.153.021-.229l-.203.836h-.006a1.703 1.703 0 01-1.582 1.289 1.792 1.792 0 01-1.668-1.897c0-.113.01-.224.03-.335l-.23.937h-.006a1.704 1.704 0 01-1.582 1.29 1.792 1.792 0 01-1.674-1.891c.001-.115.011-.23.03-.343v-.014c.009-.058.027-.114.04-.168l1.84-6.971h6.776l-.007-.003z" fill="#EA4335"/><path d="M62.483 15.126l-.718 7.885a1.715 1.715 0 01-1.7 1.53 1.654 1.654 0 01-1.852-1.667 2.581 2.581 0 010-.343l-.086.53-.02.15a1.696 1.696 0 01-1.546 1.318 1.758 1.758 0 01-1.79-1.752 2.31 2.31 0 01.01-.343v-.013c.007-.058.017-.115.03-.172l1.486-7.096 3.126-.022 3.06-.005z" fill="#EA4335"/><path d="M62.483 15.148h3.275l-.248 7.893c-.01.057-.019.114-.035.17v.014c-.03.11-.071.216-.12.319a1.745 1.745 0 01-2.244.896 1.99 1.99 0 01-1.276-2.137l.648-7.155zm-16.156 0h-3.174l-2.138 6.837c-.014.055-.032.114-.042.167v.015c-.02.113-.03.228-.031.343a1.794 1.794 0 001.675 1.89 1.7 1.7 0 001.58-1.29h.008l2.122-7.962zm6.776 0h-3.419l-1.73 6.97a1.671 1.671 0 00-.042.169v.014a2.13 2.13 0 00-.03.343 1.792 1.792 0 001.673 1.89 1.704 1.704 0 001.582-1.29h.006l1.96-8.096z" fill="#81CA95"/><path d="M49.685 15.148h-3.358l-1.839 6.97c-.014.057-.032.115-.041.169v.014a2.264 2.264 0 00-.03.343 1.792 1.792 0 001.675 1.89 1.703 1.703 0 001.581-1.29h.007l2.005-8.096z" fill="#35A853"/><path d="M59.416 15.126l-3.126.021-1.485 7.096a1.716 1.716 0 00-.031.172v.014a2.308 2.308 0 00-.01.342 1.759 1.759 0 001.79 1.752 1.696 1.696 0 001.545-1.317l.021-.151 1.296-7.93z" fill="#81CA95"/><path d="M62.483 15.126h-3.067l-1.182 7.21a1.71 1.71 0 00-.025.171v.015a2.515 2.515 0 000 .343 1.654 1.654 0 001.853 1.666 1.714 1.714 0 001.7-1.529l.721-7.876zm-6.193.022h-3.187l-1.705 6.97c-.015.057-.032.115-.043.169v.014a1.97 1.97 0 00-.03.343A1.793 1.793 0 0053 24.534a1.617 1.617 0 001.58-1.29h.008l1.702-8.096z" fill="#35A853"/><path d="M40.94 26.533h68.963v-4.221H40.941v4.22z" fill="#35A853"/><path d="M54.314 42.22l3.623.005a1.558 1.558 0 001.557-1.552l.009-5.845a1.559 1.559 0 00-1.552-1.556h-3.622a1.561 1.561 0 00-1.558 1.552l-.009 5.845a1.55 1.55 0 001.552 1.55z" fill="#A8DAB5"/><path d="M46.155 53.943l-25.27.04-.04-26.081a2.001 2.001 0 011.993-1.998l21.28-.034a2.001 2.001 0 011.997 1.992l.04 26.08z" fill="#AFCBFA"/><path d="M22.838 25.904a2.006 2.006 0 00-1.91 1.416l-2.065 7.9a3.656 3.656 0 107.314-.01l1.199-9.313-4.538.007z" fill="#669DF7"/><path d="M46.032 27.28a2.008 2.008 0 00-1.918-1.41l-4.538.008 1.229 9.307a3.656 3.656 0 107.314-.011l-2.087-7.894zm-12.554-1.393l-6.102.01-1.199 9.312a3.66 3.66 0 003.664 3.651 3.66 3.66 0 003.65-3.663l-.013-9.31z" fill="#E8F0FD"/><path d="M33.478 25.887l.015 9.31a3.658 3.658 0 007.314-.012l-1.229-9.307-6.1.009z" fill="#669DF7"/><path d="M38.03 53.973l-9.02.013-.015-10.026a1.652 1.652 0 011.65-1.655l5.715-.009a1.654 1.654 0 011.656 1.65l.015 10.027z" fill="#E8F0FE"/><path d="M27.578 11.599h-.006l.052.124.025.061 4.552 10.938a.868.868 0 001.6-.008l4.412-10.873a5.75 5.75 0 00.496-2.47 5.763 5.763 0 00-11.526.143 5.74 5.74 0 00.395 2.085z" fill="#EA4335"/><path d="M32.946 10.998a1.787 1.787 0 100-3.575 1.787 1.787 0 000 3.575z" fill="#A50E0E"/></g><defs><clipPath id="clip0_2630_58398"><path fill="#fff" d="M0 0h64v64H0z"/></clipPath></defs></svg>

''');

  final List<ResolvedPathNode> pathNodesOld =
      queryChildren<ResolvedPathNode>(node);
  final List<ResolvedMaskNode> maskNodesOld =
      queryChildren<ResolvedMaskNode>(node);
  final List<ParentNode> parentNodesOld = queryChildren<ParentNode>(node);

  final MaskingOptimizer visitor = MaskingOptimizer();

  final Node newNode = visitor.apply(node);
  final List<ResolvedPathNode> pathNodes =
      queryChildren<ResolvedPathNode>(newNode);
  final List<ResolvedMaskNode> maskNodes =
      queryChildren<ResolvedMaskNode>(newNode);
  final List<ParentNode> parentNodes = queryChildren<ParentNode>(newNode);

  print('In the resolved node...');
  print('There are ' + (pathNodes.length).toString() + ' PathNodes');
  print('There are ' + (maskNodes.length).toString() + ' MaskNodes');
  print('There are ' + (parentNodes.length).toString() + ' ParentNodes');
}
