import 'package:liquify/liquify.dart';
import 'package:recase/recase.dart';

bool _registered = false;

/// Registers the case-conversion Liquid filters available to mold templates.
///
/// Idempotent — safe to call before every render. Filter names mirror common
/// code-generation case transforms (comparable to Mason's mustache case
/// transformers): `snake_case`, `pascal_case`, `camel_case`, `constant_case`,
/// `dot_case`, `param_case`, `path_case`, `header_case`, `title_case`, and
/// `sentence_case`.
void ensureFoundryLiquidFiltersRegistered() {
  if (_registered) return;
  _registered = true;

  _registerCaseFilter('snake_case', (recase) => recase.snakeCase);
  _registerCaseFilter('pascal_case', (recase) => recase.pascalCase);
  _registerCaseFilter('camel_case', (recase) => recase.camelCase);
  _registerCaseFilter('constant_case', (recase) => recase.constantCase);
  _registerCaseFilter('dot_case', (recase) => recase.dotCase);
  _registerCaseFilter('param_case', (recase) => recase.paramCase);
  _registerCaseFilter('path_case', (recase) => recase.pathCase);
  _registerCaseFilter('header_case', (recase) => recase.headerCase);
  _registerCaseFilter('title_case', (recase) => recase.titleCase);
  _registerCaseFilter('sentence_case', (recase) => recase.sentenceCase);
}

void _registerCaseFilter(
  String name,
  String Function(ReCase recase) transform,
) {
  FilterRegistry.register(
    name,
    (value, arguments, namedArguments) => transform(ReCase('$value')),
  );
}
