import 'dart:convert';
// This lint is currently broken for packages that say they support web.
// ignore: avoid_web_libraries_in_flutter
import 'dart:html';
import 'dart:typed_data';

/// Fetches an HTTP resource from the specified [url] using the specified [headers].
Future<Uint8List> httpGet(Uri uri, {Map<String, String>? headers}) async {
  final HttpRequest request = await HttpRequest.request(
    uri.toString(),
    requestHeaders: headers,
  );
  return Uint8List.fromList(utf8.encode(request.responseText!));
}
