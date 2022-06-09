// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import 'listener.dart';
import 'debug.dart';

@immutable
class _RasterKey {
  const _RasterKey(this.info, this.width, this.height);

  // While picture info doesn't implement equality, the caching at the vector graphic
  // state object level ensures multiple widgets that request the same bytes will get
  // the same picture instance. Thus we rely on identical picture infos being equal.
  final PictureInfo info;
  final int width;
  final int height;

  @override
  bool operator ==(Object other) {
    return other is _RasterKey &&
        other.info == info &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode => Object.hash(info, width, height);
}

class _RasterData {
  _RasterData(this.image, this.count, this.key);

  final ui.Image image;
  final _RasterKey key;
  int count = 0;
}

/// For testing only, clear all pending rasters.
@visibleForTesting
void debugClearRasteCaches() {
  if (!kDebugMode) {
    return;
  }
  RenderVectorGraphic._liveRasterCache.clear();
  RenderVectorGraphic._pendingRasterCache.clear();
}

/// A render object which draws a vector graphic instance as a raster.
class RenderVectorGraphic extends RenderBox {
  /// Create a new [RenderVectorGraphic].
  RenderVectorGraphic(
    this._pictureInfo,
    this._colorFilter,
    this._devicePixelRatio,
    this._opacity,
    this._scale,
  ) {
    _opacity?.addListener(_updateOpacity);
    _updateOpacity();
  }

  static final Map<_RasterKey, _RasterData> _liveRasterCache =
      <_RasterKey, _RasterData>{};
  static final Map<_RasterKey, Future<_RasterData>> _pendingRasterCache =
      <_RasterKey, Future<_RasterData>>{};

  /// The [PictureInfo] which contains the vector graphic and size to draw.
  PictureInfo get pictureInfo => _pictureInfo;
  PictureInfo _pictureInfo;
  set pictureInfo(PictureInfo value) {
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

  /// The device pixel ratio the vector graphic should be rasterized at.
  double get devicePixelRatio => _devicePixelRatio;
  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == devicePixelRatio) {
      return;
    }
    _devicePixelRatio = value;
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

  /// An additional ratio the picture will be transformed by.
  ///
  /// This value is used to ensure the computed raster does not
  /// have extra pixelation from scaling in the case that a the [BoxFit]
  /// value used in the [VectorGraphic] widget implies a scaling factor
  /// greater than 1.0.
  ///
  /// For example, if the vector graphic widget is sized at 100x100,
  /// the vector graphic itself has a size of 50x50, and [BoxFit.fill]
  /// is used. This will compute a scale of 2.0, which will result in a
  /// raster that is 100x100.
  double get scale => _scale;
  double _scale;
  set scale(double value) {
    assert(value != 0);
    if (value == scale) {
      return;
    }
    _scale = value;
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

  /// Visible for testing only.
  @visibleForTesting
  Future<void>? get pendingRasterUpdate {
    if (kReleaseMode) {
      return null;
    }
    return _pendingRasterUpdate;
  }

  Future<void>? _pendingRasterUpdate;
  bool _disposed = false;

  static Future<_RasterData> _createRaster(_RasterKey key, double scaleFactor) {
    if (_pendingRasterCache.containsKey(key)) {
      return _pendingRasterCache[key]!;
    }

    final PictureInfo info = key.info;
    final int scaledWidth = key.width;
    final int scaledHeight = key.height;
    // In order to scale a picture, it must be placed in a new picture
    // with a transform applied. Surprisingly, the height and width
    // arguments of Picture.toImage do not control the resolution that the
    // picture is rendered at, instead it controls how much of the picture to
    // capture in a raster.
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);

    canvas.scale(scaleFactor);
    canvas.drawPicture(info.picture);
    final ui.Picture rasterPicture = recorder.endRecording();

    final Future<_RasterData> pending =
        rasterPicture.toImage(scaledWidth, scaledHeight).then((ui.Image image) {
      return _RasterData(image, 0, key);
    });
    _pendingRasterCache[key] = pending;
    pending.whenComplete(() {
      _pendingRasterCache.remove(key);
    });
    return pending;
  }

  void _maybeReleaseRaster(_RasterData? data) {
    if (data == null) {
      return;
    }
    data.count -= 1;
    if (data.count <= 0) {
      _liveRasterCache.remove(data.key);
      data.image.dispose();
    }
  }

  // Re-create the raster for a given vector graphic if the target size
  // is sufficiently different. Returns `null` if rasterData has been
  // updated immediately.
  Future<void>? _maybeUpdateRaster() {
    final int scaledWidth =
        (pictureInfo.size.width * devicePixelRatio / scale).round();
    final int scaledHeight =
        (pictureInfo.size.height * devicePixelRatio / scale).round();
    final _RasterKey key = _RasterKey(_pictureInfo, scaledWidth, scaledHeight);

    // First check if the raster is available synchronously. This also handles
    // a no-op change that would resolve to an identical picture.
    if (_liveRasterCache.containsKey(key)) {
      final _RasterData data = _liveRasterCache[key]!;
      if (data != _rasterData) {
        _maybeReleaseRaster(_rasterData);
        data.count += 1;
      }
      _rasterData = data;
      return null; // immediate update.
    }
    return _createRaster(key, devicePixelRatio / scale)
        .then((_RasterData data) {
      data.count += 1;
      // Ensure this is only added to the live cache once.
      if (data.count == 1) {
        _liveRasterCache[key] = data;
      }
      if (_disposed) {
        _maybeReleaseRaster(data);
        return;
      }
      _maybeReleaseRaster(_rasterData);
      _rasterData = data;
      markNeedsPaint();
    });
  }

  _RasterData? _rasterData;

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
    _disposed = true;
    _maybeReleaseRaster(_rasterData);
    _opacity?.removeListener(_updateOpacity);
    super.dispose();
  }

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

    _pendingRasterUpdate = _maybeUpdateRaster();
    final ui.Image? image = _rasterData?.image;
    final int? width = _rasterData?.key.width;
    final int? height = _rasterData?.key.height;

    if (image == null || width == null || height == null) {
      return;
    }

    // Use `FilterQuality.low` to scale the image, which corresponds to
    // bilinear interpolation.
    final Paint colorPaint = Paint()..filterQuality = ui.FilterQuality.low;
    if (colorFilter != null) {
      colorPaint.colorFilter = colorFilter!;
    }
    colorPaint.color = Color.fromRGBO(0, 0, 0, _opacityValue);
    final Rect src = ui.Rect.fromLTWH(
      0,
      0,
      width.toDouble(),
      height.toDouble(),
    );
    final Rect dst = ui.Rect.fromLTWH(
      offset.dx,
      offset.dy,
      pictureInfo.size.width,
      pictureInfo.size.height,
    );
    context.canvas.drawImageRect(
      image,
      src,
      dst,
      colorPaint,
    );
  }
}
