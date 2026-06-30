import 'package:foundry_core/src/mold/mold_issue.dart';
import 'package:test/test.dart';

void main() {
  test('MoldIssue toString includes severity, path, and message', () {
    const issue = MoldIssue(
      severity: MoldIssueSeverity.error,
      path: 'mold.yaml',
      message: 'Something went wrong.',
    );

    expect(issue.toString(), 'error [mold.yaml]: Something went wrong.');
  });

  test('MoldLoadException toString lists all issues', () {
    const exception = MoldLoadException([
      MoldIssue(
        severity: MoldIssueSeverity.error,
        path: 'mold.yaml',
        message: 'First issue.',
      ),
      MoldIssue(
        severity: MoldIssueSeverity.warning,
        path: 'variables.dart',
        message: 'Second issue.',
      ),
    ]);

    expect(
      exception.toString(),
      'Failed to load mold:\n'
      '  error [mold.yaml]: First issue.\n'
      '  warning [variables.dart]: Second issue.',
    );
  });
}
