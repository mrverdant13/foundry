import 'package:foundry_core/src/rendering/template_liquid_filters.dart';
import 'package:liquify/liquify.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(ensureFoundryLiquidFiltersRegistered);

  group('foundry liquid filters', () {
    test('snake_case converts to snake case', () {
      final rendered = Template.parse(
        '{{ name | snake_case }}',
        data: {'name': 'My Project'},
      ).render();

      expect(rendered, 'my_project');
    });

    test('pascal_case converts to pascal case', () {
      final rendered = Template.parse(
        '{{ name | pascal_case }}',
        data: {'name': 'my project'},
      ).render();

      expect(rendered, 'MyProject');
    });

    test('camel_case converts to camel case', () {
      final rendered = Template.parse(
        '{{ name | camel_case }}',
        data: {'name': 'my project'},
      ).render();

      expect(rendered, 'myProject');
    });

    test('constant_case converts to constant case', () {
      final rendered = Template.parse(
        '{{ name | constant_case }}',
        data: {'name': 'my project'},
      ).render();

      expect(rendered, 'MY_PROJECT');
    });

    test('is idempotent to register repeatedly', () {
      ensureFoundryLiquidFiltersRegistered();
      ensureFoundryLiquidFiltersRegistered();

      final rendered = Template.parse(
        '{{ name | snake_case }}',
        data: {'name': 'my project'},
      ).render();

      expect(rendered, 'my_project');
    });
  });
}
