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
    pathkit.Path newPath = pathkit.Path(pathkit.FillType.evenOdd);
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
  List<PathCommand> newCommands = [];

  int index = 0;
  Float32List points = path.points;
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

  final Path newPath = Path(commands: newCommands);

  if (path.fillType == pathkit.FillType.evenOdd) {
    final Path newPath =
        Path(commands: newCommands, fillType: PathFillType.evenOdd);
  }

  return newPath;
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
  /// Set to true if case is too complex for MaskingOptimizer
  bool svgNotSupported = false;

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
  _Result visitParentNode(ParentNode parentNode, Node parent) {
    final _Result _result = _Result(parentNode);
    _result.children = parentNode.children.toList();
    _result.childCount = _result.children.length;

    try {
      pathNodesWithMasks[resolvedMaskDict[parentNode.hashCode.toString()]
          as ResolvedMaskNode] = [];
    } catch (e) {
      maskInstructions[
          maskDict[parentNode.hashCode.toString()] as ResolvedMaskNode] = [];
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
      } else if (child.runtimeType.toString() == 'ResolvedMaskNode') {
        child.accept(this, null);
      }
    }

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
      final _Result maskResult = maskNode.mask.accept(this, maskNode);
      final _Result childResult = maskNode.child.accept(this, maskNode);

      if (childResult.childCount <= 1 && maskResult.childCount == 1) {
        final ResolvedPathNode maskPathNode =
            maskInstructions[maskNode]?.single as ResolvedPathNode;

        if (childResult.childCount == 1) {
          final ResolvedPathNode pathNode =
              pathNodesWithMasks[maskNode]?.single as ResolvedPathNode;

          pathkit.Path maskPathKitPath = toPathKitPath(maskPathNode.path);
          maskPathKitPath.applyOp(
              toPathKitPath(pathNode.path), pathkit.PathOp.intersect);
          Path newPath = toVectorGraphicsPath(maskPathKitPath);
          final ResolvedPathNode newPathNode = ResolvedPathNode(
              paint: pathNode.paint,
              bounds: maskPathNode.bounds,
              path: newPath);
          _result = _Result(newPathNode);
        } else if (childResult.childCount == 0) {
          final ResolvedPathNode pathNode =
              childResult.node as ResolvedPathNode;

          pathkit.Path maskPathKitPath = toPathKitPath(maskPathNode.path);
          maskPathKitPath.applyOp(
              toPathKitPath(pathNode.path), pathkit.PathOp.intersect);
          Path newPath = toVectorGraphicsPath(maskPathKitPath);
          final ResolvedPathNode newPathNode = ResolvedPathNode(
              paint: pathNode.paint,
              bounds: maskPathNode.bounds,
              path: newPath);
          _result = _Result(newPathNode);
        }
      }
    }
    /*
     to revisit later ...
    else {
      if (childResult.childCount == 1) {
        ResolvedPathNode pathNode =
            pathNodesWithMasks[maskNode]?.single as ResolvedPathNode;
        
        List<PathCommand> commandsToAdd = [];

        for (ResolvedPathNode maskPathNode
            in maskInstructions[maskNode] as List<ResolvedPathNode>) {
          if (isInside(pathNode.bounds, maskPathNode.bounds) && ) {
            pathNode.path.commands.toList();
          }
        }
      }
    }

    */

    return _result;
  }

  @override
  _Result visitResolvedClipNode(ResolvedClipNode clipNode, Node data) {
    // TODO: implement visitResolvedClipNode
    throw UnimplementedError();
  }

  @override
  _Result visitResolvedPath(ResolvedPathNode pathNode, Node data) {
    final _Result _result = _Result(pathNode);
    return _result;
  }

  @override
  _Result visitResolvedText(ResolvedTextNode textNode, Node data) {
    // TODO: implement visitResolvedText
    throw UnimplementedError();
  }

  @override
  _Result visitResolvedVerticesNode(
      ResolvedVerticesNode verticesNode, Node data) {
    // TODO: implement visitResolvedVerticesNode
    throw UnimplementedError();
  }

  @override
  _Result visitSaveLayerNode(SaveLayerNode layerNode, Node data) {
    // TODO: implement visitSaveLayerNode
    throw UnimplementedError();
  }

  @override
  _Result visitViewportNode(ViewportNode viewportNode, void data) {
    //print("Old viewportNode child count " +
    //    viewportNode.children.length.toString());

    //print(viewportNode.children);

    final List<Node> children = [];

    for (Node child in viewportNode.children) {
      if (child.runtimeType.toString() == 'ResolvedMaskNode') {
        final _Result childNode = child.accept(this, viewportNode);
        children.add(childNode.node);
      } else {
        children.add(child);
      }
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
<svg width="46" height="45" viewBox="0 0 46 45" fill="none" xmlns="http://www.w3.org/2000/svg">
  <mask id="a" maskUnits="userSpaceOnUse" x="0" y="1" width="46" height="44">
    <path fill-rule="evenodd" clip-rule="evenodd" d="M.36 22.78c0 12.026 10.09 21.774 22.536 21.774 12.445 0 22.533-9.748 22.533-21.773 0-12.02-10.09-21.77-22.54-21.77S.36 10.76.36 22.78z" fill="#fff" />
  </mask>
  <path fill-rule="evenodd" clip-rule="evenodd" d="M-26.706 48.184l-3.534-4.715L42.414-13.4l3.533 4.715-72.653 56.87z" fill="#FFE492" mask="url(#a)" />
</svg>''');

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
