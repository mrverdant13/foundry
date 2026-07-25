import 'dart:convert';

import 'package:foundry_cli/src/cast_session_vars.dart';
import 'package:test/test.dart';

class _PrivateSeed {
  const _PrivateSeed(this.label);
  final String label;
}

void main() {
  group('projectEncodableCastVars', () {
    test('keeps JSON primitives, lists, and nested string-keyed maps', () {
      final projected = projectEncodableCastVars({
        'name': 'Ada',
        'count': 3,
        'enabled': true,
        'missing': null,
        'tags': <Object?>['a', 1, false, null],
        'publish': <String, Object?>{
          'host': 'example.com',
          'port': 8080,
        },
      });

      expect(
        projected,
        {
          'name': 'Ada',
          'count': 3,
          'enabled': true,
          'missing': null,
          'tags': ['a', 1, false, null],
          'publish': {
            'host': 'example.com',
            'port': 8080,
          },
        },
      );
      expect(() => jsonEncode(projected), returnsNormally);
    });

    test('omits non-encodable top-level values', () {
      final projected = projectEncodableCastVars({
        'name': 'Ada',
        'seed': const _PrivateSeed('prepare'),
      });

      expect(projected, {'name': 'Ada'});
      expect(projected.containsKey('seed'), isFalse);
    });

    test('omits non-encodable nested map entries and non-string keys', () {
      final projected = projectEncodableCastVars({
        'publish': <Object?, Object?>{
          'host': 'example.com',
          'token': const _PrivateSeed('secret'),
          1: 'ignored',
        },
      });

      expect(
        projected,
        {
          'publish': {'host': 'example.com'},
        },
      );
    });

    test('replaces non-encodable list elements with null', () {
      final projected = projectEncodableCastVars({
        'items': <Object?>['ok', const _PrivateSeed('x'), 2],
      });

      expect(projected, {
        'items': ['ok', null, 2],
      });
    });

    test('omits non-finite numbers that jsonEncode rejects', () {
      final projected = projectEncodableCastVars({
        'ok': 1.5,
        'nan': double.nan,
        'inf': double.infinity,
        'negInf': double.negativeInfinity,
        'nested': <String, Object?>{
          'ratio': double.nan,
          'port': 8080,
        },
        'items': <Object?>[1, double.infinity, 3],
      });

      expect(
        projected,
        {
          'ok': 1.5,
          'nested': {'port': 8080},
          'items': [1, null, 3],
        },
      );
      expect(() => jsonEncode(projected), returnsNormally);
    });
  });
}
