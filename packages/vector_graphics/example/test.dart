import 'dart:io';
import 'dart:convert';

void main() {
  print(base64.encode(File('flutter.png').readAsBytesSync()));
}
