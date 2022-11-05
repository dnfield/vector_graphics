import 'dart:io';

import 'package:pubspec_parse/pubspec_parse.dart';
import 'package:path/path.dart' as path;

void main(List<String> args) {
  final Pubspec compiler = getPubspec(Package.compiler);
  final Pubspec codec = getPubspec(Package.codec);
  final Pubspec runtime = getPubspec(Package.runtime);

  bool valid = true;
  if (compiler.version != codec.version) {
    print(
        'Compiler ${compiler.version} is different from Codec ${codec.version}');
    valid = false;
  }
  if (runtime.version != codec.version) {
    print(
        'Runtime ${runtime.version} is different from Codec ${codec.version}');
    valid = false;
  }

  valid = validateDeps(compiler, codec);
  valid = validateDeps(runtime, codec);

  if (!valid) {
    print('Validations failed');
    exit(1);
  }

  print('Checks successful.');

  if (args.contains('--publish')) {
    for (final Package package in Package.values) {
      print('Publishing ${package.name}...');
      ProcessResult result = Process.runSync(
        'dart',
        <String>['pub', 'publish', '-f'],
        workingDirectory: getPath(package),
      );

      if (result.exitCode != 0) {
        print(result.stdout);
        print(result.stderr);
        print('Failed, exiting.');
        exit(2);
      }
    }
  }
}

bool validateDeps(Pubspec source, Pubspec codec) {
  if (!source.dependencies.containsKey(packages[Package.codec])) {
    print(
        'Expected ${source.name} to have a dependnecy on codec, but none found.');
    return false;
  }

  if (source.dependencies.containsKey(packages[Package.runtime])) {
    print('${source.name} must not depend on runtime.');
    return false;
  }
  if (source.dependencies.containsKey(packages[Package.compiler])) {
    print('${source.name} must not depend on compiler.');
    return false;
  }

  final HostedDependency compilerCodec =
      source.dependencies[packages[Package.codec]] as HostedDependency;

  if (compilerCodec.version != codec.version) {
    print(
        '${source.name} depends on codec version ${compilerCodec.version}, should be ${codec.version}');
    return false;
  }
  return true;
}

/// Ordered by publication.
enum Package {
  codec,
  runtime,
  compiler,
}

const Map<Package, String> packages = <Package, String>{
  Package.codec: 'vector_graphics_codec',
  Package.compiler: 'vector_graphics_compiler',
  Package.runtime: 'vector_graphics',
};

Pubspec getPubspec(Package package) {
  final String packagePath = getPath(package);
  return Pubspec.parse(
      File(path.join(packagePath, 'pubspec.yaml')).readAsStringSync());
}

String getPath(Package package) {
  final String packagesPath = path.join(
      path.dirname(Platform.script.path), '..', '..', '..', 'packages');

  return path.join(packagesPath, packages[package]);
}
