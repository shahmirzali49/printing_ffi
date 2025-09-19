/// An exception thrown when a native printing operation fails.
///
/// Contains a detailed message from the underlying native printing system
/// (e.g., CUPS or Windows Spooler).
class PrintingFfiException implements Exception {
  final String message;
  PrintingFfiException(this.message);

  @override
  String toString() => 'PrintingFfiException: $message';
}

/// Exception thrown when the helper isolate encounters a fatal error or exits unexpectedly.
class IsolateError extends Error {
  final String message;
  IsolateError(this.message);
  @override
  String toString() => 'IsolateError: $message';
}
