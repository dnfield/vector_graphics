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
      '''<svg xmlns="http://www.w3.org/2000/svg" width="235" height="64" fill="none"><defs><linearGradient id="paint0_linear" x1="23.84" x2="35.59" y1="31.63" y2="35.91" gradientUnits="userSpaceOnUse"><stop offset=".2" stop-color="#D93025"/><stop offset=".6" stop-color="#EA4335"/></linearGradient><linearGradient id="paint1_linear" x1="6" x2="19.09" y1="33.02" y2="37.78" gradientUnits="userSpaceOnUse"><stop offset=".2" stop-color="#4285F4"/><stop offset=".8" stop-color="#1B74E8"/></linearGradient></defs>  <path fill="#202124" d="M134.72 48.8l3.37-13.15-4.56-4.56 4.56-4.56-3.37-13.16L121.56 10 117 14.56 112.44 10l-13.16 3.37-3.37 13.14 4.56 4.56-4.56 4.58 3.37 13.16 13.16 3.37 4.56-4.56 4.56 4.56 13.16-3.37zm-15.1-3.79l4.35-4.36 5.53 5.53-6.92 1.78-2.97-2.95zm-6.98-20.89l4.36-4.35 4.36 4.35-4.36 4.36-4.36-4.36zm1.75 6.97l-4.36 4.36-4.36-4.36 4.36-4.36 4.36 4.36zm9.56-4.36l4.36 4.36-4.36 4.36-4.36-4.36 4.36-4.36zm-2.6 11.31L117 42.4l-4.36-4.36 4.36-4.36 4.36 4.36zm-9.91 9.92l-6.92-1.78 5.53-5.53 4.36 4.36-2.97 2.95zm-8.36-14.26l4.36 4.36-5.53 5.53-1.78-6.92 2.95-2.97zm-1.19-15.1l5.53 5.52-4.36 4.36-2.96-2.97 1.8-6.91zm12.5-1.43l-4.36 4.36L104.5 16l6.92-1.78 2.97 2.95zm8.17-2.97l6.92 1.78-5.53 5.53-4.36-4.36 2.97-2.95zm8.36 14.28l-4.36-4.36 5.53-5.52 1.78 6.91-2.95 2.97zm1.19 15.09l-5.53-5.53 4.36-4.36 2.96 2.97-1.8 6.92z"/>  <path fill="#1A73E8" d="M66.17 29.98a.88.88 0 00-1.25-1.24l-4.61 4.61c-.1.1-.1.26 0 .35l4.61 4.62a.88.88 0 001.25-1.25l-2.66-2.66h8.86a.88.88 0 000-1.77H63.5l2.66-2.66z"/>  <mask id="a" width="14" height="11" x="60" y="28" maskUnits="userSpaceOnUse">    <path fill="#fff" d="M66.17 29.98a.88.88 0 00-1.25-1.24l-4.61 4.61c-.1.1-.1.26 0 .35l4.61 4.62a.88.88 0 001.25-1.25l-2.66-2.66h8.86a.88.88 0 000-1.77H63.5l2.66-2.66z"/></mask>  <g mask="url(#a)"><path fill="#5F6368" d="M79 21.73H55v24h24z"/></g>  <path fill="#1A73E8" d="M167.17 29.98a.88.88 0 10-1.25-1.24l-4.61 4.61c-.1.1-.1.26 0 .35l4.61 4.62a.88.88 0 001.25-1.25l-2.66-2.66h8.86a.88.88 0 100-1.77h-8.86l2.66-2.66z"/>  <mask id="b" width="14" height="11" x="161" y="28" maskUnits="userSpaceOnUse">    <path fill="#fff" d="M167.17 29.98a.88.88 0 10-1.25-1.24l-4.61 4.61c-.1.1-.1.26 0 .35l4.61 4.62a.88.88 0 001.25-1.25l-2.66-2.66h8.86a.88.88 0 100-1.77h-8.86l2.66-2.66z"/></mask>  <g mask="url(#b)"><path fill="#5F6368" d="M180 21.73h-24v24h24z"/></g>  <path fill="url(#paint0_linear)" d="M21.86 37.19l7.92-13.73 4.3 2.5a5.82 5.82 0 012.14 7.95l-4.46 7.73a3.64 3.64 0 01-4.97 1.33l-4-2.31a2.54 2.54 0 01-.93-3.47z"/>  <path fill="#FDBD00" d="M21.02 27.66l-9.85 17.07 4.3 2.49a5.82 5.82 0 007.96-2.14l6.4-11.07c1-1.74.4-3.96-1.34-4.97l-4-2.3a2.54 2.54 0 00-3.47.92z"/>  <path fill="#2DA94F" d="M29.78 23.47l-3.05-1.77a7.28 7.28 0 00-9.95 2.67l-5.66 9.8c-1 1.75-.4 3.97 1.34 4.98l3.05 1.76c1.74 1 3.96.41 4.97-1.33l6.76-11.71A5.08 5.08 0 0134.18 26"/>  <path fill="url(#paint1_linear)" d="M17.66 27.24L14.3 25.3a3.14 3.14 0 00-4.3 1.15l-4.03 6.99a7.18 7.18 0 002.63 9.82l2.57 1.48 3.1 1.79 1.36.77a5.52 5.52 0 01-1.7-7.35l1.05-1.8 3.83-6.63c.87-1.5.35-3.41-1.15-4.28z"/>  <path fill="#1A73E8" fill-rule="evenodd" d="M200.67 25.73l12.66-6.67L226 25.73v2.66h-25.33v-2.66zm12.66-3.66l6.95 3.66h-13.9l6.95-3.66zm-10 9h4v9.32h-4v-9.33zm12 0v9.32h-4v-9.33h4zm-14.66 12v2.66H226v-2.67h-25.33zm18.66-12h4v9.32h-4v-9.33z" clip-rule="evenodd"/></svg>
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
