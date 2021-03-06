// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:test/test.dart';
import 'package:vector_graphics_compiler/src/svg/node.dart';
import 'package:vector_graphics_compiler/src/svg/parser.dart';
import 'package:vector_graphics_compiler/src/svg/resolver.dart';
import 'package:vector_graphics_compiler/src/svg/tessellator.dart';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart';

import 'helpers.dart';

void main() {
  setUpAll(() {
    if (!initializeTessellatorFromFlutterCache()) {
      fail('error in setup');
    }
  });

  test('Can convert simple shape to indexed vertices', () async {
    final Node node = await parseToNodeTree('''
<svg viewBox="0 0 200 200">
  <rect x="0" y="0" width="10" height="10" fill="white" />
</svg>''');
    Node resolvedNode = node.accept(ResolvingVisitor(), AffineMatrix.identity);
    resolvedNode = resolvedNode.accept(Tessellator(), null);

    final ResolvedVerticesNode verticesNode =
        queryChildren<ResolvedVerticesNode>(resolvedNode).single;

    expect(verticesNode.bounds, const Rect.fromLTWH(0, 0, 10, 10));
    expect(verticesNode.vertices.vertices, <double>[
      0.0,
      10.0,
      10.0,
      0.0,
      10.0,
      10.0,
      10.0,
      0.0,
      0.0,
      10.0,
      0.0,
      0.0
    ]);
    expect(verticesNode.vertices.indices, null);
  });

  test('Can convert complex path to indexed vertices', () async {
    final Node node = await parseToNodeTree('''
<svg viewBox="0 0 200 200">
  <path id="path120" d="m-54.2,176.4s11.2,7.2-3.2,38.4l6.4-2.4s-0.8,11.2-4,13.6l7.2-3.2s4.8,8,0.8,12.8c0,0,16.8,8,16,14.4,0,0,6.4-8,2.4-14.4s-11.2-2.4-10.4-20.8l-8.8,3.2s5.6-8.8,5.6-15.2l-8,2.4s15.469-26.58,4.8-28c-6-0.8-8.8-0.8-8.8-0.8z"/>
</svg>''');
    Node resolvedNode = node.accept(ResolvingVisitor(), AffineMatrix.identity);
    resolvedNode = resolvedNode.accept(Tessellator(), null);

    final ResolvedVerticesNode verticesNode =
        queryChildren<ResolvedVerticesNode>(resolvedNode).single;

    expect(
        verticesNode.bounds,
        const Rect.fromLTRB(-57.400000000000006, 176.4, -24.60000000000001,
            250.00000000000003));
    expect(verticesNode.vertices.vertices, <double>[
      -42.135414123535156,
      179.4943389892578,
      -41.73436737060547,
      184.28823852539062,
      -41.69853973388672,
      181.1885986328125,
      -42.890689849853516,
      189.16851806640625,
      -43.03253173828125,
      178.2003173828125,
      -44.450836181640625,
      177.38226318359375,
      -45.400001525878906,
      177.1999969482422,
      -45.86604309082031,
      196.82717895507812,
      -49.716590881347656,
      204.369384765625,
      -50.08125305175781,
      186.15936279296875,
      -50.83125305175781,
      181.88436889648438,
      -52.040626525878906,
      178.97341918945312,
      -52.80000305175781,
      176.39999389648438,
      -53.849998474121094,
      176.625,
      -54.20000076293945,
      176.39999389648438,
      -50.20000076293945,
      205.1999969482422,
      -50.22187805175781,
      191.99533081054688,
      -42.20000076293945,
      202.8000030517578,
      -43.94999694824219,
      210.45001220703125,
      -42.375,
      205.27499389648438,
      -47.099998474121094,
      216.89999389648438,
      -47.79999923706055,
      218.0,
      -47.79999923706055,
      222.8000030517578,
      -51.0,
      212.39999389648438,
      -51.099998474121094,
      213.79998779296875,
      -52.30000305175781,
      220.66250610351562,
      -53.43437957763672,
      223.87342834472656,
      -54.41874694824219,
      225.4812469482422,
      -55.0,
      226.0,
      -39.0,
      214.8000030517578,
      -44.900001525878906,
      236.60000610351562,
      -39.087501525878906,
      218.07501220703125,
      -45.4375,
      229.42498779296875,
      -47.19999694824219,
      223.8000030517578,
      -27.307811737060547,
      239.30625915527344,
      -27.903125762939453,
      244.125,
      -27.364063262939453,
      241.78125,
      -27.931251525878906,
      236.8125,
      -28.600000381469727,
      235.60000610351562,
      -29.374998092651367,
      234.48126220703125,
      -30.200000762939453,
      249.0,
      -30.987499237060547,
      248.78750610351562,
      -31.109375,
      232.86404418945312,
      -32.13593673706055,
      246.2937469482422,
      -33.875,
      231.08749389648438,
      -34.329689025878906,
      243.81875610351562,
      -36.40625,
      228.86561584472656,
      -37.165618896484375,
      241.47500610351562,
      -37.765625,
      226.53594970703125,
      -38.703125,
      223.06719970703125,
      -31.0,
      250.0,
      -45.564064025878906,
      232.640625,
      -46.318748474121094,
      234.6750030517578,
      -47.0,
      235.60000610351562,
      -51.68437957763672,
      199.58908081054688,
      -54.900001525878906,
      209.1374969482422,
      -57.400001525878906,
      214.8000030517578,
    ]);
    expect(verticesNode.vertices.indices, <int>[
      0,
      1,
      2,
      0,
      3,
      1,
      4,
      3,
      0,
      5,
      3,
      4,
      6,
      3,
      5,
      6,
      7,
      3,
      6,
      8,
      7,
      6,
      9,
      8,
      6,
      10,
      9,
      6,
      11,
      10,
      12,
      11,
      6,
      12,
      13,
      11,
      13,
      12,
      14,
      9,
      15,
      8,
      15,
      9,
      16,
      17,
      18,
      19,
      17,
      20,
      18,
      17,
      21,
      20,
      15,
      21,
      17,
      15,
      22,
      21,
      23,
      15,
      16,
      23,
      22,
      15,
      24,
      22,
      23,
      25,
      22,
      24,
      26,
      22,
      25,
      27,
      22,
      26,
      22,
      27,
      28,
      29,
      30,
      31,
      29,
      32,
      30,
      29,
      33,
      32,
      21,
      33,
      29,
      33,
      21,
      22,
      34,
      35,
      36,
      37,
      35,
      34,
      38,
      35,
      37,
      39,
      35,
      38,
      39,
      40,
      35,
      39,
      41,
      40,
      42,
      41,
      39,
      42,
      43,
      41,
      44,
      43,
      42,
      44,
      45,
      43,
      46,
      45,
      44,
      46,
      47,
      45,
      48,
      47,
      46,
      49,
      47,
      48,
      49,
      30,
      47,
      30,
      49,
      31,
      40,
      41,
      50,
      51,
      30,
      32,
      52,
      30,
      51,
      30,
      52,
      53,
      54,
      23,
      16,
      55,
      23,
      54,
      23,
      55,
      56,
    ]);
  });
}
