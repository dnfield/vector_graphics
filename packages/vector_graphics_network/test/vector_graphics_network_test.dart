// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vector_graphics/vector_graphics.dart';
import 'package:vector_graphics_network/vector_graphics_network.dart';
import 'package:flutter_test/flutter_test.dart';

const String kExample = r'''
<svg height="100" width="100">
  <circle cx="50" cy="50" r="40" stroke="black" stroke-width="3" fill="red" />
</svg>
''';

void main() {
  testWidgets('Can "download" and compile a simple SVG',
      (WidgetTester tester) async {
    HttpOverrides.global = TestOverrides();

    final NetworkSvgLoader loader = NetworkSvgLoader(
      url: 'https://github.com/dnfield/vector_graphics',
      headers: <String, String>{'foo': 'bar'},
    );
    await tester.pumpWidget(VectorGraphic(loader: loader));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}

class TestOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return FakeHttpClient();
  }
}

class FakeHttpClient extends Fake implements HttpClient {
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    return FakeHttpClientRequest();
  }
}

class FakeHttpClientRequest extends Fake implements HttpClientRequest {
  @override
  Future<HttpClientResponse> close() async {
    return FakeHttpClientResponse(gzip.encode(utf8.encode(kExample)));
  }
}

class FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  FakeHttpClientResponse(this.data);

  final List<int> data;

  @override
  X509Certificate? get certificate => throw UnimplementedError();

  @override
  HttpClientResponseCompressionState get compressionState =>
      throw UnimplementedError();

  @override
  HttpConnectionInfo? get connectionInfo => throw UnimplementedError();

  @override
  int get contentLength => data.length;

  @override
  List<Cookie> get cookies => throw UnimplementedError();

  @override
  Future<Socket> detachSocket() {
    throw UnimplementedError();
  }

  @override
  HttpHeaders get headers => throw UnimplementedError();

  @override
  bool get isRedirect => throw UnimplementedError();

  @override
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return Stream<List<int>>.fromIterable(<List<int>>[data]).listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  @override
  bool get persistentConnection => throw UnimplementedError();

  @override
  String get reasonPhrase => throw UnimplementedError();

  @override
  Future<HttpClientResponse> redirect(
      [String? method, Uri? url, bool? followLoops]) {
    throw UnimplementedError();
  }

  @override
  List<RedirectInfo> get redirects => throw UnimplementedError();

  @override
  int get statusCode => HttpStatus.ok;
}
