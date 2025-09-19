
class Printer {
  /// The platform specific printer identification (e.g., device URI).
  final String url;

  /// The display name of the printer.
  final String name;

  /// The printer model.
  final String? model;

  /// The physical location of the printer.
  final String? location;

  /// A user comment about the printer.
  final String? comment;

  /// Whether this is the default printer on the system.
  final bool isDefault;

  /// Whether the printer is available for printing (e.g., not offline or stopped).
  final bool isAvailable;

  /// The raw platform-specific state value.
  final int state;

  Printer({
    required this.url,
    required this.name,
    this.model,
    this.location,
    this.comment,
    required this.isDefault,
    required this.isAvailable,
    required this.state,
  });
}
