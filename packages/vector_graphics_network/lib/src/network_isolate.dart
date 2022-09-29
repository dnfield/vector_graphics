// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:vector_graphics_compiler/vector_graphics_compiler.dart';

/// A background isolate that fetches and decodes SVGs.
class NetworkIsolate {
  NetworkIsolate._();

  late final SendPort _sendPort;
  final Completer<void> _ready = Completer<void>();

  int _nextId = 0;
  final Map<int, _PendingNetworkRequest> _pending =
      <int, _PendingNetworkRequest>{};

  /// Create a new [NetworkIsolate].
  static Future<NetworkIsolate> create() async {
    final NetworkIsolate networkIsolate = NetworkIsolate._();
    final RawReceivePort port = RawReceivePort();
    port.handler = networkIsolate._onResponse;

    await Isolate.spawn(
      _networkIsolateMain,
      _SpawnArgs(port.sendPort),
    );
    await networkIsolate._ready.future;
    // Do not access this field directly; use [_httpClient] instead.
    // We set `autoUncompress` to false to ensure that we can trust the value of
    // the `Content-Length` HTTP header. We automatically uncompress the content
    // in our call to [consolidateHttpClientResponseBytes].
    final HttpClient httpClient = HttpClient()..autoUncompress = false;
    networkIsolate._sendPort.send(httpClient);
    return networkIsolate;
  }

  /// Return the compiled bytes for the SVG at [url].
  Future<ByteData> getUrl(
    String url,
    Map<String, String>? headers,
  ) async {
    final int id = _nextId;
    _nextId += 1;

    final _PendingNetworkRequest request = _PendingNetworkRequest();
    _pending[id] = request;

    try {
      _sendPort.send(_GetUrl(url, headers, id));
      return await request.completer.future;
    } finally {
      _pending.remove(id);
    }
  }

  void _onResponse(Object? data) {
    if (data is SendPort) {
      _sendPort = data;
      _ready.complete();
    } else if (data is _ExceptionEvent) {
      _pending[data.id]!.completer.completeError(data.exception);
    } else if (data is _ResponseEvent) {
      _pending[data.id]!
          .completer
          .complete(data.data.materialize().asByteData());
    } else {
      assert(false, 'Unexpected NetworkIsolate response: $data');
    }
  }

  static late HttpClient _httpClient;

  static void _networkIsolateMain(_SpawnArgs args) {
    final RawReceivePort port = RawReceivePort();
    port.handler = (Object? request) {
      if (request is HttpClient) {
        _httpClient = request;
      } else if (request is _GetUrl) {
        _getUrl(_httpClient, request.url, request.id, request.headers,
            args.sendPort);
      } else {
        assert(false, 'Unexpected NetworkIsolate request: $request');
      }
    };
    args.sendPort.send(port.sendPort);
  }

  static Future<void> _getUrl(HttpClient client, String url, int id,
      Map<String, String>? headers, SendPort sendPort) async {
    try {
      final Uri resolved = Uri.base.resolve(url);
      final HttpClientRequest request = await client.getUrl(resolved);
      headers?.forEach(request.headers.add);
      final HttpClientResponse response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        // The network may be only temporarily unavailable, or the file will be
        // added on the server later. Avoid having future calls to resolve
        // fail to check the network again.
        sendPort
            .send(_ExceptionEvent(Exception('Failed to download $url'), id));
        await response.drain<List<int>>(<int>[]);
        return;
      }
      final Uint8List bytes = await consolidateHttpClientResponseBytes(
        response,
      );
      final Uint8List compiledBytes = await encodeSvg(
        xml: utf8.decode(bytes),
        debugName: url,
        enableClippingOptimizer: false,
        enableMaskingOptimizer: false,
        enableOverdrawOptimizer: false,
      );
      sendPort.send(_ResponseEvent(
          TransferableTypedData.fromList(<Uint8List>[compiledBytes]), id));
    } catch (err) {
      sendPort.send(_ExceptionEvent(err, id));
    }
  }
}

class _PendingNetworkRequest {
  final Completer<ByteData> completer = Completer<ByteData>();
}

class _ResponseEvent {
  const _ResponseEvent(this.data, this.id);

  final int id;
  final TransferableTypedData data;
}

class _ExceptionEvent {
  _ExceptionEvent(this.exception, this.id);

  final int id;
  final Object exception;
}

class _SpawnArgs {
  _SpawnArgs(this.sendPort);

  final SendPort sendPort;
}

class _GetUrl {
  const _GetUrl(this.url, this.headers, this.id);

  final String url;
  final Map<String, String>? headers;
  final int id;
}
