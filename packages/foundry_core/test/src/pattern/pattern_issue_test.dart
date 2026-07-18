import 'package:foundry_core/foundry_core.dart';
import 'package:test/test.dart';

void main() {
  test('PatternIssue toString includes severity, path, and message', () {
    const issue = PatternIssue(
      severity: PatternIssueSeverity.error,
      path: '.foundry/pattern.yaml',
      message: 'Something went wrong.',
    );

    expect(
      issue.toString(),
      'error [.foundry/pattern.yaml]: Something went wrong.',
    );
  });

  test('PatternMarkerException toString lists all issues', () {
    const exception = PatternMarkerException([
      PatternIssue(
        severity: PatternIssueSeverity.error,
        path: '.foundry/pattern.yaml',
        message: 'First issue.',
      ),
      PatternIssue(
        severity: PatternIssueSeverity.warning,
        path: '.foundry/pattern.yaml',
        message: 'Second issue.',
      ),
    ]);

    expect(
      exception.toString(),
      'Failed to parse pattern marker:\n'
      '  error [.foundry/pattern.yaml]: First issue.\n'
      '  warning [.foundry/pattern.yaml]: Second issue.',
    );
  });
}
