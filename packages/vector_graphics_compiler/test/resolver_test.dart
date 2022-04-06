import 'package:test/test.dart';
import 'package:vector_graphics_compiler/src/geometry/basic_types.dart';
import 'package:vector_graphics_compiler/src/geometry/matrix.dart';
import 'package:vector_graphics_compiler/src/geometry/path.dart';
import 'package:vector_graphics_compiler/src/paint.dart';
import 'package:vector_graphics_compiler/src/svg/node.dart';
import 'package:vector_graphics_compiler/src/svg/parser.dart';
import 'package:vector_graphics_compiler/src/svg/resolver.dart';

void main() {
  test(
      'Resolves PathNodes to ResolvedPathNodes by flattening the transform '
      'and computing bounds', () {
    final PathNode pathNode = PathNode(
      Path(
        commands: const <PathCommand>[
          MoveToCommand(0, 0),
          MoveToCommand(10, 10),
        ],
      ),
      SvgAttributes(
        transform: AffineMatrix.identity.translated(10, 10),
        raw: <String, String>{},
        fill: SvgFillAttributes(
          RefResolver(),
          color: const Color(0xFFAABBCC),
        ),
      ),
    );

    final ResolvingVisitor resolver = ResolvingVisitor();
    final ResolvedPathNode resolvedPathNode =
        pathNode.accept(resolver, AffineMatrix.identity) as ResolvedPathNode;

    expect(resolvedPathNode.bounds, const Rect.fromLTWH(10, 10, 10, 10));
    expect(
      resolvedPathNode.path,
      Path(
        commands: const <PathCommand>[
          MoveToCommand(10, 10),
          MoveToCommand(20, 20),
        ],
      ),
    );
  });

  test('Resolving Nodes replaces empty text with Node.zero', () {
    final ViewportNode viewportNode = ViewportNode(
      SvgAttributes.empty,
      width: 100,
      height: 100,
      transform: AffineMatrix.identity,
    );
    viewportNode.addChild(
      TextNode('', Point.zero, true, 12, FontWeight.w100, SvgAttributes.empty),
      clipResolver: (String ref) => <Path>[],
      maskResolver: (String ref) => null,
    );

    final ResolvingVisitor resolver = ResolvingVisitor();
    final ViewportNode newViewport =
        viewportNode.accept(resolver, AffineMatrix.identity) as ViewportNode;

    expect(newViewport.children, <Node>[Node.empty]);
  });

  test('Resolving Nodes removes unresolved masks', () {
    final ViewportNode viewportNode = ViewportNode(
      SvgAttributes.empty,
      width: 100,
      height: 100,
      transform: AffineMatrix.identity,
    );
    viewportNode.addChild(
      PathNode(
        Path(commands: const <PathCommand>[
          MoveToCommand(10, 10),
        ]),
        SvgAttributes(
          raw: const <String, String>{},
          fill: SvgFillAttributes(
            RefResolver(),
            color: const Color(0xFFAABBCC),
          ),
        ),
      ),
      clipResolver: (String ref) => <Path>[],
      maskResolver: (String ref) => null,
      maskId: 'DoesntMatter',
    );

    expect(viewportNode.children, contains(isA<MaskNode>()));

    final ResolvingVisitor resolver = ResolvingVisitor();
    final ViewportNode newViewport =
        viewportNode.accept(resolver, AffineMatrix.identity) as ViewportNode;

    expect(newViewport.children, contains(isA<ResolvedPathNode>()));
  });
}
