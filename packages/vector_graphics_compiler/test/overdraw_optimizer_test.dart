// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:test/test.dart';
import 'package:vector_graphics_compiler/src/svg/node.dart';
import 'package:vector_graphics_compiler/src/svg/overdraw_optimizer.dart';
import 'package:vector_graphics_compiler/src/svg/parser.dart';
import 'package:vector_graphics_compiler/src/svg/resolver.dart';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart';
import 'test_svg_strings.dart';

Future<Node> parseAndResolve(String source) async {
  final Node node = await parseToNodeTree(source);
  final ResolvingVisitor visitor = ResolvingVisitor();
  return node.accept(visitor, AffineMatrix.identity);
}

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

void main() {
  setUpAll(() {
    if (!initializePathOpsFromFlutterCache()) {
      fail('error in setup');
    }
  });
  test('Basic case of two opaque shapes overlapping', () async {
    final Node node = await parseAndResolve(basicOverlap);
    final VectorInstructions instructions = await parse(basicOverlap);

    final List<ResolvedPathNode> pathNodesOld =
        queryChildren<ResolvedPathNode>(node);

    final OverdrawOptimizer visitor = OverdrawOptimizer();
    final Node newNode = visitor.apply(node);

    final List<ResolvedPathNode> pathNodesNew =
        queryChildren<ResolvedPathNode>(newNode);

    expect(pathNodesOld.length, pathNodesNew.length);

    expect(instructions.paints, const <Paint>[
      Paint(blendMode: BlendMode.srcOver, fill: Fill(color: Color(0xffadd8e6))),
      Paint(
          blendMode: BlendMode.multiply,
          fill: Fill(
              color: Color(0x98ffffff),
              shader: LinearGradient(
                  id: 'url(#linearGradient-3)',
                  from: Point(46.9782516, 60.9121966),
                  to: Point(60.42279469999999, 90.6839734),
                  colors: <Color>[Color(0xffffffff), Color(0xff0000ff)],
                  offsets: <double>[0.0, 1.0],
                  tileMode: TileMode.clamp,
                  unitMode: GradientUnitMode.transformed)))
    ]);

    expect(instructions.paths, <Path>[
      Path(
        commands: const <PathCommand>[
          MoveToCommand(50.0, 0.0),
          CubicToCommand(77.5957512247, 0.0, 100.0, 22.4042487753, 100.0, 50.0),
          CubicToCommand(
              100.0, 77.5957512247, 77.5957512247, 100.0, 50.0, 100.0),
          CubicToCommand(22.4042487753, 100.0, 0.0, 77.5957512247, 0.0, 50.0),
          CubicToCommand(0.0, 22.4042487753, 22.4042487753, 0.0, 50.0, 0.0),
          CloseCommand()
        ],
      ),
      Path(
        commands: const <PathCommand>[
          MoveToCommand(90.0, 50.0),
          CubicToCommand(
              90.0, 27.923398971557617, 72.07659912109375, 10.0, 50.0, 10.0),
          CubicToCommand(
              27.923398971557617, 10.0, 10.0, 27.923398971557617, 10.0, 50.0),
          CubicToCommand(
              10.0, 72.07659912109375, 27.923398971557617, 90.0, 50.0, 90.0),
          CubicToCommand(
              72.07659912109375, 90.0, 90.0, 72.07659912109375, 90.0, 50.0),
          CloseCommand()
        ],
      )
    ]);
  });

  test('Basic case of two shapes with opacity < 1.0 overlapping', () async {
    final Node node = await parseAndResolve(opacityOverlap);
    final VectorInstructions instructions = await parse(opacityOverlap);

    final List<ResolvedPathNode> pathNodesOld =
        queryChildren<ResolvedPathNode>(node);

    final OverdrawOptimizer visitor = OverdrawOptimizer();
    final Node newNode = visitor.apply(node);

    final List<ResolvedPathNode> pathNodesNew =
        queryChildren<ResolvedPathNode>(newNode);

    expect(pathNodesNew.length, 3);

    expect(instructions.paints, const <Paint>[
      Paint(blendMode: BlendMode.srcOver, fill: Fill(color: Color(0xffadd8e6))),
      Paint(
          blendMode: BlendMode.multiply,
          fill: Fill(
              color: Color(0x98ffffff),
              shader: LinearGradient(
                  id: 'url(#linearGradient-3)',
                  from: Point(46.9782516, 60.9121966),
                  to: Point(60.42279469999999, 90.6839734),
                  colors: <Color>[Color(0xffffffff), Color(0xff0000ff)],
                  offsets: <double>[0.0, 1.0],
                  tileMode: TileMode.clamp,
                  unitMode: GradientUnitMode.transformed)))
    ]);

    expect(instructions.paths, <Path>[
      Path(
        commands: const <PathCommand>[
          MoveToCommand(50.0, 0.0),
          CubicToCommand(77.5957512247, 0.0, 100.0, 22.4042487753, 100.0, 50.0),
          CubicToCommand(
              100.0, 77.5957512247, 77.5957512247, 100.0, 50.0, 100.0),
          CubicToCommand(22.4042487753, 100.0, 0.0, 77.5957512247, 0.0, 50.0),
          CubicToCommand(0.0, 22.4042487753, 22.4042487753, 0.0, 50.0, 0.0),
          CloseCommand()
        ],
      ),
      Path(
        commands: const <PathCommand>[
          MoveToCommand(90.0, 50.0),
          CubicToCommand(
              90.0, 27.923398971557617, 72.07659912109375, 10.0, 50.0, 10.0),
          CubicToCommand(
              27.923398971557617, 10.0, 10.0, 27.923398971557617, 10.0, 50.0),
          CubicToCommand(
              10.0, 72.07659912109375, 27.923398971557617, 90.0, 50.0, 90.0),
          CubicToCommand(
              72.07659912109375, 90.0, 90.0, 72.07659912109375, 90.0, 50.0),
          CloseCommand()
        ],
      )
    ]);
  });

  test('Solid shape overlapping semi-transparent shape', () async {
    final Node node = await parseAndResolve(solidOverTrasnparent);
    final OverdrawOptimizer visitor = OverdrawOptimizer();
    final Node newNode = visitor.apply(node);

    final List<ResolvedClipNode> clipNodesNew =
        queryChildren<ResolvedClipNode>(newNode);

    expect(clipNodesNew.length, 1);
  });

  test('Semi-transparent shape overlapping solid shape', () async {
    final Node node = await parseAndResolve(transparentOverSolid);

    final List<ResolvedPathNode> pathNodesOld =
        queryChildren<ResolvedPathNode>(node);
    final List<ParentNode> parentNodesOld = queryChildren<ParentNode>(node);

    final OverdrawOptimizer visitor = OverdrawOptimizer();
    final Node newNode = visitor.apply(node);

    final List<ResolvedPathNode> pathNodesNew =
        queryChildren<ResolvedPathNode>(newNode);
    final List<ParentNode> parentNodesNew = queryChildren<ParentNode>(newNode);

    expect(pathNodesOld.length, pathNodesNew.length);
    expect(parentNodesOld.length, parentNodesNew.length);
  });

  test('Multiple opaque and semi-trasnparent shapes', () async {
    final Node node = await parseAndResolve(complexOpacityTest);

    final List<ResolvedPathNode> pathNodesOld =
        queryChildren<ResolvedPathNode>(node);
    final List<ParentNode> parentNodesOld = queryChildren<ParentNode>(node);

    final OverdrawOptimizer visitor = OverdrawOptimizer();
    final Node newNode = visitor.apply(node);

    final List<ResolvedPathNode> pathNodesNew =
        queryChildren<ResolvedPathNode>(newNode);
    final List<ParentNode> parentNodesNew = queryChildren<ParentNode>(newNode);

    expect(pathNodesOld.length, pathNodesNew.length);
    expect(parentNodesOld.length, parentNodesNew.length);
  });
}
