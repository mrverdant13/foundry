/// Process exit codes returned by the `foundry` command-line interface.
///
/// Mirrors the exit code contract from the product requirements: success,
/// user-facing errors (invalid input, invalid invocation, invalid mold, hook
/// failure), and unexpected internal errors.
enum FoundryExitCode {
  /// The command completed successfully.
  success(0),

  /// The command failed due to a user-facing error, such as invalid input,
  /// an invalid invocation, or another expected failure condition.
  userError(1),

  /// The command failed due to an unexpected internal error.
  internalError(2);

  const FoundryExitCode(this.code);

  /// The numeric process exit code.
  final int code;
}
