// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'listener.dart';
import 'debug.dart';

/// A render object which draws a vector graphic instance as a raster.
class RenderSimpleVectorGraphic extends RenderBox {
  /// Create a new [RenderSimpleVectorGraphic].
  RenderSimpleVectorGraphic(
    this._pictureInfo,
    this._colorFilter,
    this._opacity,
  ) {
    _opacity?.addListener(_updateOpacity);
    _updateOpacity();
  }

  /// The [PictureInfo] which contains the vector graphic and size to draw.
  SimplePictureInfo get pictureInfo => _pictureInfo;
  SimplePictureInfo _pictureInfo;
  set pictureInfo(SimplePictureInfo value) {
    if (identical(value, _pictureInfo)) {
      return;
    }
    _pictureInfo = value;
    markNeedsPaint();
  }

  /// An optional [ColorFilter] to apply to the rasterized vector graphic.
  ColorFilter? get colorFilter => _colorFilter;
  ColorFilter? _colorFilter;
  set colorFilter(ColorFilter? value) {
    if (colorFilter == value) {
      return;
    }
    _colorFilter = value;
    markNeedsPaint();
  }

  double _opacityValue = 1.0;

  /// An opacity to draw the rasterized vector graphic with.
  Animation<double>? get opacity => _opacity;
  Animation<double>? _opacity;
  set opacity(Animation<double>? value) {
    if (value == opacity) {
      return;
    }
    _opacity?.removeListener(_updateOpacity);
    _opacity = value;
    _opacity?.addListener(_updateOpacity);
    _updateOpacity();
    markNeedsPaint();
  }

  void _updateOpacity() {
    if (opacity == null) {
      return;
    }
    final double newValue = opacity!.value;
    if (newValue == _opacityValue) {
      return;
    }
    _opacityValue = newValue;
    markNeedsPaint();
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    return constraints.smallest;
  }

  @override
  void attach(covariant PipelineOwner owner) {
    _opacity?.addListener(_updateOpacity);
    _updateOpacity();
    super.attach(owner);
  }

  @override
  void detach() {
    _opacity?.removeListener(_updateOpacity);
    super.detach();
  }

  @override
  void dispose() {
    _opacity?.removeListener(_updateOpacity);
    super.dispose();
  }

  final Paint _cachedPaint = ui.Paint();

  @override
  void paint(PaintingContext context, ui.Offset offset) {
    assert(size == pictureInfo.size);
    if (kDebugMode && debugSkipRaster) {
      context.canvas
          .drawRect(offset & size, Paint()..color = const Color(0xFFFF00FF));
      return;
    }

    if (_opacityValue <= 0.0) {
      return;
    }
    pictureInfo.draw(context.canvas, _cachedPaint, _opacityValue, colorFilter);
  }
}
