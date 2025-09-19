class CupsOptionChoiceModel {
  /// The value to be sent to CUPS (e.g., "A4", "4").
  final String choice;

  /// The human-readable text for the choice (e.g., "A4", "Landscape").
  final String text;

  CupsOptionChoiceModel({required this.choice, required this.text});
}

class CupsOptionModel {
  /// The name of the option (e.g., "media", "orientation-requested").
  final String name;

  /// The default value for this option.
  final String defaultValue;

  /// A list of supported values for this option.
  final List<CupsOptionChoiceModel> supportedValues;

  CupsOptionModel({
    required this.name,
    required this.defaultValue,
    required this.supportedValues,
  });
}

/// Represents a paper size supported by a Windows printer.
class WindowsPaperSize {
  final int id;
  final String name;
  final double widthMillimeters;
  final double heightMillimeters;

  WindowsPaperSize({
    required this.name,
    required this.id,
    required this.widthMillimeters,
    required this.heightMillimeters,
  });

  @override
  String toString() => '$name (${widthMillimeters.toStringAsFixed(1)} x ${heightMillimeters.toStringAsFixed(1)} mm)';
}

/// Represents a paper source (bin/tray) supported by a Windows printer.
class WindowsPaperSource {
  final int id;
  final String name;

  WindowsPaperSource({required this.id, required this.name});

  @override
  String toString() => name;
}

/// Represents a media type supported by a Windows printer.
class WindowsMediaType {
  final int id;
  final String name;

  WindowsMediaType({required this.id, required this.name});

  @override
  String toString() => name;
}

/// Represents a resolution supported by a Windows printer.
class WindowsResolution {
  final int xdpi;
  final int ydpi;

  WindowsResolution({required this.xdpi, required this.ydpi});

  @override
  String toString() => '$xdpi x $ydpi DPI';
}

/// Holds the capabilities (paper sizes, resolutions) of a Windows printer.
class WindowsPrinterCapabilitiesModel {
  final List<WindowsPaperSize> paperSizes;
  final List<WindowsPaperSource> paperSources;
  final List<WindowsMediaType> mediaTypes;
  final List<WindowsResolution> resolutions;
  final bool isColorSupported;
  final bool isMonochromeSupported;
  final bool supportsLandscape;

  WindowsPrinterCapabilitiesModel({
    required this.paperSizes,
    required this.paperSources,
    required this.resolutions,
    required this.mediaTypes,
    required this.isColorSupported,
    required this.isMonochromeSupported,
    required this.supportsLandscape,
  });
}
