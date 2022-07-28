// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:test/test.dart';
import 'package:vector_graphics_compiler/src/geometry/matrix.dart';
import 'package:vector_graphics_compiler/src/paint.dart';
import 'package:vector_graphics_compiler/src/svg/node.dart';
import 'package:vector_graphics_compiler/src/svg/opacity_peephole.dart';
import 'package:vector_graphics_compiler/src/svg/parser.dart';
import 'package:vector_graphics_compiler/src/svg/resolver.dart';

import 'helpers.dart';

Future<Node> parseAndResolve(String source) async {
  final Node node = await parseToNodeTree(source);
  final ResolvingVisitor visitor = ResolvingVisitor();
  return node.accept(visitor, AffineMatrix.identity);
}

void main() {
  test('Applies opacity to single child path', () async {
    final Node node = await parseAndResolve('''
<svg viewBox="0 0 200 200">
  <g opacity="0.5">
    <rect x="0" y="0" width="10" height="10" fill="white" />
  </g>
</svg>''');

    final OpacityPeepholeOptimizer visitor = OpacityPeepholeOptimizer();
    final Node newNode = visitor.apply(node);
    final ResolvedPathNode pathNode =
        queryChildren<ResolvedPathNode>(newNode).single;

    expect(pathNode.paint.fill?.color, const Color(0x7fffffff));
  });

  test('Applies opacity and blend mode to single child path', () async {
    final Node node = await parseAndResolve('''
<svg viewBox="0 0 200 200">
  <g opacity="0.5" style="mix-blend-mode:color-burn">
    <rect x="0" y="0" width="10" height="10" fill="white" />
  </g>
</svg>''');

    final OpacityPeepholeOptimizer visitor = OpacityPeepholeOptimizer();
    final Node newNode = visitor.apply(node);
    final ResolvedPathNode pathNode =
        queryChildren<ResolvedPathNode>(newNode).single;

    expect(pathNode.paint.fill?.color, const Color(0x7fffffff));
    expect(pathNode.paint.blendMode, BlendMode.colorBurn);
  });

  test('Applies opacity to non-overlapping child paths', () async {
    final Node node = await parseAndResolve('''
<svg viewBox="0 0 200 200">
  <g opacity="0.5">
    <rect x="0" y="0" width="10" height="10" fill="white" />
    <rect x="30" y="40" width="10" height="10" fill="white" />
  </g>
</svg>''');

    final OpacityPeepholeOptimizer visitor = OpacityPeepholeOptimizer();
    final Node newNode = visitor.apply(node);
    final List<ResolvedPathNode> pathNodes =
        queryChildren<ResolvedPathNode>(newNode);

    expect(pathNodes[0].paint.fill?.color, const Color(0x7fffffff));
    expect(pathNodes[1].paint.fill?.color, const Color(0x7fffffff));
  });

  test(
      'Does not apply opacity and blend mode to single child path with own blend mode',
      () async {
    final Node node = await parseAndResolve('''
<svg viewBox="0 0 200 200">
  <g opacity="0.5" style="mix-blend-mode:color-burn">
    <rect x="0" y="0" width="10" height="10" fill="white" style="mix-blend-mode:darken"/>
  </g>
</svg>''');

    final OpacityPeepholeOptimizer visitor = OpacityPeepholeOptimizer();
    final Node newNode = visitor.apply(node);
    final ResolvedPathNode pathNode =
        queryChildren<ResolvedPathNode>(newNode).single;

    expect(pathNode.paint.fill?.color, const Color(0xffffffff));
    expect(pathNode.paint.blendMode, BlendMode.darken);
  });

  test('Does not apply opacity to overlapping child paths', () async {
    final Node node = await parseAndResolve('''
<svg viewBox="0 0 200 200">
  <g opacity="0.5">
    <rect x="0" y="0" width="10" height="10" fill="white" />
    <rect x="5" y="5" width="10" height="10" fill="white" />
  </g>
</svg>''');

    final OpacityPeepholeOptimizer visitor = OpacityPeepholeOptimizer();
    final Node newNode = visitor.apply(node);
    final List<ResolvedPathNode> pathNodes =
        queryChildren<ResolvedPathNode>(newNode);

    expect(pathNodes[0].paint.fill?.color, const Color(0xffffffff));
    expect(pathNodes[1].paint.fill?.color, const Color(0xffffffff));
  });

  test('Does not apply opacity to text nodes', () async {
    final Node node = await parseAndResolve('''
<svg viewBox="0 0 200 200">
  <g opacity="0.5">
    <text x="0" y="0" fill="white">Hello</text>
  </g>
</svg>''');

    final OpacityPeepholeOptimizer visitor = OpacityPeepholeOptimizer();
    final Node newNode = visitor.apply(node);
    final ResolvedTextNode textNode =
        queryChildren<ResolvedTextNode>(newNode).single;

    expect(textNode.paint.fill?.color, const Color(0xffffffff));
  });

  test('Collapses nested opacity groups multiplicatively', () async {
    final Node node = await parseAndResolve('''
<svg viewBox="0 0 200 200">
  <g opacity="0.5">
    <g opacity="0.3">
      <g opacity="0.2">
        <rect x="0" y="0" width="10" height="10" fill="white" />
      </g>
    </g>
  </g>
</svg>''');

    final OpacityPeepholeOptimizer visitor = OpacityPeepholeOptimizer();
    final Node newNode = visitor.apply(node);
    final ResolvedPathNode textNode =
        queryChildren<ResolvedPathNode>(newNode).single;

    expect(textNode.paint.fill?.color, const Color(0x07ffffff));
  });

  test('Applies opacity to image nodes', () async {
    final Node node = await parseAndResolve('''
<svg viewBox="0 0 200 200">
  <g opacity="0.5">
    <image id="image0" width="50" height="50" xlink:href="data:image/png;base64,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">
  </g>
</svg>''');

    final OpacityPeepholeOptimizer visitor = OpacityPeepholeOptimizer();
    final Node newNode = visitor.apply(node);
    final ResolvedImageNode imageNode =
        queryChildren<ResolvedImageNode>(newNode).single;

    expect(imageNode.opacity, closeTo(0.5, 0.1));
  });
}
