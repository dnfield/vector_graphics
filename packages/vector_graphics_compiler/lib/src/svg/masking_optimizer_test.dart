//import 'dart:html';
import 'dart:ui';

import 'dart:typed_data';

import 'package:vector_graphics_compiler/src/svg/node.dart';
import 'package:vector_graphics_compiler/src/svg/masking_optimizer.dart';
import 'package:vector_graphics_compiler/src/svg/resolver.dart';
import 'dart:core';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart';
import 'package:vector_graphics/src/listener.dart';
import 'dart:convert';
import 'dart:ui' show ImageByteFormat;
import 'package:flutter/material.dart';

import 'package:vector_graphics_codec/vector_graphics_codec.dart';

// DO NOT CHECK THIS IN

int queryMaskChildren(Node node) {
  if (node.runtimeType.toString() == 'ResolvedPathNode') {
    return 1;
  } else if (node.runtimeType.toString() == 'ParentNode') {
    ParentNode parentNode = node as ParentNode;
    int count = 1;
    for (Node child in parentNode.children) {
      count += queryMaskChildren(child);
    }
    return count;
  } else {
    ResolvedMaskNode maskNode = node as ResolvedMaskNode;
    int count = 1;
    count += queryMaskChildren(maskNode.mask);

    return count;
  }
}

/*
int queryAllChildren(Node node) {
  if (node.runtimeType.toString() == 'ViewportNode') {
    int count = 1;
    for (Node child in (node as ViewportNode).children) {
      count += queryAllChildren(child);
    }
    return count;
  } else if (node.runtimeType.toString() == 'ResolvedMaskNode') {
    int count = 1;
    ResolvedMaskNode maskNode = node as ResolvedMaskNode;
    count += queryMaskChildren(maskNode.mask);
    count += queryMaskChildren(maskNode.child);
    return count;
  } else if (node.runtimeType.toString() == 'ResolvedClipNode') {
    int count = 1;
    ResolvedClipNode clipNode = node as ResolvedClipNode;
    count += queryAllChildren(clipNode.child);
    return count;
  } else if (node.runtimeType.toString() == 'SaveLayerNode') {
    int count = 1;
    SaveLayerNode layerNode = node as SaveLayerNode;
    for (Node child in layerNode.children) {
      count += queryAllChildren(child);
    }
    return count;
  } else if (node.runtimeType.toString() == 'ParentNode') {
    int count = 1;
    ParentNode parentNode = node as ParentNode;
    for (Node child in parentNode.children) {
      count += queryAllChildren(child);
    }
    return count;
  } else {
    return 1;
  }
}
*/

void main() async {
  const String svgString =
      '''<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="48" height="48" viewBox="0 0 48 48"><defs><path d="M43 8H5c-1.65 0-3 1.35-3 3v26c0 1.65 1.35 3 3 3h38c1.65 0 3-1.35 3-3V11c0-1.65-1.35-3-3-3z" id="a"/><path d="M43 8H5c-1.65 0-3 1.35-3 3v26c0 1.65 1.35 3 3 3h38c1.65 0 3-1.35 3-3V11c0-1.65-1.35-3-3-3z" id="c"/><path d="M43 8H5c-1.65 0-3 1.35-3 3v26c0 1.65 1.35 3 3 3h38c1.65 0 3-1.35 3-3V11c0-1.65-1.35-3-3-3z" id="e"/><path d="M43 8H5c-1.65 0-3 1.35-3 3v26c0 1.65 1.35 3 3 3h38c1.65 0 3-1.35 3-3V11c0-1.65-1.35-3-3-3z" id="g"/><path d="M43 8H5c-1.65 0-3 1.35-3 3v26c0 1.65 1.35 3 3 3h38c1.65 0 3-1.35 3-3V11c0-1.65-1.35-3-3-3z" id="i"/><path d="M43 8H5c-1.65 0-3 1.35-3 3v26c0 1.65 1.35 3 3 3h38c1.65 0 3-1.35 3-3V11c0-1.65-1.35-3-3-3z" id="k"/><path d="M43 8H5c-1.65 0-3 1.35-3 3v26c0 1.65 1.35 3 3 3h38c1.65 0 3-1.35 3-3V11c0-1.65-1.35-3-3-3z" id="n"/><path d="M43 8H5c-1.65 0-3 1.35-3 3v26c0 1.65 1.35 3 3 3h38c1.65 0 3-1.35 3-3V11c0-1.65-1.35-3-3-3z" id="p"/><path d="M43 8H5c-1.65 0-3 1.35-3 3v26c0 1.65 1.35 3 3 3h38c1.65 0 3-1.35 3-3V11c0-1.65-1.35-3-3-3z" id="r"/><path d="M43 8H5c-1.65 0-3 1.35-3 3v26c0 1.65 1.35 3 3 3h38c1.65 0 3-1.35 3-3V11c0-1.65-1.35-3-3-3z" id="t"/><path d="M43 8H5c-1.65 0-3 1.35-3 3v26c0 1.65 1.35 3 3 3h38c1.65 0 3-1.35 3-3V11c0-1.65-1.35-3-3-3z" id="v"/><path d="M43 8H5c-1.65 0-3 1.35-3 3v26c0 1.65 1.35 3 3 3h38c1.65 0 3-1.35 3-3V11c0-1.65-1.35-3-3-3z" id="x"/><path d="M43 8H5c-1.65 0-3 1.35-3 3v26c0 1.65 1.35 3 3 3h38c1.65 0 3-1.35 3-3V11c0-1.65-1.35-3-3-3z" id="z"/><radialGradient cx="2.245%" cy="2.331%" fx="2.245%" fy="2.331%" r="162.394%" gradientTransform="matrix(.72727 0 0 1 .006 0)" id="B"><stop stop-color="#FFF" stop-opacity=".1" offset="0%"/><stop stop-color="#FFF" stop-opacity="0" offset="100%"/></radialGradient><linearGradient x1="27.717%" y1="14.053%" x2="88.49%" y2="54.926%" id="l"><stop stop-color="#262626" stop-opacity=".2" offset="0%"/><stop stop-color="#262626" stop-opacity=".02" offset="100%"/></linearGradient></defs><g fill="none"><mask id="b" fill="#fff"><use xlink:href="#a"/></mask><path fill="#E1E1E1" mask="url(#b)" d="M7 15.25h34V40H7z"/><mask id="d" fill="#fff"><use xlink:href="#c"/></mask><path fill="#EEE" mask="url(#d)" d="M24 27.635L7 40h34V15.25z"/><mask id="f" fill="#fff"><use xlink:href="#e"/></mask><path fill-opacity=".4" fill="#FFF" mask="url(#f)" d="M24 27.635L7 40h.345L24 27.885 41 15.5v-.25z"/><mask id="h" fill="#fff"><use xlink:href="#g"/></mask><path fill="#D23F31" mask="url(#h)" d="M2 11h5v29H2z"/><mask id="j" fill="#fff"><use xlink:href="#i"/></mask><path fill="#C53929" mask="url(#j)" d="M41 11h5v29h-5z"/><mask id="m" fill="#fff"><use xlink:href="#k"/></mask><path fill="url(#l)" mask="url(#m)" d="M2.88 13.12L29.758 40H46V11z"/><mask id="o" fill="#fff"><use xlink:href="#n"/></mask><path d="M43 8L24 21 5 8H2v3c0 1.027.518 1.935 1.305 2.475L24 27.635l20.695-14.16A2.997 2.997 0 0046 11V8h-3z" fill="#DB4437" mask="url(#o)"/><mask id="q" fill="#fff"><use xlink:href="#p"/></mask><path d="M43 39.75H5c-1.65 0-3-1.35-3-3V37c0 1.65 1.35 3 3 3h38c1.65 0 3-1.35 3-3v-.25c0 1.65-1.35 3-3 3z" fill-opacity=".2" fill="#262626" mask="url(#q)"/><mask id="s" fill="#fff"><use xlink:href="#r"/></mask><path d="M43 8l-.365.25H43c1.65 0 3 1.35 3 3V11c0-1.65-1.35-3-3-3z" fill-opacity=".2" fill="#FFF" mask="url(#s)"/><mask id="u" fill="#fff"><use xlink:href="#t"/></mask><path d="M5 8l.365.25H5c-1.65 0-3 1.35-3 3V11c0-1.65 1.35-3 3-3z" fill-opacity=".2" fill="#FFF" mask="url(#u)"/><mask id="w" fill="#fff"><use xlink:href="#v"/></mask><path d="M44.695 13.225L24 27.385 3.305 13.225A2.997 2.997 0 012 10.75V11c0 1.027.518 1.935 1.305 2.475L24 27.635l20.695-14.16A2.997 2.997 0 0046 11v-.25a2.997 2.997 0 01-1.305 2.475z" fill-opacity=".25" fill="#3E2723" mask="url(#w)"/><mask id="y" fill="#fff"><use xlink:href="#x"/></mask><path fill="#F1F1F1" mask="url(#y)" d="M5 8l19 13L43 8z"/><mask id="A" fill="#fff"><use xlink:href="#z"/></mask><path fill-opacity=".02" fill="#262626" mask="url(#A)" d="M5 8l.365.25h37.27L43 8z"/><path d="M43 8H5c-1.65 0-3 1.35-3 3v26c0 1.65 1.35 3 3 3h38c1.65 0 3-1.35 3-3V11c0-1.65-1.35-3-3-3z" fill="url(#B)" mask="url(#A)"/><path mask="url(#A)" d="M0 0h48v48H0z"/></g></svg>
      ''';

  final Node root = await parseAndResolve(svgString);

  final List<ResolvedPathNode> pathNodesOld =
      queryChildren<ResolvedPathNode>(root);
  final List<ResolvedMaskNode> maskNodesOld =
      queryChildren<ResolvedMaskNode>(root);
  final List<ParentNode> parentNodesOld = queryChildren<ParentNode>(root);

  int recursiveMaskNodeCountOld = 0;

  for (ResolvedMaskNode maskNode in maskNodesOld) {
    recursiveMaskNodeCountOld += queryMaskChildren(maskNode);
  }

  int oldTotal =
      pathNodesOld.length + parentNodesOld.length + recursiveMaskNodeCountOld;

  //int oldTotal = queryAllChildren(root);

  final MaskingOptimizer visitor = MaskingOptimizer();
  final Node newNode = visitor.apply(root);

  //int newTotal = queryAllChildren(newNode);

  final List<ResolvedPathNode> pathNodesNew =
      queryChildren<ResolvedPathNode>(newNode);
  final List<ResolvedMaskNode> maskNodesNew =
      queryChildren<ResolvedMaskNode>(newNode);
  final List<ParentNode> parentNodesNew = queryChildren<ParentNode>(newNode);

  int recursiveMaskNodeCountNew = 0;

  for (ResolvedMaskNode maskNode in maskNodesNew) {
    recursiveMaskNodeCountNew += queryMaskChildren(maskNode);
  }

  int newTotal =
      pathNodesNew.length + parentNodesNew.length + recursiveMaskNodeCountNew;

  int nodeReduction = (oldTotal) - (newTotal);

  /*
  print("OLD - path: " +
      pathNodesOld.length.toString() +
      ", mask: " +
      maskNodesOld.length.toString() +
      ", parent: " +
      parentNodesOld.length.toString());
  print("NEW - path: " +
      pathNodesNew.length.toString() +
      ", mask: " +
      maskNodesNew.length.toString() +
      ", parent: " +
      parentNodesNew.length.toString());
    */

  final Uint8List data = await encodeSvg(svgString, 'test_file_name');

  final FlutterVectorGraphicsListener listener =
      FlutterVectorGraphicsListener();
  const VectorGraphicsCodec codec = VectorGraphicsCodec();
  codec.decode(data.buffer.asByteData(), listener);

  ViewportNode viewportNode = root as ViewportNode;

  final image = (await listener
      .toPicture()
      .picture
      .toImage(viewportNode.width.round(), viewportNode.height.round()));

  final ByteData? imageBytes =
      await image.toByteData(format: ImageByteFormat.png);
  print(
      'data:image/png;base64,${base64Encode(imageBytes!.buffer.asUint8List())}');
  print('There was a ' + nodeReduction.toString() + ' node reduction.');
}
