import 'dart:io';

import 'package:foundry_cli/foundry_cli.dart';

/// Entry point for the `foundry` executable.
Future<void> main(List<String> args) async {
  final exitCode = await FoundryCommandRunner().run(args);
  exit(exitCode);
}
