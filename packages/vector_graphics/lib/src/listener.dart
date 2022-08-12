// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:vector_graphics_codec/vector_graphics_codec.dart';

const VectorGraphicsCodec _codec = VectorGraphicsCodec();

/// The deocded result of a vector graphics asset.
class PictureInfo {
  /// Construct a new [PictureInfo].
  PictureInfo._(this.picture, this.size);

  /// A picture generated from a vector graphics image.
  final ui.Picture picture;

  /// The target size of the picture.
  ///
  /// This information should be used to scale and position
  /// the picture based on the available space and alignment.
  final ui.Size size;
}

/// Internal testing only.
@visibleForTesting
Locale? get debugLastLocale => _debugLastLocale;
Locale? _debugLastLocale;

/// Internal testing only.
@visibleForTesting
TextDirection? get debugLastTextDirection => _debugLastTextDirection;
TextDirection? _debugLastTextDirection;

/// Decode a vector graphics binary asset into a [ui.Picture].
///
/// Throws a [StateError] if the data is invalid.
Future<PictureInfo> decodeVectorGraphics(
  ByteData data, {
  required Locale? locale,
  required TextDirection? textDirection,
}) async {
  assert(() {
    _debugLastTextDirection = textDirection;
    _debugLastLocale = locale;
    return true;
  }());
  final FlutterVectorGraphicsListener listener = FlutterVectorGraphicsListener(
    locale: locale,
    textDirection: textDirection,
  );
  DecodeResponse response = _codec.decode(data, listener);
  if (response.complete) {
    return listener.toPicture();
  }
  await listener.waitForImageDecode();
  response = _codec.decode(data, listener, response: response);
  assert(response.complete);

  return listener.toPicture();
}

/// Pattern configuration to be used when creating ImageShader
class PatternConfig {
  /// Constructs a [PatternConfig].
  PatternConfig(this.patternId, this.width, this.height, this.transform);

  /// The pattern's id.
  final int patternId;

  /// The pattern's width.
  final double width;

  /// The pattern's height.
  final double height;

  /// The pattern's transform.
  final Float64List transform;
}

/// A listener implementation for the vector graphics codec that converts the
/// format into a [ui.Picture].
class FlutterVectorGraphicsListener extends VectorGraphicsCodecListener {
  /// Create a new [FlutterVectorGraphicsListener].
  ///
  /// The [locale] and [textDirection] are used to configure any text created
  /// by the vector_graphic.
  factory FlutterVectorGraphicsListener({
    Locale? locale,
    TextDirection? textDirection,
  }) {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    return FlutterVectorGraphicsListener._(
      canvas,
      recorder,
      locale,
      textDirection,
    );
  }

  FlutterVectorGraphicsListener._(
    this._canvas,
    this._recorder,
    this._locale,
    this._textDirection,
  );

  final Locale? _locale;
  final TextDirection? _textDirection;

  final ui.PictureRecorder _recorder;
  ui.Canvas _canvas;

  final List<ui.Paint> _paints = <ui.Paint>[];
  final List<ui.Path> _paths = <ui.Path>[];
  final List<ui.Shader> _shaders = <ui.Shader>[];
  final List<_TextConfig> _textConfig = <_TextConfig>[];
  final List<Future<ui.Image>> _pendingImages = <Future<ui.Image>>[];
  final Map<int, ui.Image> _images = <int, ui.Image>{};
  final List<Future<ui.ImageShader>> _pendingPatterns =
      <Future<ui.ImageShader>>[];
  final Map<int, ui.ImageShader> _patterns = <int, ui.ImageShader>{};
  final Map<int, ui.Canvas> _patternCanvases = <int, ui.Canvas>{};
  final Map<int, ui.PictureRecorder> _patternRecorders =
      <int, ui.PictureRecorder>{};
  ui.Path? _currentPath;
  ui.Size _size = ui.Size.zero;
  bool _done = false;

  PatternConfig? _currentPattern;

  static final ui.Paint _emptyPaint = ui.Paint();
  static final ui.Paint _grayscaleDstInPaint = ui.Paint()
    ..blendMode = ui.BlendMode.dstIn
    ..colorFilter = const ui.ColorFilter.matrix(<double>[
      0, 0, 0, 0, 0, //
      0, 0, 0, 0, 0,
      0, 0, 0, 0, 0,
      0.2126, 0.7152, 0.0722, 0, 0,
    ]); //convert to grayscale (https://www.w3.org/Graphics/Color/sRGB) and use them as transparency

  /// Convert the vector graphics asset this listener decoded into a [ui.Picture].
  ///
  /// This method can only be called once for a given listener instance.
  PictureInfo toPicture() {
    assert(!_done);
    _done = true;
    try {
      return PictureInfo._(_recorder.endRecording(), _size);
    } finally {
      for (final ui.Image image in _images.values) {
        image.dispose();
      }
      _images.clear();
    }
  }

  /// Wait for all pending images to load.
  Future<void> waitForImageDecode() {
    assert(_pendingImages.isNotEmpty);
    return Future.wait(_pendingImages);
  }

  /// Wait for all pending patterns to load.
  Future<void> waitForPatternDecode() {
    assert(_pendingPatterns.isNotEmpty);
    return Future.wait(_pendingPatterns);
  }

  @override
  void onDrawPath(int pathId, int? paintId, int? patternId) async {
    final ui.Path path = _paths[pathId];
    ui.Paint? paint;
    if (paintId != null) {
      paint = _paints[paintId];
    }
    if (patternId != 65535) {
      if (paintId != null) {
        paint!.shader = _patterns[patternId];
      } else {
        final ui.Paint newPaint = ui.Paint();
        newPaint.shader = _patterns[patternId];
        paint = newPaint;
      }
    }
    if (_currentPattern != null) {
      _patternCanvases[_currentPattern!.patternId]!
          .drawPath(path, paint ?? _emptyPaint);
    } else {
      _canvas.drawPath(path, paint ?? _emptyPaint);
    }
  }

  @override
  void onDrawVertices(Float32List vertices, Uint16List? indices, int? paintId) {
    final ui.Vertices vextexData =
        ui.Vertices.raw(ui.VertexMode.triangles, vertices, indices: indices);
    ui.Paint? paint;
    if (paintId != null) {
      paint = _paints[paintId];
    }
    _canvas.drawVertices(
        vextexData, ui.BlendMode.srcOver, paint ?? _emptyPaint);
  }

  @override
  void onPaintObject({
    required int color,
    required int? strokeCap,
    required int? strokeJoin,
    required int blendMode,
    required double? strokeMiterLimit,
    required double? strokeWidth,
    required int paintStyle,
    required int id,
    required int? shaderId,
  }) {
    assert(_paints.length == id, 'Expect ID to be ${_paints.length}');
    final ui.Paint paint = ui.Paint()..color = ui.Color(color);
    if (blendMode != 0) {
      paint.blendMode = ui.BlendMode.values[blendMode];
    }

    if (shaderId != null) {
      paint.shader = _shaders[shaderId];
    }

    if (paintStyle == 1) {
      paint.style = ui.PaintingStyle.stroke;
      if (strokeCap != null && strokeCap != 0) {
        paint.strokeCap = ui.StrokeCap.values[strokeCap];
      }
      if (strokeJoin != null && strokeJoin != 0) {
        paint.strokeJoin = ui.StrokeJoin.values[strokeJoin];
      }
      if (strokeMiterLimit != null && strokeMiterLimit != 4.0) {
        paint.strokeMiterLimit = strokeMiterLimit;
      }
      // SVG's default stroke width is 1.0. Flutter's default is 0.0.
      if (strokeWidth != null && strokeWidth != 0.0) {
        paint.strokeWidth = strokeWidth;
      }
    }
    _paints.add(paint);
  }

  @override
  void onPathClose() {
    _currentPath!.close();
  }

  @override
  void onPathCubicTo(
      double x1, double y1, double x2, double y2, double x3, double y3) {
    _currentPath!.cubicTo(x1, y1, x2, y2, x3, y3);
  }

  @override
  void onPathFinished() {
    _currentPath = null;
  }

  @override
  void onPathLineTo(double x, double y) {
    _currentPath!.lineTo(x, y);
  }

  @override
  void onPathMoveTo(double x, double y) {
    _currentPath!.moveTo(x, y);
  }

  @override
  void onPathStart(int id, int fillType) {
    assert(_currentPath == null);
    assert(_paths.length == id, 'Expected Id to be $id');

    final ui.Path path = ui.Path();
    path.fillType = ui.PathFillType.values[fillType];
    _paths.add(path);
    _currentPath = path;
  }

  @override
  void onRestoreLayer() {
    if (_currentPattern != null) {
      final int patternId = _currentPattern!.patternId;
      onPatternFinished(_currentPattern, _patternRecorders[patternId],
          _patternCanvases[patternId]!);
    } else {
      _canvas.restore();
    }
  }

  @override
  void onSaveLayer(int paintId) {
    _canvas.saveLayer(null, _paints[paintId]);
  }

  @override
  void onMask() {
    _canvas.saveLayer(null, _grayscaleDstInPaint);
  }

  @override
  void onClipPath(int pathId) {
    _canvas.save();
    _canvas.clipPath(_paths[pathId]);
  }

  @override
  void onPatternStart(int patternId, double x, double y, double width,
      double height, Float64List transform) {
    assert(_currentPattern == null);
    _currentPattern = PatternConfig(patternId, width, height, transform);
    _patternRecorders[patternId] = ui.PictureRecorder();
    final ui.Canvas newCanvas = ui.Canvas(_patternRecorders[patternId]!);
    newCanvas.clipRect(ui.Offset(x, y) & ui.Size(width, height));
    _patternCanvases[patternId] = newCanvas;
  }

  /// Creates ImageShader for active pattern.
  Future<void> onPatternFinished(PatternConfig? currentPattern,
      ui.PictureRecorder? patternRecorder, ui.Canvas canvas) async {
    final FlutterVectorGraphicsListener patternListener =
        FlutterVectorGraphicsListener._(
            canvas, patternRecorder!, _locale, _textDirection);
    double imageWidth = currentPattern!.width;
    double imageHeight = currentPattern.height;

    if (imageWidth < 1) {
      imageWidth = (_size.width * imageWidth);
    }
    if (imageHeight < 1) {
      imageHeight = (_size.width * imageHeight);
    }

    patternListener._size =
        ui.Size(imageWidth.toDouble(), imageHeight.toDouble());

    final PictureInfo pictureInfo = patternListener.toPicture();
    _currentPattern = null;
    final ui.Image image = pictureInfo.picture
        .toImageSync(imageWidth.round(), imageHeight.round());

    final ui.ImageShader pattern = ui.ImageShader(
      image,
      ui.TileMode.repeated,
      ui.TileMode.repeated,
      currentPattern.transform,
    );

    _patterns[currentPattern.patternId] = pattern;
  }

  @override
  void onLinearGradient(
    double fromX,
    double fromY,
    double toX,
    double toY,
    Int32List colors,
    Float32List? offsets,
    int tileMode,
    int id,
  ) {
    assert(_shaders.length == id);

    final ui.Offset from = ui.Offset(fromX, fromY);
    final ui.Offset to = ui.Offset(toX, toY);
    final List<ui.Color> colorValues = <ui.Color>[
      for (int i = 0; i < colors.length; i++) ui.Color(colors[i])
    ];
    final ui.Gradient gradient = ui.Gradient.linear(
      from,
      to,
      colorValues,
      offsets,
      ui.TileMode.values[tileMode],
    );
    _shaders.add(gradient);
  }

  @override
  void onRadialGradient(
    double centerX,
    double centerY,
    double radius,
    double? focalX,
    double? focalY,
    Int32List colors,
    Float32List? offsets,
    Float64List? transform,
    int tileMode,
    int id,
  ) {
    assert(_shaders.length == id);

    final ui.Offset center = ui.Offset(centerX, centerY);
    final ui.Offset? focal = focalX == null ? null : ui.Offset(focalX, focalY!);
    final List<ui.Color> colorValues = <ui.Color>[
      for (int i = 0; i < colors.length; i++) ui.Color(colors[i])
    ];
    final bool hasFocal = focal != center && focal != null;
    final ui.Gradient gradient = ui.Gradient.radial(
      center,
      radius,
      colorValues,
      offsets,
      ui.TileMode.values[tileMode],
      transform,
      hasFocal ? focal : null,
    );
    _shaders.add(gradient);
  }

  @override
  void onSize(double width, double height) {
    _canvas.clipRect(ui.Offset.zero & ui.Size(width, height));
    _size = ui.Size(width, height);
  }

  @override
  void onTextConfig(
    String text,
    String? fontFamily,
    double x,
    double y,
    int fontWeight,
    double fontSize,
    Float64List? transform,
    int id,
  ) {
    _textConfig.add(_TextConfig(
      text,
      fontFamily,
      x,
      y,
      ui.FontWeight.values[fontWeight],
      fontSize,
      transform,
    ));
  }

  @override
  void onDrawText(int textId, int paintId, int? patternId) async {
    final ui.Paint paint = _paints[paintId];
    if (patternId != 65535) {
      paint.shader = _patterns[patternId];
    }
    final _TextConfig textConfig = _textConfig[textId];
    final ui.ParagraphBuilder builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textDirection: _textDirection,
      ),
    );
    builder.pushStyle(ui.TextStyle(
      locale: _locale,
      foreground: paint,
      fontWeight: textConfig.fontWeight,
      fontSize: textConfig.fontSize,
      fontFamily: textConfig.fontFamily,
    ));
    builder.addText(textConfig.text);

    final ui.Paragraph paragraph = builder.build();
    paragraph.layout(const ui.ParagraphConstraints(
      width: double.infinity,
    ));

    if (textConfig.transform != null) {
      _canvas.save();
      _canvas.transform(textConfig.transform!);
    }
    _canvas.drawParagraph(
      paragraph,
      ui.Offset(textConfig.dx, textConfig.dy - paragraph.alphabeticBaseline),
    );
    if (textConfig.transform != null) {
      _canvas.restore();
    }
  }

  @override
  void onImage(int imageId, int format, Uint8List data) {
    assert(format == 0); // Only PNG is supported.
    _pendingImages.add(ui.ImmutableBuffer.fromUint8List(data)
        .then((ui.ImmutableBuffer buffer) async {
      final ui.ImageDescriptor descriptor =
          await ui.ImageDescriptor.encoded(buffer);
      final ui.Codec codec = await descriptor.instantiateCodec();
      final ui.FrameInfo info = await codec.getNextFrame();
      final ui.Image image = info.image;
      buffer.dispose();
      descriptor.dispose();
      codec.dispose();
      _images[imageId] = image;
      return image;
    }));
  }

  @override
  void onDrawImage(int imageId, double x, double y, double width, double height,
      Float64List? transform) {
    final ui.Image image = _images[imageId]!;
    if (transform != null) {
      _canvas.save();
      _canvas.transform(transform);
    }
    paintImage(
      canvas: _canvas,
      rect: ui.Rect.fromLTWH(x, y, width, height),
      image: image,
    );
    if (transform != null) {
      _canvas.restore();
    }
  }
}

class _TextConfig {
  const _TextConfig(
    this.text,
    this.fontFamily,
    this.dx,
    this.dy,
    this.fontWeight,
    this.fontSize,
    this.transform,
  );

  final String text;
  final String? fontFamily;
  final double fontSize;
  final double dx;
  final double dy;
  final ui.FontWeight fontWeight;
  final Float64List? transform;
}
