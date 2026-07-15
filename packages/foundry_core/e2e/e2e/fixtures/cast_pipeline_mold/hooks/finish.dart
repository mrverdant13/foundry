import 'dart:io';

import 'package:foundry_core/foundry_core.dart';

Future<void> run(FoundryContext context) async {
  await File('cast_complete.txt').writeAsString('finished\n');
}
