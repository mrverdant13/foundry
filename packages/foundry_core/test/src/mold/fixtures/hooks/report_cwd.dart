import 'dart:io';

import 'package:foundry_core/foundry_core.dart';

/// Fixture hook that records [Directory.current] into the context.
Future<void> run(FoundryContext context) async {
  context.set('cwd', Directory.current.path);
}
