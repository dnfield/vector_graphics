import 'package:test/test.dart';
import 'package:vector_graphics_compiler/src/svg/node.dart';
import 'package:vector_graphics_compiler/src/svg/clipping_optimizer.dart';
import 'package:vector_graphics_compiler/src/svg/parser.dart';
import 'package:vector_graphics_compiler/src/svg/resolver.dart';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart';

Future<Node> parseAndResolve(String source) async {
  final Node node = await parseToNodeTree(source);
  final ResolvingVisitor visitor = ResolvingVisitor();
  return node.accept(visitor, AffineMatrix.identity);
}

List<T> queryChildren<T extends Node>(Node node) {
  final List<T> children = <T>[];
  void visitor(Node child) {
    if (child is T) {
      children.add(child);
    }
    child.visitChildren(visitor);
  }

  node.visitChildren(visitor);
  return children;
}

const String xmlString =
    ''' <svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64" fill="none"><mask id="a" style="mask-type:alpha" maskUnits="userSpaceOnUse" x="0" y="0" width="64" height="64"><circle cx="32" cy="32" r="32" fill="#C4C4C4"/></mask><g clip-path="url(#clip0_2630_58398)" mask="url(#a)"><path d="M65.564 0H-3.041v65.807h68.605V0z" fill="#669DF6"/><path d="M69.185-14.857h-77.29v65.143h77.29v-65.143z" fill="#D2E3FC"/><path d="M21.792 2.642l-24.045.056.124 51.288 24.028-.039-.107-51.305z" fill="#FBBC04"/><path d="M1.931 10.286a1.543 1.543 0 013.086-.008v2.26a1.543 1.543 0 01-3.086.007v-2.26zm1.571 12.292a1.545 1.545 0 01-1.544-1.537l-.006-2.26a1.543 1.543 0 013.086-.006v2.26a1.545 1.545 0 01-1.536 1.543zM8.33 10.27a1.543 1.543 0 013.086-.007l.006 2.26a1.543 1.543 0 01-3.086.006l-.006-2.26zM9.9 22.563a1.546 1.546 0 01-1.545-1.534v-2.261a1.543 1.543 0 113.086-.007v2.26a1.546 1.546 0 01-1.54 1.542zm4.828-12.308a1.544 1.544 0 012.13-1.431 1.542 1.542 0 01.956 1.423v2.26a1.54 1.54 0 01-1.54 1.546 1.542 1.542 0 01-1.546-1.539v-2.26zm1.57 12.292a1.545 1.545 0 01-1.544-1.537l-.005-2.26a1.544 1.544 0 012.63-1.096 1.542 1.542 0 01.455 1.09v2.26a1.545 1.545 0 01-1.536 1.543zM1.959 27.278a1.543 1.543 0 113.086-.007v2.26a1.543 1.543 0 11-3.086.007v-2.26zM3.53 39.571a1.544 1.544 0 01-1.545-1.537l-.006-2.263a1.543 1.543 0 113.086-.008v2.261a1.545 1.545 0 01-1.536 1.547zm4.826-12.308a1.543 1.543 0 113.086-.008v2.26a1.542 1.542 0 01-3.086.007v-2.26zm1.571 12.292a1.545 1.545 0 01-1.544-1.536v-2.26a1.543 1.543 0 113.086-.007l.005 2.26a1.544 1.544 0 01-1.547 1.543zm4.828-12.308a1.542 1.542 0 113.086-.007l.006 2.26a1.543 1.543 0 11-3.086.007l-.006-2.26zm1.571 12.296a1.544 1.544 0 01-1.544-1.537v-2.26a1.543 1.543 0 013.085-.008l.006 2.26a1.546 1.546 0 01-1.547 1.545z" fill="#FDE293"/><path d="M22.783 5.54a1.077 1.077 0 001.05-1.306L22.83-.393a1.387 1.387 0 00-1.325-.978l-23.456.037a1.39 1.39 0 00-1.322.98l-.989 4.633A1.077 1.077 0 00-3.208 5.58l25.99-.042z" fill="#F9AB00"/><path d="M43.051 53.973h65.009l.046-36.144a2.921 2.921 0 00-2.924-2.924l-59.16.404a2.924 2.924 0 00-2.925 2.923l-.046 35.74z" fill="#81C995"/><path d="M62.483 15.148h3.275l-.248 7.893c-.01.057-.019.114-.035.17v.014c-.03.11-.071.216-.12.319a1.744 1.744 0 01-2.244.895 1.989 1.989 0 01-1.282-2.136l.654-7.155zm-21.512 7.023v-.013c.01-.059.029-.115.043-.167l2.138-6.838h3.174l-2.124 7.967h-.006a1.7 1.7 0 01-1.581 1.29 1.793 1.793 0 01-1.674-1.896c0-.115.01-.23.03-.343zm12.132-7.023h3.187l-1.704 8.1h-.006a1.62 1.62 0 01-1.581 1.29 1.793 1.793 0 01-1.675-1.891c.002-.077.009-.153.021-.229l-.203.836h-.006a1.703 1.703 0 01-1.582 1.289 1.792 1.792 0 01-1.668-1.897c0-.113.01-.224.03-.335l-.23.937h-.006a1.704 1.704 0 01-1.582 1.29 1.792 1.792 0 01-1.674-1.891c.001-.115.011-.23.03-.343v-.014c.009-.058.027-.114.04-.168l1.84-6.971h6.776l-.007-.003z" fill="#EA4335"/><path d="M62.483 15.126l-.718 7.885a1.715 1.715 0 01-1.7 1.53 1.654 1.654 0 01-1.852-1.667 2.581 2.581 0 010-.343l-.086.53-.02.15a1.696 1.696 0 01-1.546 1.318 1.758 1.758 0 01-1.79-1.752 2.31 2.31 0 01.01-.343v-.013c.007-.058.017-.115.03-.172l1.486-7.096 3.126-.022 3.06-.005z" fill="#EA4335"/><path d="M62.483 15.148h3.275l-.248 7.893c-.01.057-.019.114-.035.17v.014c-.03.11-.071.216-.12.319a1.745 1.745 0 01-2.244.896 1.99 1.99 0 01-1.276-2.137l.648-7.155zm-16.156 0h-3.174l-2.138 6.837c-.014.055-.032.114-.042.167v.015c-.02.113-.03.228-.031.343a1.794 1.794 0 001.675 1.89 1.7 1.7 0 001.58-1.29h.008l2.122-7.962zm6.776 0h-3.419l-1.73 6.97a1.671 1.671 0 00-.042.169v.014a2.13 2.13 0 00-.03.343 1.792 1.792 0 001.673 1.89 1.704 1.704 0 001.582-1.29h.006l1.96-8.096z" fill="#81CA95"/><path d="M49.685 15.148h-3.358l-1.839 6.97c-.014.057-.032.115-.041.169v.014a2.264 2.264 0 00-.03.343 1.792 1.792 0 001.675 1.89 1.703 1.703 0 001.581-1.29h.007l2.005-8.096z" fill="#35A853"/><path d="M59.416 15.126l-3.126.021-1.485 7.096a1.716 1.716 0 00-.031.172v.014a2.308 2.308 0 00-.01.342 1.759 1.759 0 001.79 1.752 1.696 1.696 0 001.545-1.317l.021-.151 1.296-7.93z" fill="#81CA95"/><path d="M62.483 15.126h-3.067l-1.182 7.21a1.71 1.71 0 00-.025.171v.015a2.515 2.515 0 000 .343 1.654 1.654 0 001.853 1.666 1.714 1.714 0 001.7-1.529l.721-7.876zm-6.193.022h-3.187l-1.705 6.97c-.015.057-.032.115-.043.169v.014a1.97 1.97 0 00-.03.343A1.793 1.793 0 0053 24.534a1.617 1.617 0 001.58-1.29h.008l1.702-8.096z" fill="#35A853"/><path d="M40.94 26.533h68.963v-4.221H40.941v4.22z" fill="#35A853"/><path d="M54.314 42.22l3.623.005a1.558 1.558 0 001.557-1.552l.009-5.845a1.559 1.559 0 00-1.552-1.556h-3.622a1.561 1.561 0 00-1.558 1.552l-.009 5.845a1.55 1.55 0 001.552 1.55z" fill="#A8DAB5"/><path d="M46.155 53.943l-25.27.04-.04-26.081a2.001 2.001 0 011.993-1.998l21.28-.034a2.001 2.001 0 011.997 1.992l.04 26.08z" fill="#AFCBFA"/><path d="M22.838 25.904a2.006 2.006 0 00-1.91 1.416l-2.065 7.9a3.656 3.656 0 107.314-.01l1.199-9.313-4.538.007z" fill="#669DF7"/><path d="M46.032 27.28a2.008 2.008 0 00-1.918-1.41l-4.538.008 1.229 9.307a3.656 3.656 0 107.314-.011l-2.087-7.894zm-12.554-1.393l-6.102.01-1.199 9.312a3.66 3.66 0 003.664 3.651 3.66 3.66 0 003.65-3.663l-.013-9.31z" fill="#E8F0FD"/><path d="M33.478 25.887l.015 9.31a3.658 3.658 0 007.314-.012l-1.229-9.307-6.1.009z" fill="#669DF7"/><path d="M38.03 53.973l-9.02.013-.015-10.026a1.652 1.652 0 011.65-1.655l5.715-.009a1.654 1.654 0 011.656 1.65l.015 10.027z" fill="#E8F0FE"/><path d="M27.578 11.599h-.006l.052.124.025.061 4.552 10.938a.868.868 0 001.6-.008l4.412-10.873a5.75 5.75 0 00.496-2.47 5.763 5.763 0 00-11.526.143 5.74 5.74 0 00.395 2.085z" fill="#EA4335"/><path d="M32.946 10.998a1.787 1.787 0 100-3.575 1.787 1.787 0 000 3.575z" fill="#A50E0E"/></g><defs><clipPath id="clip0_2630_58398"><path fill="#fff" d="M0 0h64v64H0z"/></clipPath></defs></svg> ''';

void main() {
  setUpAll(() {
    if (!initializePathOpsFromFlutterCache()) {
      fail('error in setup');
    }
  });
  test('Only resolve ClipNode if .clips has one PathNode', () async {
    final Node node = await parseAndResolve(
        ''' <svg width="200px" height="200x" viewBox="0 0 200 200">
  <defs>
    <clipPath id="a">
      <rect x="0" y="0" width="200" height="100" />
    </clipPath>
  </defs>

  <circle cx="100" cy="100" r="100" clip-path="url(#a)" fill="white" />
</svg>''');

    final ClippingOptimizer visitor = ClippingOptimizer();
    final Node newNode = visitor.apply(node);

    final List<ResolvedClipNode> clipNodesNew =
        queryChildren<ResolvedClipNode>(newNode);

    expect(clipNodesNew.length, 0);
  });

  test(
      "Don't resolve a ClipNode if one of the PathNodes it's applied to has stroke.width set",
      () async {
    final Node node = await parseAndResolve(''' <svg width="10" height="10">
  <clipPath id="clip0">
    <path d="M2 3h7.9v2H1" />
  </clipPath>
  <path d="M2, 5L8,6" stroke="black" stroke-linecap="round" stroke-width="2" clip-path="url(#clip0)" />
</svg>''');

    final ClippingOptimizer visitor = ClippingOptimizer();
    final Node newNode = visitor.apply(node);

    final List<ResolvedClipNode> clipNodesNew =
        queryChildren<ResolvedClipNode>(newNode);

    expect(clipNodesNew.length, 1);
  });

  test("Don't resolve ClipNode if intersection of Clip and Path is empty",
      () async {
    final Node node = await parseAndResolve(
        '''<svg width="200px" height="200x" viewBox="0 0 200 200">
  <defs>
    <clipPath id="a">
      <rect x="300" y="300" width="200" height="100" />
    </clipPath>
  </defs>
  <path clip-path="url(#a)" d="M0 0 z"/>
</svg>

''');
    final ClippingOptimizer visitor = ClippingOptimizer();
    final Node newNode = visitor.apply(node);

    final List<ResolvedClipNode> clipNodesNew =
        queryChildren<ResolvedClipNode>(newNode);

    expect(clipNodesNew.length, 1);
  });

  test('ParentNode and PathNode count should stay the same', () async {
    final Node node = await parseAndResolve(xmlString);

    final List<ResolvedPathNode> pathNodesOld =
        queryChildren<ResolvedPathNode>(node);
    final List<ParentNode> parentNodesOld = queryChildren<ParentNode>(node);

    final ClippingOptimizer visitor = ClippingOptimizer();
    final Node newNode = visitor.apply(node);

    final List<ResolvedPathNode> pathNodesNew =
        queryChildren<ResolvedPathNode>(newNode);
    final List<ParentNode> parentNodesNew = queryChildren<ParentNode>(newNode);

    expect(pathNodesOld.length, pathNodesNew.length);
    expect(parentNodesOld.length, parentNodesNew.length);
  });
}
