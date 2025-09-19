/// The result of opening the printer properties dialog.
enum PrinterPropertiesResult {
  /// An error occurred, or the dialog could not be opened.
  error,

  /// The user clicked "OK" and changes were applied (Windows only).
  /// On macOS/Linux, this indicates the browser command was dispatched successfully.
  ok,

  /// The user clicked "Cancel" (Windows only).
  cancel,
}
