import 'dart:collection';

import 'package:xml/xml_events.dart';

import '../draw_command_builder.dart';
import '../geometry/basic_types.dart';
import '../geometry/matrix.dart';
import '../geometry/path.dart';
import '../paint.dart';
import '../vector_instructions.dart';
import 'colors.dart';
import 'node.dart';
import 'numbers.dart' hide parseDoubleWithUnits;
import 'numbers.dart' as numbers show parseDoubleWithUnits;
import 'parsers.dart';
import 'theme.dart';

final Set<String> _unhandledElements = <String>{'title', 'desc'};

typedef _ParseFunc = Future<void>? Function(
    SvgParser parserState, bool warningsAsErrors);
typedef _PathFunc = Path? Function(SvgParser parserState);

const Map<String, _ParseFunc> _svgElementParsers = <String, _ParseFunc>{
  'svg': _Elements.svg,
  'g': _Elements.g,
  'a': _Elements.g, // treat as group
  'use': _Elements.use,
  'symbol': _Elements.symbol,
  'mask': _Elements.symbol, // treat as symbol
  'radialGradient': _Elements.radialGradient,
  'linearGradient': _Elements.linearGradient,
  'clipPath': _Elements.clipPath,
  'image': _Elements.image,
  'text': _Elements.text,
};

const Map<String, _PathFunc> _svgPathFuncs = <String, _PathFunc>{
  'circle': _Paths.circle,
  'path': _Paths.path,
  'rect': _Paths.rect,
  'polygon': _Paths.polygon,
  'polyline': _Paths.polyline,
  'ellipse': _Paths.ellipse,
  'line': _Paths.line,
};

// ignore: avoid_classes_with_only_static_members
class _Elements {
  static Future<void>? svg(SvgParser parserState, bool warningsAsErrors) {
    final _Viewport viewBox = parserState._parseViewBox();

    // TODO(dnfield): Support nested SVG elements. https://github.com/dnfield/flutter_svg/issues/132
    if (parserState._root != null) {
      const String errorMessage = 'Unsupported nested <svg> element.';
      if (warningsAsErrors) {
        throw UnsupportedError(errorMessage);
      }

      parserState._parentDrawables.addLast(
        _SvgGroupTuple(
          'svg',
          ViewportNode(
            parserState._currentAttributes,
            width: viewBox.width,
            height: viewBox.height,
            transform: viewBox.transform,
          ),
        ),
      );
      return null;
    }
    parserState._root = ViewportNode(
      parserState._currentAttributes,
      width: viewBox.width,
      height: viewBox.height,
      transform: viewBox.transform,
    );
    parserState.addGroup(parserState._currentStartElement!, parserState._root!);
    return null;
  }

  static Future<void>? g(SvgParser parserState, bool warningsAsErrors) {
    if (parserState._currentStartElement?.isSelfClosing == true) {
      return null;
    }
    final ParentNode parent = parserState.currentGroup!;

    final ParentNode group = ParentNode(parserState._currentAttributes);
    parent.addChild(
      group,
      clipId: parserState._currentAttributes.clipPathId,
      clipServer: parserState._definitions.getClipPath,
      maskId: parserState.attribute('mask'),
      maskServer: parserState._definitions.getDrawable,
    );
    parserState.addGroup(parserState._currentStartElement!, group);
    return null;
  }

  static Future<void>? symbol(SvgParser parserState, bool warningsAsErrors) {
    final ParentNode group = ParentNode(parserState._currentAttributes);
    parserState.addGroup(parserState._currentStartElement!, group);
    return null;
  }

  static Future<void>? use(SvgParser parserState, bool warningsAsErrors) {
    final ParentNode? parent = parserState.currentGroup;
    final String xlinkHref = parserState._currentAttributes.href!;
    if (xlinkHref.isEmpty) {
      return null;
    }

    final AffineMatrix transform =
        (parseTransform(parserState.attribute('transform')) ??
                AffineMatrix.identity)
            .translated(
      parserState.parseDoubleWithUnits(
        parserState.attribute('x', def: '0'),
      )!,
      parserState.parseDoubleWithUnits(
        parserState.attribute('y', def: '0'),
      )!,
    );

    final AttributedNode ref =
        parserState._definitions.getDrawable('url($xlinkHref)');
    final ParentNode group = ParentNode(
      parserState._currentAttributes,
      precalculatedTransform: transform,
    );

    group.addChild(ref.applyAttributes(parserState._currentAttributes));
    parserState.checkForIri(group);
    parent!.addChild(
      group,
      clipId: parserState._currentAttributes.clipPathId,
      clipServer: parserState._definitions.getClipPath,
      maskId: parserState.attribute('mask'),
      maskServer: parserState._definitions.getDrawable,
    );
    return null;
  }

  static Future<void>? parseStops(
    SvgParser parserState,
    List<Color> colors,
    List<double> offsets,
  ) {
    for (XmlEvent event in parserState._readSubtree()) {
      if (event is XmlEndElementEvent) {
        continue;
      }
      if (event is XmlStartElementEvent) {
        final String rawOpacity = parserState.attribute(
          'stop-opacity',
          def: '1',
        )!;
        final Color stopColor =
            parserState.parseColor(parserState.attribute('stop-color')) ??
                Color.opaqueBlack;
        colors.add(stopColor.withOpacity(parseDouble(rawOpacity)!));

        final String rawOffset = parserState.attribute(
          'offset',
          def: '0%',
        )!;
        offsets.add(parseDecimalOrPercentage(rawOffset));
      }
    }
    return null;
  }

  static Future<void>? radialGradient(
    SvgParser parserState,
    bool warningsAsErrors,
  ) {
    final String? gradientUnits = parserState.attribute('gradientUnits');
    bool isObjectBoundingBox = gradientUnits != 'userSpaceOnUse';

    final String? rawCx = parserState.attribute('cx', def: '50%');
    final String? rawCy = parserState.attribute('cy', def: '50%');
    final String? rawR = parserState.attribute('r', def: '50%');
    final String? rawFx = parserState.attribute('fx', def: rawCx);
    final String? rawFy = parserState.attribute('fy', def: rawCy);
    final TileMode spreadMethod = parserState.parseTileMode();
    final String id = parserState.buildUrlIri();
    final AffineMatrix? originalTransform = parseTransform(
      parserState.attribute('gradientTransform'),
    );

    final List<double> offsets = <double>[];
    final List<Color> colors = <Color>[];

    if (parserState._currentStartElement!.isSelfClosing) {
      final String? href = parserState._currentAttributes.href;
      final RadialGradient ref =
          parserState._definitions.getGradient<RadialGradient>('url($href)');

      if (gradientUnits == null) {
        isObjectBoundingBox =
            ref.unitMode == GradientUnitMode.objectBoundingBox;
      }
      colors.addAll(ref.colors);
      offsets.addAll(ref.offsets!);
    } else {
      parseStops(parserState, colors, offsets);
    }

    late double cx, cy, r, fx, fy;
    if (isObjectBoundingBox) {
      cx = parseDecimalOrPercentage(rawCx!);
      cy = parseDecimalOrPercentage(rawCy!);
      r = parseDecimalOrPercentage(rawR!);
      fx = parseDecimalOrPercentage(rawFx!);
      fy = parseDecimalOrPercentage(rawFy!);
    } else {
      cx = isPercentage(rawCx!)
          ? parsePercentage(rawCx) * parserState.rootBounds.width +
              parserState.rootBounds.left
          : parserState.parseDoubleWithUnits(rawCx)!;
      cy = isPercentage(rawCy!)
          ? parsePercentage(rawCy) * parserState.rootBounds.height +
              parserState.rootBounds.top
          : parserState.parseDoubleWithUnits(rawCy)!;
      r = isPercentage(rawR!)
          ? parsePercentage(rawR) *
              ((parserState.rootBounds.height + parserState.rootBounds.width) /
                  2)
          : parserState.parseDoubleWithUnits(rawR)!;
      fx = isPercentage(rawFx!)
          ? parsePercentage(rawFx) * parserState.rootBounds.width +
              parserState.rootBounds.left
          : parserState.parseDoubleWithUnits(rawFx)!;
      fy = isPercentage(rawFy!)
          ? parsePercentage(rawFy) * parserState.rootBounds.height +
              parserState.rootBounds.top
          : parserState.parseDoubleWithUnits(rawFy)!;
    }

    parserState._definitions.addGradient(
      id,
      RadialGradient(
        center: Point(cx, cy),
        radius: r,
        focalPoint: (fx != cx || fy != cy) ? Point(fx, fy) : Point(cx, cy),
        colors: colors,
        offsets: offsets,
        unitMode: isObjectBoundingBox
            ? GradientUnitMode.objectBoundingBox
            : GradientUnitMode.userSpaceOnUse,
        tileMode: spreadMethod,
        transform: originalTransform,
      ),
    );
    return null;
  }

  static Future<void>? linearGradient(
    SvgParser parserState,
    bool warningsAsErrors,
  ) {
    final String? gradientUnits = parserState.attribute('gradientUnits');
    bool isObjectBoundingBox = gradientUnits != 'userSpaceOnUse';

    final String x1 = parserState.attribute('x1', def: '0%')!;
    final String x2 = parserState.attribute('x2', def: '100%')!;
    final String y1 = parserState.attribute('y1', def: '0%')!;
    final String y2 = parserState.attribute('y2', def: '0%')!;
    final String id = parserState.buildUrlIri();
    final AffineMatrix? originalTransform = parseTransform(
      parserState.attribute('gradientTransform'),
    );
    final TileMode spreadMethod = parserState.parseTileMode();

    final List<Color> colors = <Color>[];
    final List<double> offsets = <double>[];
    if (parserState._currentStartElement!.isSelfClosing) {
      final String? href = parserState._currentAttributes.href;
      final LinearGradient ref =
          parserState._definitions.getGradient<LinearGradient>('url($href)');
      if (gradientUnits == null) {
        isObjectBoundingBox =
            ref.unitMode == GradientUnitMode.objectBoundingBox;
      }
      colors.addAll(ref.colors);
      offsets.addAll(ref.offsets!);
    } else {
      parseStops(parserState, colors, offsets);
    }

    Point fromPoint, toPoint;
    if (isObjectBoundingBox) {
      fromPoint = Point(
        parseDecimalOrPercentage(x1),
        parseDecimalOrPercentage(y1),
      );
      toPoint = Point(
        parseDecimalOrPercentage(x2),
        parseDecimalOrPercentage(y2),
      );
    } else {
      fromPoint = Point(
        isPercentage(x1)
            ? parsePercentage(x1) * parserState.rootBounds.width +
                parserState.rootBounds.left
            : parserState.parseDoubleWithUnits(x1)!,
        isPercentage(y1)
            ? parsePercentage(y1) * parserState.rootBounds.height +
                parserState.rootBounds.top
            : parserState.parseDoubleWithUnits(y1)!,
      );

      toPoint = Point(
        isPercentage(x2)
            ? parsePercentage(x2) * parserState.rootBounds.width +
                parserState.rootBounds.left
            : parserState.parseDoubleWithUnits(x2)!,
        isPercentage(y2)
            ? parsePercentage(y2) * parserState.rootBounds.height +
                parserState.rootBounds.top
            : parserState.parseDoubleWithUnits(y2)!,
      );
    }

    parserState._definitions.addGradient(
      id,
      LinearGradient(
        from: fromPoint,
        to: toPoint,
        colors: colors,
        offsets: offsets,
        tileMode: spreadMethod,
        unitMode: isObjectBoundingBox
            ? GradientUnitMode.objectBoundingBox
            : GradientUnitMode.userSpaceOnUse,
        transform: originalTransform,
      ),
    );

    return null;
  }

  static Future<void>? clipPath(SvgParser parserState, bool warningsAsErrors) {
    final String id = parserState.buildUrlIri();

    final List<PathBuilder> pathBuilders = <PathBuilder>[];
    PathBuilder? currentPath;
    for (XmlEvent event in parserState._readSubtree()) {
      if (event is XmlEndElementEvent) {
        continue;
      }
      if (event is XmlStartElementEvent) {
        final _PathFunc? pathFn = _svgPathFuncs[event.name];

        if (pathFn != null) {
          final PathBuilder nextPath = PathBuilder.fromPath(
            parserState.applyTransformIfNeeded(
              pathFn(parserState)!,
              parserState.currentGroup?.transform,
            ),
          );
          nextPath.fillType =
              parserState._currentAttributes.clipRule ?? PathFillType.nonZero;
          if (currentPath != null &&
              nextPath.fillType != currentPath.fillType) {
            currentPath = nextPath;
            pathBuilders.add(currentPath);
          } else if (currentPath == null) {
            currentPath = nextPath;
            pathBuilders.add(currentPath);
          } else {
            currentPath.addPath(nextPath.toPath(reset: false));
          }
        } else if (event.name == 'use') {
          final String? xlinkHref = parserState._currentAttributes.href;
          final Node? definitionDrawable =
              parserState._definitions.getDrawable('url($xlinkHref)');

          void extractPathsFromDrawable(Node? target) {
            if (target is PathNode) {
              pathBuilders.add(PathBuilder.fromPath(target.path));
            } else if (target is ParentNode) {
              target.visitChildren(extractPathsFromDrawable);
            }
          }

          extractPathsFromDrawable(definitionDrawable);
        } else {
          final String errorMessage =
              'Unsupported clipPath child ${event.name}';
          if (warningsAsErrors) {
            throw UnsupportedError(errorMessage);
          }
        }
      }
    }
    parserState._definitions.addClipPath(
        id,
        pathBuilders
            .map((PathBuilder builder) => builder.toPath())
            .toList(growable: false));
    return null;
  }

  static Future<void> image(
      SvgParser parserState, bool warningsAsErrors) async {
    throw UnsupportedError('TODO');
    // final String? href = parserState._currentAttributes.href;
    // if (href == null) {
    //   return;
    // }
    // final Point offset = Point(
    //   parserState.parseDoubleWithUnits(
    //     parserState.attribute('x', def: '0'),
    //   )!,
    //   parserState.parseDoubleWithUnits(
    //     parserState.attribute('y', def: '0'),
    //   )!,
    // );
    // final Size size = Size(
    //   parserState.parseDoubleWithUnits(
    //     parserState.attribute('width', def: '0'),
    //   )!,
    //   parserState.parseDoubleWithUnits(
    //     parserState.attribute('height', def: '0'),
    //   )!,
    // );
    // // final Image image = await resolveImage(href);
    // final ParentNode parent = parserState._parentDrawables.last.drawable!;
    // final DrawableStyle? parentStyle = parent.paint;
    // final DrawableRasterImage drawable = DrawableRasterImage(
    //   parserState.attribute('id', def: ''),
    //   image,
    //   offset,
    //   parserState.parseStyle(parserState.rootBounds, parentStyle,
    //       currentColor: parent.color),
    //   size: size,
    //   transform: parseTransform(parserState.attribute('transform'))?.storage,
    // );
    // parserState.checkForIri(drawable);

    // parserState.currentGroup!.children!.add(drawable);
  }

  static Future<void> text(
    SvgParser parserState,
    bool warningsAsErrors,
  ) async {
    throw UnsupportedError('TODO');
    // assert(parserState != null); // ignore: unnecessary_null_comparison
    // assert(parserState.currentGroup != null);
    // if (parserState._currentStartElement!.isSelfClosing) {
    //   return;
    // }

    // // <text>, <tspan> -> Collect styles
    // // <tref> TBD - looks like Inkscape supports it, but no browser does.
    // // XmlNodeType.TEXT/CDATA -> DrawableText
    // // Track the style(s) and offset(s) for <text> and <tspan> elements
    // final Queue<_TextInfo> textInfos = ListQueue<_TextInfo>();
    // double lastTextWidth = 0;

    // void _processText(String value) {
    //   if (value.isEmpty) {
    //     return;
    //   }
    //   assert(textInfos.isNotEmpty);
    //   final _TextInfo lastTextInfo = textInfos.last;
    //   // final Paragraph fill = createParagraph(
    //   //   value,
    //   //   lastTextInfo.style,
    //   //   lastTextInfo.style.fill,
    //   // );
    //   // final Paragraph stroke = createParagraph(
    //   //   value,
    //   //   lastTextInfo.style,
    //   //   DrawablePaint.isEmpty(lastTextInfo.style.stroke)
    //   //       ? transparentStroke
    //   //       : lastTextInfo.style.stroke,
    //   // );
    //   // parserState.currentGroup!.children!.add(
    //   //   DrawableText(
    //   //     parserState.attribute('id', def: ''),
    //   //     fill,
    //   //     stroke,
    //   //     lastTextInfo.offset,
    //   //     lastTextInfo.style.textStyle!.anchor ??
    //   //         DrawableTextAnchorPosition.start,
    //   //     transform: lastTextInfo.transform?.storage,
    //   //   ),
    //   // );
    //   // lastTextWidth = fill.maxIntrinsicWidth;
    // }

    // void _processStartElement(XmlStartElementEvent event) {
    //   _TextInfo? lastTextInfo;
    //   if (textInfos.isNotEmpty) {
    //     lastTextInfo = textInfos.last;
    //   }
    //   final Point currentPoint = _parseCurrentPoint(
    //     parserState,
    //     lastTextInfo?.offset.translate(lastTextWidth, 0),
    //   );
    //   AffineMatrix? transform =
    //       parseTransform(parserState.attribute('transform'));
    //   if (lastTextInfo?.transform != null) {
    //     if (transform == null) {
    //       transform = lastTextInfo!.transform;
    //     } else {
    //       transform = lastTextInfo!.transform!.multiplied(transform);
    //     }
    //   }

    //   final DrawableStyle? parentStyle =
    //       lastTextInfo?.style ?? parserState.currentGroup!.style;

    //   textInfos.add(_TextInfo(
    //     parserState.parseStyle(
    //       parserState.rootBounds,
    //       parentStyle,
    //     ),
    //     currentPoint,
    //     transform,
    //   ));
    //   if (event.isSelfClosing) {
    //     textInfos.removeLast();
    //   }
    // }

    // _processStartElement(parserState._currentStartElement!);

    // for (XmlEvent event in parserState._readSubtree()) {
    //   if (event is XmlCDATAEvent) {
    //     _processText(event.text.trim());
    //   } else if (event is XmlTextEvent) {
    //     final String? space =
    //         getAttribute(parserState.attributes, 'space');
    //     if (space != 'preserve') {
    //       _processText(event.text.trim());
    //     } else {
    //       _processText(event.text.replaceAll(_trimPattern, ''));
    //     }
    //   }
    //   if (event is XmlStartElementEvent) {
    //     _processStartElement(event);
    //   } else if (event is XmlEndElementEvent) {
    //     textInfos.removeLast();
    //   }
    // }
  }
}

// ignore: avoid_classes_with_only_static_members
class _Paths {
  static Path circle(SvgParser parserState) {
    final double cx = parserState.parseDoubleWithUnits(
      parserState.attribute('cx', def: '0'),
    )!;
    final double cy = parserState.parseDoubleWithUnits(
      parserState.attribute('cy', def: '0'),
    )!;
    final double r = parserState.parseDoubleWithUnits(
      parserState.attribute('r', def: '0'),
    )!;
    final Rect oval = Rect.fromCircle(cx, cy, r);
    return PathBuilder(parserState._currentAttributes.fillRule)
        .addOval(oval)
        .toPath();
  }

  static Path path(SvgParser parserState) {
    final String d = parserState.attribute('d', def: '')!;
    return parseSvgPathData(d, parserState._currentAttributes.fillRule);
  }

  static Path rect(SvgParser parserState) {
    final double x = parserState.parseDoubleWithUnits(
      parserState.attribute('x', def: '0'),
    )!;
    final double y = parserState.parseDoubleWithUnits(
      parserState.attribute('y', def: '0'),
    )!;
    final double w = parserState.parseDoubleWithUnits(
      parserState.attribute('width', def: '0'),
    )!;
    final double h = parserState.parseDoubleWithUnits(
      parserState.attribute('height', def: '0'),
    )!;
    String? rxRaw = parserState.attribute('rx');
    String? ryRaw = parserState.attribute('ry');
    rxRaw ??= ryRaw;
    ryRaw ??= rxRaw;

    if (rxRaw != null && rxRaw != '') {
      final double rx = parserState.parseDoubleWithUnits(rxRaw)!;
      final double ry = parserState.parseDoubleWithUnits(ryRaw)!;
      return PathBuilder(parserState._currentAttributes.fillRule)
          .addRRect(Rect.fromLTWH(x, y, w, h), rx, ry)
          .toPath();
    }

    return PathBuilder(parserState._currentAttributes.fillRule)
        .addRect(Rect.fromLTWH(x, y, w, h))
        .toPath();
  }

  static Path? polygon(SvgParser parserState) {
    return parsePathFromPoints(parserState, true);
  }

  static Path? polyline(SvgParser parserState) {
    return parsePathFromPoints(parserState, false);
  }

  static Path? parsePathFromPoints(SvgParser parserState, bool close) {
    final String points = parserState.attribute('points', def: '')!;
    if (points == '') {
      return null;
    }
    final String path = 'M$points${close ? 'z' : ''}';

    return parseSvgPathData(path, parserState._currentAttributes.fillRule);
  }

  static Path ellipse(SvgParser parserState) {
    final double cx = parserState.parseDoubleWithUnits(
      parserState.attribute('cx', def: '0'),
    )!;
    final double cy = parserState.parseDoubleWithUnits(
      parserState.attribute('cy', def: '0'),
    )!;
    final double rx = parserState.parseDoubleWithUnits(
      parserState.attribute('rx', def: '0'),
    )!;
    final double ry = parserState.parseDoubleWithUnits(
      parserState.attribute('ry', def: '0'),
    )!;

    final Rect r = Rect.fromLTWH(cx - rx, cy - ry, rx * 2, ry * 2);
    return PathBuilder(parserState._currentAttributes.fillRule)
        .addOval(r)
        .toPath();
  }

  static Path line(SvgParser parserState) {
    final double x1 = parserState.parseDoubleWithUnits(
      parserState.attribute('x1', def: '0'),
    )!;
    final double x2 = parserState.parseDoubleWithUnits(
      parserState.attribute('x2', def: '0'),
    )!;
    final double y1 = parserState.parseDoubleWithUnits(
      parserState.attribute('y1', def: '0'),
    )!;
    final double y2 = parserState.parseDoubleWithUnits(
      parserState.attribute('y2', def: '0'),
    )!;

    return PathBuilder(parserState._currentAttributes.fillRule)
        .moveTo(x1, y1)
        .lineTo(x2, y2)
        .toPath();
  }
}

class _SvgGroupTuple {
  _SvgGroupTuple(this.name, this.drawable);

  final String name;
  final ParentNode drawable;
}

/// Reads an SVG XML string and via the [parse] method creates a set of
/// [VectorInstructions].
class SvgParser {
  /// Creates a new [SvgParser].
  SvgParser(
    String xml,
    this.theme,
    this._key,
    this._warningsAsErrors,
  ) : _eventIterator = parseEvents(xml).iterator;

  /// The theme used when parsing SVG elements.
  final SvgTheme theme;

  final Iterator<XmlEvent> _eventIterator;
  final String? _key;
  final bool _warningsAsErrors;
  final _DrawableDefinitionServer _definitions = _DrawableDefinitionServer();
  final Queue<_SvgGroupTuple> _parentDrawables = ListQueue<_SvgGroupTuple>(10);
  ViewportNode? _root;
  SvgAttributes _currentAttributes = SvgAttributes.empty;
  XmlStartElementEvent? _currentStartElement;

  /// The current depth of the reader in the XML hierarchy.
  int depth = 0;

  void _discardSubtree() {
    final int subtreeStartDepth = depth;
    while (_eventIterator.moveNext()) {
      final XmlEvent event = _eventIterator.current;
      if (event is XmlStartElementEvent && !event.isSelfClosing) {
        depth += 1;
      } else if (event is XmlEndElementEvent) {
        depth -= 1;
        assert(depth >= 0);
      }
      _currentAttributes = SvgAttributes.empty;
      _currentStartElement = null;
      if (depth < subtreeStartDepth) {
        return;
      }
    }
  }

  Iterable<XmlEvent> _readSubtree() sync* {
    final int subtreeStartDepth = depth;
    while (_eventIterator.moveNext()) {
      final XmlEvent event = _eventIterator.current;
      bool isSelfClosing = false;
      if (event is XmlStartElementEvent) {
        final Map<String, String> attributeMap =
            _createAttributeMap(event.attributes);
        if (!_isVisible(attributeMap)) {
          if (!event.isSelfClosing) {
            depth += 1;
            _discardSubtree();
          }
          continue;
        }
        _currentAttributes = _createSvgAttributes(
          attributeMap,
          currentColor: depth == 0 ? theme.currentColor : null,
        );
        _currentStartElement = event;
        depth += 1;
        isSelfClosing = event.isSelfClosing;
      }
      yield event;

      if (isSelfClosing || event is XmlEndElementEvent) {
        depth -= 1;
        assert(depth >= 0);
        _currentAttributes = SvgAttributes.empty;
        _currentStartElement = null;
      }
      if (depth < subtreeStartDepth) {
        return;
      }
    }
  }

  /// Drive the XML reader to EOF and produce [VectorInstructions].
  Future<VectorInstructions> parse() async {
    for (XmlEvent event in _readSubtree()) {
      if (event is XmlStartElementEvent) {
        if (startElement(event)) {
          continue;
        }
        final _ParseFunc? parseFunc = _svgElementParsers[event.name];
        await parseFunc?.call(this, _warningsAsErrors);
        if (parseFunc == null) {
          if (!event.isSelfClosing) {
            _discardSubtree();
          }
          assert(() {
            unhandledElement(event);
            return true;
          }());
        }
      } else if (event is XmlEndElementEvent) {
        endElement(event);
      }
    }
    if (_root == null) {
      throw StateError('Invalid SVG data');
    }
    final DrawCommandBuilder builder = DrawCommandBuilder();
    _root!.build(builder, AffineMatrix.identity);
    return builder.toInstructions(_root!.width, _root!.height);
  }

  /// Gets the attribute for the current position of the parser.
  String? attribute(String name, {String? def}) =>
      _currentAttributes.raw[name] ?? def;

  /// The current group, if any, in the [Drawable] heirarchy.
  ParentNode? get currentGroup {
    assert(_parentDrawables.isNotEmpty);
    return _parentDrawables.last.drawable;
  }

  /// The root bounds of the drawable.
  Rect get rootBounds {
    assert(_root != null, 'Cannot get rootBounds with null root');
    return _root!.viewport;
  }

  /// Whether this [DrawableStyleable] belongs in the [DrawableDefinitions] or not.
  bool checkForIri(AttributedNode? drawable) {
    final String iri = buildUrlIri();
    if (iri != emptyUrlIri) {
      _definitions.addDrawable(iri, drawable!);
      return true;
    }
    return false;
  }

  /// Appends a group to the collection.
  void addGroup(XmlStartElementEvent event, ParentNode drawable) {
    _parentDrawables.addLast(_SvgGroupTuple(event.name, drawable));
    checkForIri(drawable);
  }

  /// Updates the [VectorInstructions] with the current path and paint.
  bool addShape(XmlStartElementEvent event) {
    final _PathFunc? pathFunc = _svgPathFuncs[event.name];
    if (pathFunc == null) {
      return false;
    }
    if (!_currentAttributes.paintsAnything) {
      return true;
    }
    final ParentNode parent = _parentDrawables.last.drawable;
    final Path path = pathFunc(this)!;

    final PathNode drawable = PathNode(path, _currentAttributes);
    checkForIri(drawable);
    parent.addChild(
      drawable,
      clipId: _currentAttributes.clipPathId,
      clipServer: _definitions.getClipPath,
      maskId: attribute('mask'),
      maskServer: _definitions.getDrawable,
    );
    return true;
  }

  /// Potentially handles a starting element, if it was a singular shape or a
  /// `<defs>` element.
  bool startElement(XmlStartElementEvent event) {
    if (event.name == 'defs') {
      if (!event.isSelfClosing) {
        addGroup(
          event,
          ParentNode(_currentAttributes),
        );
        return true;
      }
    }
    return addShape(event);
  }

  /// Handles the end of an XML element.
  void endElement(XmlEndElementEvent event) {
    while (event.name == _parentDrawables.last.name &&
        _parentDrawables.last.drawable is ClipNode) {
      _parentDrawables.removeLast();
    }
    if (event.name == _parentDrawables.last.name) {
      _parentDrawables.removeLast();
    }
  }

  /// Prints an error for unhandled elements.
  ///
  /// Will only print an error once for unhandled/unexpected elements, except for
  /// `<style/>`, `<title/>`, and `<desc/>` elements.
  void unhandledElement(XmlStartElementEvent event) {
    final String errorMessage =
        'unhandled element ${event.name}; Picture key: $_key';
    if (_warningsAsErrors) {
      // Throw error instead of log warning.
      throw UnimplementedError(errorMessage);
    }
    if (_unhandledElements.add(event.name)) {
      print(errorMessage);
    }
  }

  /// Parses a `rawDouble` `String` to a `double`
  /// taking into account absolute and relative units
  /// (`px`, `em` or `ex`).
  ///
  /// Passing an `em` value will calculate the result
  /// relative to the provided [fontSize]:
  /// 1 em = 1 * `fontSize`.
  ///
  /// Passing an `ex` value will calculate the result
  /// relative to the provided [xHeight]:
  /// 1 ex = 1 * `xHeight`.
  ///
  /// The `rawDouble` might include a unit which is
  /// stripped off when parsed to a `double`.
  ///
  /// Passing `null` will return `null`.
  double? parseDoubleWithUnits(
    String? rawDouble, {
    bool tryParse = false,
  }) {
    return numbers.parseDoubleWithUnits(
      rawDouble,
      tryParse: tryParse,
      theme: theme,
    );
  }

  static final Map<String, double> _kTextSizeMap = <String, double>{
    'xx-small': 10,
    'x-small': 12,
    'small': 14,
    'medium': 18,
    'large': 22,
    'x-large': 26,
    'xx-large': 32,
  };

  /// Parses a `font-size` attribute.
  double? parseFontSize(
    String? raw, {
    double? parentValue,
  }) {
    if (raw == null || raw == '') {
      return null;
    }

    double? ret = parseDoubleWithUnits(
      raw,
      tryParse: true,
    );
    if (ret != null) {
      return ret;
    }

    raw = raw.toLowerCase().trim();
    ret = _kTextSizeMap[raw];
    if (ret != null) {
      return ret;
    }

    if (raw == 'larger') {
      if (parentValue == null) {
        return _kTextSizeMap['large'];
      }
      return parentValue * 1.2;
    }

    if (raw == 'smaller') {
      if (parentValue == null) {
        return _kTextSizeMap['small'];
      }
      return parentValue / 1.2;
    }

    throw StateError('Could not parse font-size: $raw');
  }

  double _parseRawWidthHeight(String raw) {
    if (raw == '100%' || raw == '') {
      return double.infinity;
    }
    assert(() {
      final RegExp notDigits = RegExp(r'[^\d\.]');
      if (!raw.endsWith('px') &&
          !raw.endsWith('em') &&
          !raw.endsWith('ex') &&
          raw.contains(notDigits)) {
        print(
            'Warning: Flutter SVG only supports the following formats for `width` and `height` on the SVG root:\n'
            '  width="100%"\n'
            '  width="100em"\n'
            '  width="100ex"\n'
            '  width="100px"\n'
            '  width="100" (where the number will be treated as pixels).\n'
            'The supplied value ($raw) will be discarded and treated as if it had not been specified.');
      }
      return true;
    }());
    return parseDoubleWithUnits(raw, tryParse: true) ?? double.infinity;
  }

  /// Parses an SVG @viewBox attribute (e.g. 0 0 100 100) to a [Viewport].
  _Viewport _parseViewBox() {
    final String viewBox = attribute('viewBox') ?? '';
    final String rawWidth = attribute('width') ?? '';
    final String rawHeight = attribute('height') ?? '';

    if (viewBox == '' && rawWidth == '' && rawHeight == '') {
      throw StateError('SVG did not specify dimensions\n\n'
          'The SVG library looks for a `viewBox` or `width` and `height` attribute '
          'to determine the viewport boundary of the SVG.  Note that these attributes, '
          'as with all SVG attributes, are case sensitive.\n'
          'During processing, the following attributes were found:\n'
          '  ${_currentAttributes.raw}');
    }

    if (viewBox == '') {
      final double width = _parseRawWidthHeight(rawWidth);
      final double height = _parseRawWidthHeight(rawHeight);
      return _Viewport(
        width,
        height,
        AffineMatrix.identity,
      );
    }

    final List<String> parts = viewBox.split(RegExp(r'[ ,]+'));
    if (parts.length < 4) {
      throw StateError('viewBox element must be 4 elements long');
    }
    final double width = parseDouble(parts[2])!;
    final double height = parseDouble(parts[3])!;
    final double translateX = -parseDouble(parts[0])!;
    final double translateY = -parseDouble(parts[1])!;

    return _Viewport(
      width,
      height,
      AffineMatrix.identity.translated(translateX, translateY),
    );
  }

  /// Builds an IRI in the form of `'url(#id)'`.
  String buildUrlIri() => 'url(#${_currentAttributes.id})';

  /// An empty IRI.
  static const String emptyUrlIri = _DrawableDefinitionServer.emptyUrlIri;

  /// Parses a `spreadMethod` attribute into a [TileMode].
  TileMode parseTileMode() {
    final String? spreadMethod = attribute('spreadMethod', def: 'pad');
    switch (spreadMethod) {
      case 'pad':
        return TileMode.clamp;
      case 'repeat':
        return TileMode.repeated;
      case 'reflect':
        return TileMode.mirror;
      default:
        return TileMode.clamp;
    }
  }

  StrokeCap? _parseCap(
    String? raw,
    Stroke? definitionPaint,
  ) {
    switch (raw) {
      case 'butt':
        return StrokeCap.butt;
      case 'round':
        return StrokeCap.round;
      case 'square':
        return StrokeCap.square;
      default:
        return definitionPaint?.cap;
    }
  }

  StrokeJoin? _parseJoin(
    String? raw,
    Stroke? definitionPaint,
  ) {
    switch (raw) {
      case 'miter':
        return StrokeJoin.miter;
      case 'bevel':
        return StrokeJoin.bevel;
      case 'round':
        return StrokeJoin.round;
      default:
        return definitionPaint?.join;
    }
  }

  Color? _determineFillColor(
    String rawFill,
    double opacity,
    bool explicitOpacity,
    Color? defaultFillColor,
    Color? currentColor,
  ) {
    final Color? color =
        parseColor(rawFill) ?? currentColor ?? defaultFillColor;

    if (explicitOpacity && color != null) {
      return color.withOpacity(opacity);
    }

    return color;
  }

  /// Applies a transform to a path if the [attributes] contain a `transform`.
  Path applyTransformIfNeeded(Path path, AffineMatrix? parentTransform) {
    final AffineMatrix? transform = parseTransform(attribute('transform'));

    if (transform != null) {
      return path.transformed(transform);
    } else {
      return path;
    }
  }

  /// Parses a `clipPath` element into a list of [Path]s.
  List<Path> parseClipPath() {
    final String? id = _currentAttributes.clipPathId;
    if (id != null) {
      // If this returns null it should be an error, but for now match
      // flutter_svg behavior.
      return _definitions.getClipPath(id);
    }

    return <Path>[];
  }

  static const Map<String, BlendMode> _blendModes = <String, BlendMode>{
    'multiply': BlendMode.multiply,
    'screen': BlendMode.screen,
    'overlay': BlendMode.overlay,
    'darken': BlendMode.darken,
    'lighten': BlendMode.lighten,
    'color-dodge': BlendMode.colorDodge,
    'color-burn': BlendMode.colorBurn,
    'hard-light': BlendMode.hardLight,
    'soft-light': BlendMode.softLight,
    'difference': BlendMode.difference,
    'exclusion': BlendMode.exclusion,
    'hue': BlendMode.hue,
    'saturation': BlendMode.saturation,
    'color': BlendMode.color,
    'luminosity': BlendMode.luminosity,
  };

  /// Lookup the mask if the attribute is present.
  Node? parseMask() {
    final String? rawMaskAttribute = attribute('mask');
    if (rawMaskAttribute != null) {
      return _definitions.getDrawable(rawMaskAttribute);
    }

    return null;
  }

  /// Converts a SVG Color String (either a # prefixed color string or a named color) to a [Color].
  Color? parseColor(String? colorString) {
    if (colorString == null || colorString.isEmpty) {
      return null;
    }

    if (colorString == 'none') {
      return null;
    }

    if (colorString.toLowerCase() == 'currentcolor') {
      return null;
    }

    // handle hex colors e.g. #fff or #ffffff.  This supports #RRGGBBAA
    if (colorString[0] == '#') {
      if (colorString.length == 4) {
        final String r = colorString[1];
        final String g = colorString[2];
        final String b = colorString[3];
        colorString = '#$r$r$g$g$b$b';
      }
      int color = int.parse(colorString.substring(1), radix: 16);

      if (colorString.length == 7) {
        return Color(color |= 0xFF000000);
      }

      if (colorString.length == 9) {
        return Color(color);
      }
    }

    // handle rgba() colors e.g. rgba(255, 255, 255, 1.0)
    if (colorString.toLowerCase().startsWith('rgba')) {
      final List<String> rawColorElements = colorString
          .substring(colorString.indexOf('(') + 1, colorString.indexOf(')'))
          .split(',')
          .map((String rawColor) => rawColor.trim())
          .toList();

      final double opacity = parseDouble(rawColorElements.removeLast())!;

      final List<int> rgb = rawColorElements
          .map((String rawColor) => int.parse(rawColor))
          .toList();

      return Color.fromRGBO(rgb[0], rgb[1], rgb[2], opacity);
    }

    // Conversion code from: https://github.com/MichaelFenwick/Color, thanks :)
    if (colorString.toLowerCase().startsWith('hsl')) {
      final List<int> values = colorString
          .substring(colorString.indexOf('(') + 1, colorString.indexOf(')'))
          .split(',')
          .map((String rawColor) {
        rawColor = rawColor.trim();

        if (rawColor.endsWith('%')) {
          rawColor = rawColor.substring(0, rawColor.length - 1);
        }

        if (rawColor.contains('.')) {
          return (parseDouble(rawColor)! * 2.55).round();
        }

        return int.parse(rawColor);
      }).toList();
      final double hue = values[0] / 360 % 1;
      final double saturation = values[1] / 100;
      final double luminance = values[2] / 100;
      final int alpha = values.length > 3 ? values[3] : 255;
      List<double> rgb = <double>[0, 0, 0];

      if (hue < 1 / 6) {
        rgb[0] = 1;
        rgb[1] = hue * 6;
      } else if (hue < 2 / 6) {
        rgb[0] = 2 - hue * 6;
        rgb[1] = 1;
      } else if (hue < 3 / 6) {
        rgb[1] = 1;
        rgb[2] = hue * 6 - 2;
      } else if (hue < 4 / 6) {
        rgb[1] = 4 - hue * 6;
        rgb[2] = 1;
      } else if (hue < 5 / 6) {
        rgb[0] = hue * 6 - 4;
        rgb[2] = 1;
      } else {
        rgb[0] = 1;
        rgb[2] = 6 - hue * 6;
      }

      rgb = rgb
          .map((double val) => val + (1 - saturation) * (0.5 - val))
          .toList();

      if (luminance < 0.5) {
        rgb = rgb.map((double val) => luminance * 2 * val).toList();
      } else {
        rgb = rgb
            .map((double val) => luminance * 2 * (1 - val) + 2 * val - 1)
            .toList();
      }

      rgb = rgb.map((double val) => val * 255).toList();

      return Color.fromARGB(
          alpha, rgb[0].round(), rgb[1].round(), rgb[2].round());
    }

    // handle rgb() colors e.g. rgb(255, 255, 255)
    if (colorString.toLowerCase().startsWith('rgb')) {
      final List<int> rgb = colorString
          .substring(colorString.indexOf('(') + 1, colorString.indexOf(')'))
          .split(',')
          .map((String rawColor) {
        rawColor = rawColor.trim();
        if (rawColor.endsWith('%')) {
          rawColor = rawColor.substring(0, rawColor.length - 1);
          return (parseDouble(rawColor)! * 2.55).round();
        }
        return int.parse(rawColor);
      }).toList();

      // rgba() isn't really in the spec, but Firefox supported it at one point so why not.
      final int a = rgb.length > 3 ? rgb[3] : 255;
      return Color.fromARGB(a, rgb[0], rgb[1], rgb[2]);
    }

    // handle named colors ('red', 'green', etc.).
    final Color? namedColor = namedColors[colorString];
    if (namedColor != null) {
      return namedColor;
    }

    throw StateError('Could not parse "$colorString" as a color.');
  }

  Map<String, String> _createAttributeMap(List<XmlEventAttribute> attributes) {
    final Map<String, String> attributeMap = <String, String>{};
    if (_parentDrawables.isNotEmpty && currentGroup != null) {
      attributeMap.addEntries(currentGroup!.attributes.heritable);
    }

    for (final XmlEventAttribute attribute in attributes) {
      final String value = attribute.value.trim();
      if (attribute.localName == 'style') {
        for (final String style in value.split(';')) {
          if (style.isEmpty) {
            continue;
          }
          final List<String> styleParts = style.split(':');
          final String attributeValue = styleParts[1].trim();
          if (attributeValue == 'inherit') {
            continue;
          }
          attributeMap[styleParts[0].trim()] = attributeValue;
        }
      } else if (value != 'inherit') {
        attributeMap[attribute.localName] = value;
      }
    }
    return attributeMap;
  }

  SvgStrokeAttributes? _parseStrokeAttributes(
    Map<String, String> attributeMap,
    double? uniformOpacity,
    Color? currentColor,
  ) {
    final String? rawStroke = attributeMap['stroke'];
    if (rawStroke == 'none') {
      return SvgStrokeAttributes.none;
    }

    final String? rawStrokeOpacity = attributeMap['stroke-opacity'];
    double opacity = 1.0;
    if (rawStrokeOpacity != null) {
      opacity = parseDouble(rawStrokeOpacity)!.clamp(0.0, 1.0).toDouble();
    }
    if (uniformOpacity != null) {
      opacity *= uniformOpacity;
    }

    final String? rawStrokeCap = attributeMap['stroke-linecap'];
    final String? rawLineJoin = attributeMap['stroke-linejoin'];
    final String? rawMiterLimit = attributeMap['stroke-miterlimit'];
    final String? rawStrokeWidth = attributeMap['stroke-width'];

    final String? anyStrokeAttribute = rawStroke ??
        rawStrokeCap ??
        rawLineJoin ??
        rawMiterLimit ??
        rawStrokeWidth;

    if (anyStrokeAttribute == null || rawStroke == 'none') {
      return null;
    }

    Paint? definitionPaint;
    Color? strokeColor;
    String? shaderId;
    if (rawStroke?.startsWith('url') == true) {
      shaderId = rawStroke;
      strokeColor = Color.fromRGBO(255, 255, 255, opacity);
    } else {
      strokeColor = parseColor(rawStroke);
    }

    return SvgStrokeAttributes._(
      _definitions,
      shaderId: shaderId,
      color: (strokeColor ?? currentColor ?? definitionPaint?.stroke?.color)
          ?.withOpacity(opacity),
      cap: _parseCap(rawStrokeCap, definitionPaint?.stroke),
      join: _parseJoin(rawLineJoin, definitionPaint?.stroke),
      miterLimit:
          parseDouble(rawMiterLimit) ?? definitionPaint?.stroke?.miterLimit,
      width: parseDoubleWithUnits(rawStrokeWidth) ??
          definitionPaint?.stroke?.width,
    );
  }

  SvgFillAttributes? _parseFillAttributes(
    Map<String, String> attributeMap,
    double? uniformOpacity,
    Color? currentColor,
  ) {
    final String rawFill = attributeMap['fill'] ?? '';

    if (rawFill == 'none') {
      return SvgFillAttributes.none;
    }

    final String? rawFillOpacity = attributeMap['fill-opacity'];
    double opacity = 1.0;
    if (rawFillOpacity != null) {
      opacity = parseDouble(rawFillOpacity)!.clamp(0.0, 1.0).toDouble();
    }
    if (uniformOpacity != null) {
      opacity *= uniformOpacity;
    }

    if (rawFill.startsWith('url')) {
      return SvgFillAttributes._(
        _definitions,
        color: Color.fromRGBO(255, 255, 255, opacity),
        shaderId: rawFill,
      );
    }

    final Color? fillColor = _determineFillColor(
      rawFill,
      opacity,
      uniformOpacity != null || rawFillOpacity != '',
      Color.opaqueBlack,
      currentColor,
    );

    if (fillColor == null) {
      return null;
    }

    return SvgFillAttributes._(
      _definitions,
      color: fillColor,
    );
  }

  bool _isVisible(Map<String, String> attributeMap) {
    return attributeMap['display'] != 'none' &&
        attributeMap['visibility'] != 'hidden';
  }

  SvgAttributes _createSvgAttributes(
    Map<String, String> attributeMap, {
    Color? currentColor,
  }) {
    final double? opacity =
        parseDouble(attributeMap['opacity'])?.clamp(0.0, 1.0).toDouble();
    final Color? color = parseColor(attributeMap['color']) ?? currentColor;
    return SvgAttributes._(
      raw: attributeMap,
      id: attributeMap['id'],
      href: attributeMap['href'],
      opacity: opacity,
      color: color,
      stroke: _parseStrokeAttributes(attributeMap, opacity, color),
      fill: _parseFillAttributes(attributeMap, opacity, color),
      fillRule:
          parseRawFillRule(attributeMap['fill-rule']) ?? PathFillType.nonZero,
      clipRule: parseRawFillRule(attributeMap['clip-rule']),
      clipPathId: attributeMap['clip-path'],
      blendMode: _blendModes[attributeMap['mix-blend-mode']],
      transform:
          parseTransform(attributeMap['transform']) ?? AffineMatrix.identity,
    );
  }
}

class _DrawableDefinitionServer {
  static const String emptyUrlIri = 'url(#)';
  final Map<String, AttributedNode> _drawables = <String, AttributedNode>{};
  final Map<String, Shader> _shaders = <String, Shader>{};
  final Map<String, List<Path>> _clips = <String, List<Path>>{};

  AttributedNode getDrawable(String ref) => _drawables[ref]!;
  List<Path> getClipPath(String ref) => _clips[ref]!;
  T getGradient<T extends Shader>(String ref) => _shaders[ref]! as T;
  void addGradient<T extends Shader>(String ref, T gradient) {
    _shaders[ref] = gradient;
  }

  void addClipPath(String ref, List<Path> paths) {
    _clips[ref] = paths;
  }

  void addDrawable(String ref, AttributedNode drawable) {
    _drawables[ref] = drawable;
  }
}

class _Viewport {
  const _Viewport(this.width, this.height, this.transform);

  final double width;
  final double height;
  final AffineMatrix transform;
}

/// A collection of attributes for an SVG element.
class SvgAttributes {
  const SvgAttributes._({
    required this.raw,
    this.id,
    this.href,
    this.transform = AffineMatrix.identity,
    this.color,
    this.opacity,
    this.stroke,
    this.fill,
    this.fillRule = PathFillType.nonZero,
    this.clipRule,
    this.clipPathId,
    this.blendMode,
  });

  /// The empty set of properties.
  static const SvgAttributes empty = SvgAttributes._(raw: <String, String>{});

  /// Whether these attributes could result in any visual display if applied to
  /// a leaf shape node.
  bool get paintsAnything => opacity != 0 && (stroke != null || fill != null);

  /// The raw attribute map.
  final Map<String, String> raw;

  /// Generated from https://www.w3.org/TR/SVG11/single-page.html
  ///
  /// Using this:
  /// ```javascript
  /// let set = '<String>{';
  /// document.querySelectorAll('.propdef')
  ///   .forEach((propdef) => {
  ///     const nameNode = propdef.querySelector('.propdef-title.prop-name');
  ///     if (!nameNode) {
  ///       return;
  ///     }
  ///     const inherited = propdef.querySelector('tbody tr:nth-child(4) td:nth-child(2)').innerText.startsWith('yes');
  ///     if (inherited) {
  ///       set += `'${nameNode.innerText.replaceAll(/[‘’]/g, '')}',`;
  ///     }
  ///   });
  /// set += '};';
  /// console.log(set);
  /// ```
  static const Set<String> _heritableProps = <String>{
    'writing-mode',
    'glyph-orientation-vertical',
    'glyph-orientation-horizontal',
    'direction',
    'text-anchor',
    'font-family',
    'font-style',
    'font-variant',
    'font-weight',
    'font-stretch',
    'font-size',
    'font-size-adjust',
    'font',
    'kerning',
    'letter-spacing',
    'word-spacing',
    'fill',
    'fill-rule',
    'fill-opacity',
    'stroke',
    'stroke-width',
    'stroke-linecap',
    'stroke-linejoin',
    'stroke-miterlimit',
    'stroke-dasharray',
    'stroke-dashoffset',
    'stroke-opacity',
    'visibility',
    'marker-start',
    'marker',
    'color-interpolation',
    'color-interpolation-filters',
    'color-rendering',
    'shape-rendering',
    'text-rendering',
    'image-rendering',
    'color',
    'color-profile',
    'clip-rule',
    'pointer-events',
    'cursor',
  };

  /// The properties in [raw] that are heritable per the SVG 1.1 specification.
  Iterable<MapEntry<String, String>> get heritable {
    return raw.entries.where((MapEntry<String, String> entry) {
      return _heritableProps.contains(entry.key);
    });
  }

  /// The `@id` attribute.
  final String? id;

  /// The `@href` attribute.
  final String? href;

  /// The uniform opacity for the object, i.e. the `@opacity` attribute.
  /// https://www.w3.org/TR/SVG11/masking.html#OpacityProperty
  final double? opacity;

  /// The `@color` attribute, which provides an indirect current color.
  ///
  /// Does _not_ include the [opacity] value.
  ///
  /// https://www.w3.org/TR/SVG11/color.html#ColorProperty
  final Color? color;

  /// The stroking properties of this element.
  final SvgStrokeAttributes? stroke;

  /// The filling properties of this element.
  final SvgFillAttributes? fill;

  /// The `@transform` attribute.
  final AffineMatrix transform;

  /// The `@fill-rule` attribute.
  final PathFillType fillRule;

  /// The `@clip-rule` attribute.
  final PathFillType? clipRule;

  /// The raw identifier for clip path(s) to apply.
  final String? clipPathId;

  /// The `mix-blend-mode` attribute.
  final BlendMode? blendMode;

  /// Creates a new set of attributes as if this inherited from `parent`.
  SvgAttributes applyParent(SvgAttributes parent) {
    final Map<String, String> newRaw = <String, String>{
      ...Map<String, String>.fromEntries(parent.heritable),
      ...raw,
    };
    return SvgAttributes._(
      raw: newRaw,
      id: id,
      href: href,
      transform: transform,
      color: parent.color ?? color,
      opacity: parent.opacity ?? opacity,
      stroke: parent.stroke ?? stroke,
      fill: parent.fill ?? fill,
      fillRule: fillRule,
      clipRule: parent.clipRule ?? clipRule,
      clipPathId: parent.clipPathId ?? clipPathId,
      blendMode: parent.blendMode ?? blendMode,
    );
  }
}

/// SVG attributes specific to stroking.
class SvgStrokeAttributes {
  const SvgStrokeAttributes._(
    this._definitions, {
    this.color,
    this.shaderId,
    this.join,
    this.cap,
    this.miterLimit,
    this.width,
  });

  /// Specifies that strokes should not be drawn, even if they otherwise would
  /// be.
  static const SvgStrokeAttributes none = SvgStrokeAttributes._(null);

  final _DrawableDefinitionServer? _definitions;

  /// The color to use for stroking. _Does_ include the opacity value. Only
  /// opacity is used if the [shaderId] is not null.
  final Color? color;

  /// The literal reference to a shader defined elsewhere.
  final String? shaderId;

  /// The join style to use for the stroke.
  final StrokeJoin? join;

  /// The cap style to use for the stroke.
  final StrokeCap? cap;

  /// The miter limit to use if the [join] is [StrokeJoin.miter].
  final double? miterLimit;

  /// The width of the stroke.
  final double? width;

  /// Creates a stroking paint object from this set of attributes, using the
  /// bounds and transform specified for shader computation.
  ///
  /// Returns null if this is [none].
  Stroke? toStroke(Rect shaderBounds, AffineMatrix transform) {
    if (_definitions == null) {
      return null;
    }

    Shader? shader;
    if (shaderId != null) {
      shader = _definitions!
          .getGradient<Shader>(shaderId!)
          .applyBounds(shaderBounds, transform);
    }
    return Stroke(
      color: color,
      shader: shader,
      cap: cap,
      miterLimit: miterLimit,
      width: width,
    );
  }
}

/// SVG attributes specific to filling.
class SvgFillAttributes {
  const SvgFillAttributes._(this._definitions, {this.color, this.shaderId});

  /// Specifies that fills should not be drawn, even if they otherwise would be.
  static const SvgFillAttributes none = SvgFillAttributes._(null);

  final _DrawableDefinitionServer? _definitions;

  /// The color to use for filling. _Does_ include the opacity value. Only
  /// opacity is used if the [shaderId] is not null.
  final Color? color;

  /// The literal reference to a shader defined elsewhere.
  final String? shaderId;

  /// Creates a [Fill] from this information with appropriate transforms and
  /// bounds for shaders.
  ///
  /// Returns null if this is [none].
  Fill? toFill(Rect shaderBounds, AffineMatrix transform) {
    if (_definitions == null) {
      return null;
    }
    Shader? shader;
    if (shaderId != null) {
      shader = _definitions!
          .getGradient<Shader>(shaderId!)
          .applyBounds(shaderBounds, transform);
    }
    return Fill(color: color, shader: shader);
  }
}
