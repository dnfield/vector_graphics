# CHANGELOG

## 1.1.5

- Support for encoding path control points as IEEE 754-2008 half precision
  floating point values using the option `--use-half-precision-control-points`.

## 1.1.4

- Support more image formats and malformed MIME types.
- Fix inheritence for `fill-rule`s.

## 1.1.3

- Further improvements to whitespace handling for text.

## 1.1.2

- Fix handling and inheritence of `none`.

## 1.1.1

- Multiple text positioning bug fixes.
- Preserve stroke-opacity when specified.

## 1.1.0

- Fix a number of inheritence related bugs:
  - Inheritence of properties specified on the root element now work.
  - Opacity inheritence is more correct now.
  - Inheritence of `use` elements is more correctly handled.
- Make `currentColor` non-null on SVG theme, and fix how it is applied.
- Remove the opacity peephole optimizer, which was incorrectly applying
  optimizations in a few cases. A future release may add this back.
- Add clipBehavior to the widget.
- Fix patterns when multiple patterns are specified and applied within the
  graphic.

## 1.0.1

- Fix handling of unspecified fill colors on use/group elements.

## 1.0.0+1

- Fix issue in pattern decoding.
- Fix issue in matrix parsing for some combinations of matrices.

## 1.0.0

* Initial stable release.
* Parsing is now synchronous, and is easier to work with in tests.
* Correctly handle images with `id`s and defined in `defs` blocks.
* Compile time color remapping support.

## 0.0.3

* Better concurrency support
* Pattern support.
* Bug fixes around image handling.
* Bug fix for when optimizers are used on non-default fill types.
* Support for SVG theme related properties (currentColor, font-size, x-height).

## 0.0.2

* Add optimizations for masks, clipping, and overdraw.

## 0.0.1

* Create repository
