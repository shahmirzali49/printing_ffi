import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'printing_ffi_bindings_generated.dart';

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

/// Represents the status of a print job.
enum PrintJobStatus {
  // Common states
  pending('Pending'),
  processing('Processing'),
  completed('Completed'),
  canceled('Canceled'),
  aborted('Aborted'),
  error('Error'),
  unknown('Unknown'),

  // Platform-specific or nuanced states
  held('Held'), // CUPS
  stopped('Stopped'), // CUPS
  paused('Paused'), // Windows
  spooling('Spooling'), // Windows
  deleting('Deleting'), // Windows
  restarting('Restarting'), // Windows
  offline('Offline'), // Windows
  paperOut('Paper Out'), // Windows
  userIntervention('User Intervention'); // Windows

  const PrintJobStatus(this.description);

  /// A user-friendly description of the status.
  final String description;

  /// Creates a [PrintJobStatus] from a raw platform-specific integer value.
  static PrintJobStatus fromRaw(int status) {
    if (Platform.isMacOS || Platform.isLinux) {
      // CUPS IPP Job States
      return switch (status) {
        3 => PrintJobStatus.pending, // IPP_JOB_PENDING
        4 => PrintJobStatus.held, // IPP_JOB_HELD
        5 => PrintJobStatus.processing, // IPP_JOB_PROCESSING
        6 => PrintJobStatus.stopped, // IPP_JOB_STOPPED
        7 => PrintJobStatus.canceled, // IPP_JOB_CANCELED
        8 => PrintJobStatus.aborted, // IPP_JOB_ABORTED
        9 => PrintJobStatus.completed, // IPP_JOB_COMPLETED
        _ => PrintJobStatus.unknown,
      };
    }

    if (Platform.isWindows) {
      // Windows Job Status bit flags. Order determines priority.
      if ((status & 0x00000002) != 0) return PrintJobStatus.error; // JOB_STATUS_ERROR
      if ((status & 0x00000400) != 0) return PrintJobStatus.userIntervention; // JOB_STATUS_USER_INTERVENTION
      if ((status & 0x00000040) != 0) return PrintJobStatus.paperOut; // JOB_STATUS_PAPEROUT
      if ((status & 0x00000020) != 0) return PrintJobStatus.offline; // JOB_STATUS_OFFLINE
      if ((status & 0x00000001) != 0) return PrintJobStatus.paused; // JOB_STATUS_PAUSED
      if ((status & 0x00000100) != 0) return PrintJobStatus.canceled; // JOB_STATUS_DELETED
      if ((status & 0x00000004) != 0) return PrintJobStatus.deleting; // JOB_STATUS_DELETING
      if ((status & 0x00000800) != 0) return PrintJobStatus.restarting; // JOB_STATUS_RESTART
      if ((status & 0x00000010) != 0) return PrintJobStatus.processing; // JOB_STATUS_PRINTING
      if ((status & 0x00000008) != 0) return PrintJobStatus.spooling; // JOB_STATUS_SPOOLING
      if ((status & 0x00001000) != 0) return PrintJobStatus.completed; // JOB_STATUS_COMPLETE
      if ((status & 0x00000080) != 0) return PrintJobStatus.completed; // JOB_STATUS_PRINTED
      if (status == 0) return PrintJobStatus.pending; // No flags, likely queued.

      return PrintJobStatus.unknown;
    }

    return PrintJobStatus.unknown;
  }
}

class PrintJob {
  final int id;
  final String title;

  /// The raw platform-specific status value.
  final int rawStatus;

  /// The parsed, cross-platform status.
  final PrintJobStatus status;

  PrintJob(this.id, this.title, this.rawStatus) : status = PrintJobStatus.fromRaw(rawStatus);

  /// A user-friendly description of the status.
  String get statusDescription => status.description;
}

/// Defines the scaling behavior for PDF printing on Windows.
sealed class PdfPrintScaling {
  /// The integer value passed to the native code.
  final int nativeValue;
  const PdfPrintScaling(this.nativeValue);

  /// **Fit to Printable Area**
  ///
  /// Scales the page (up or down) to fit perfectly within the printer's
  /// **printable area**, maintaining the aspect ratio. The printable area is
  /// the physical paper size minus any unprintable hardware margins.
  ///
  /// This is the safest scaling option to ensure no content is ever clipped.
  static const PdfPrintScaling fitToPrintableArea = _PdfPrintScalingValue(0);

  @Deprecated('Use fitToPrintableArea instead. This will be removed in a future version.')
  static const PdfPrintScaling fitPage = fitToPrintableArea;

  /// **Actual Size**
  ///
  /// Prints the page without any scaling (100% scale). The content is centered
  /// on the paper. If the page is larger than the printable area, the content
  /// will be cropped.
  static const PdfPrintScaling actualSize = _PdfPrintScalingValue(1);

  /// **Shrink to Fit**
  ///
  /// A conditional scaling mode:
  /// - If the page at its actual size is **larger** than the printable area, it
  ///   is scaled down to fit (behaving like `fitToPrintableArea`).
  /// - If the page at its actual size is **smaller** than or equal to the
  ///   printable area, it is printed without scaling (behaving like `actualSize`).
  ///
  /// This is useful for ensuring large documents are not cropped while preserving
  /// the original size of smaller documents.
  static const PdfPrintScaling shrinkToFit = _PdfPrintScalingValue(2);

  /// **Fit to Paper**
  ///
  /// Scales the page (up or down) to fit the **entire physical paper size**,
  /// maintaining the aspect ratio.
  ///
  /// **Warning:** Content near the edges of the PDF page may be clipped by the
  /// printer's unprintable hardware margins. This mode is different from
  /// `fitToPrintableArea`, which respects these margins.
  static const PdfPrintScaling fitToPaper = _PdfPrintScalingValue(3);

  /// **Custom Scale**
  ///
  /// Applies a custom scaling factor to the page.
  ///
  /// - [scale]: The scaling factor (e.g., 1.0 for 100%, 0.5 for 50%). Must be a positive number.
  const factory PdfPrintScaling.custom(double scale) = _PdfPrintScalingCustom;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! PdfPrintScaling || runtimeType != other.runtimeType) return false;
    if (other is _PdfPrintScalingCustom && this is _PdfPrintScalingCustom) {
      return (this as _PdfPrintScalingCustom).scale == other.scale;
    }
    return nativeValue == other.nativeValue;
  }

  @override
  int get hashCode => nativeValue.hashCode;
}

class _PdfPrintScalingValue extends PdfPrintScaling {
  const _PdfPrintScalingValue(super.nativeValue);
}

final class _PdfPrintScalingCustom extends PdfPrintScaling {
  const _PdfPrintScalingCustom(this.scale) : super(4);

  final double scale;

  @override
  bool operator ==(Object other) => identical(this, other) || other is _PdfPrintScalingCustom && runtimeType == other.runtimeType && scale == other.scale;

  @override
  int get hashCode => Object.hash(nativeValue, scale);
}

/// Defines the orientation for printing on Windows.
enum WindowsOrientation {
  /// Portrait orientation (short edge is top).
  portrait(1),

  /// Landscape orientation (long edge is top).
  landscape(2);

  const WindowsOrientation(this.value);
  final int value;
}

/// Defines the color mode for printing.
enum ColorMode { monochrome, color }

/// Defines the quality for printing.
///
/// These correspond to standard driver settings. `normal` is equivalent to
/// the driver's default medium quality.
enum PrintQuality { draft, low, normal, high }

/// Defines the duplex printing mode.
enum DuplexMode {
  /// Print on one side only (single-sided).
  singleSided,

  /// Print on both sides, flip on long edge (book-style).
  /// This is the standard duplex mode for documents like books.
  duplexLongEdge,

  /// Print on both sides, flip on short edge (notepad-style).
  /// This is used for documents that are bound along the short edge.
  duplexShortEdge,
}

/// Defines the alignment for PDF printing on Windows.
enum PdfPrintAlignment {
  center,
  left,
  right,
  top,
  bottom,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

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

/// Represents a generic printing option to be passed to print functions.
sealed class PrintOption {
  const PrintOption();
}

/// A Windows-specific option to set the paper size by its ID.
/// The ID can be obtained from [WindowsPrinterCapabilities].
class WindowsPaperSizeOption extends PrintOption {
  final int id;
  const WindowsPaperSizeOption(this.id);
}

/// A Windows-specific option to set the paper source (tray/bin) by its ID.
/// The ID can be obtained from [WindowsPrinterCapabilities].
class WindowsPaperSourceOption extends PrintOption {
  final int id;
  const WindowsPaperSourceOption(this.id);
}

/// An option to set the page orientation.
class OrientationOption extends PrintOption {
  final WindowsOrientation orientation;
  const OrientationOption(this.orientation);
}

/// An option to set the color mode (e.g., monochrome or color).
class ColorModeOption extends PrintOption {
  final ColorMode mode;
  const ColorModeOption(this.mode);
}

/// An option to set the print quality.
class PrintQualityOption extends PrintOption {
  final PrintQuality quality;
  const PrintQualityOption(this.quality);
}

/// A Windows-specific option to set the media type (e.g., "Plain Paper", "Glossy Photo") by its ID.
/// The ID can be obtained from [WindowsPrinterCapabilities].
class WindowsMediaTypeOption extends PrintOption {
  final int id;
  const WindowsMediaTypeOption(this.id);
}

/// A generic CUPS option, represented as a key-value pair.
/// The available options can be discovered using [getSupportedCupsOptions].
class GenericCupsOption extends PrintOption {
  final String name;
  final String value;
  const GenericCupsOption(this.name, this.value);
}

/// A Windows-specific option to set the alignment of the printed content.
class AlignmentOption extends PrintOption {
  final PdfPrintAlignment alignment;
  const AlignmentOption(this.alignment);
}

/// An option to set the collate mode for multiple copies.
///
/// For duplex printing (front/back), this controls how multiple copies are arranged:
///
/// **When true (collated)**: Pages are grouped by copy
/// - Copy 1: Page 1, Page 2, Page 3, Page 4, Page 5, Page 6
/// - Copy 2: Page 1, Page 2, Page 3, Page 4, Page 5, Page 6
///
/// **When false (non-collated)**: Pages are grouped by page number
/// - All copies of Page 1, then all copies of Page 2, etc.
/// - Page 1, Page 1, Page 2, Page 2, Page 3, Page 3, Page 4, Page 4, Page 5, Page 5, Page 6, Page 6
///
/// This is particularly useful for duplex printing where you want complete copies
/// to be printed together rather than all copies of each page.
class CollateOption extends PrintOption {
  final bool collate;
  const CollateOption(this.collate);
}

/// An option to set the duplex printing mode.
///
/// This controls whether and how pages are printed on both sides of the paper:
///
/// - [DuplexMode.singleSided]: Print on one side only
/// - [DuplexMode.duplexLongEdge]: Print on both sides, flip on long edge (book-style)
/// - [DuplexMode.duplexShortEdge]: Print on both sides, flip on short edge (notepad-style)
///
/// Note: The actual duplex printing depends on the printer's capabilities.
/// If the printer doesn't support duplex printing, single-sided printing will be used.
class DuplexOption extends PrintOption {
  final DuplexMode mode;
  const DuplexOption(this.mode);
}

class CupsOptionChoice {
  /// The value to be sent to CUPS (e.g., "A4", "4").
  final String choice;

  /// The human-readable text for the choice (e.g., "A4", "Landscape").
  final String text;

  CupsOptionChoice({required this.choice, required this.text});
}

class CupsOption {
  /// The name of the option (e.g., "media", "orientation-requested").
  final String name;

  /// The default value for this option.
  final String defaultValue;

  /// A list of supported values for this option.
  final List<CupsOptionChoice> supportedValues;

  CupsOption({
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
class WindowsPrinterCapabilities {
  final List<WindowsPaperSize> paperSizes;
  final List<WindowsPaperSource> paperSources;
  final List<WindowsMediaType> mediaTypes;
  final List<WindowsResolution> resolutions;
  final bool isColorSupported;
  final bool isMonochromeSupported;
  final bool supportsLandscape;

  WindowsPrinterCapabilities({
    required this.paperSizes,
    required this.paperSources,
    required this.resolutions,
    required this.mediaTypes,
    required this.isColorSupported,
    required this.isMonochromeSupported,
    required this.supportsLandscape,
  });
}

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

/// Represents a page range for printing.
///
/// This class provides a type-safe way to define which pages of a document to print.
/// It can represent a single page, a continuous range of pages, or a complex
/// combination of pages and ranges.
///
/// Example usage:
/// ```dart
/// // Print only page 5
/// final singlePage = PageRange.single(5);
///
/// // Print pages 2 through 7
/// final continuousRange = PageRange.range(2, 7);
///
/// // Print pages 1, 3-5, and 8
/// final complexRange = PageRange.multiple([
///   PageRange.single(1),
///   PageRange.range(3, 5),
///   PageRange.single(8),
/// ]);
///
/// // Parse from a string
/// final fromString = PageRange.parse("1-3,5,7-9");
/// ```
class PageRange {
  final String _value;

  // Private constructor to ensure values are always validated.
  PageRange._(this._value);

  /// Creates a page range representing a single page.
  ///
  /// Throws an [ArgumentError] if [page] is not positive.
  factory PageRange.single(int page) {
    if (page <= 0) {
      throw ArgumentError('Page number must be positive, but was $page.');
    }
    return PageRange._('$page');
  }

  /// Creates a page range from a [start] to an [end] page, inclusive.
  ///
  /// Throws an [ArgumentError] if pages are not positive or if [end] is less than [start].
  factory PageRange.range(int start, int end) {
    if (start <= 0) {
      throw ArgumentError('Start page must be positive, but was $start.');
    }
    if (end < start) {
      throw ArgumentError('End page ($end) cannot be less than start page ($start).');
    }
    return PageRange._('$start-$end');
  }

  /// Creates a complex page range by combining multiple [PageRange] objects.
  factory PageRange.multiple(List<PageRange> ranges) {
    if (ranges.isEmpty) {
      throw ArgumentError('The list of ranges cannot be empty.');
    }
    return PageRange._(ranges.map((r) => r.toValue()).join(','));
  }

  /// Parses a page range string (e.g., "1-3,5,7-9") into a [PageRange] object.
  ///
  /// Throws an [ArgumentError] if the format is invalid.
  factory PageRange.parse(String rangeString) {
    final trimmed = rangeString.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('Page range string cannot be empty.');
    }
    // A simple regex to validate the overall structure. It's not exhaustive but catches most common errors.
    final RegExp validPageRange = RegExp(r'^\s*\d+(-\d+)?(\s*,\s*\d+(-\d+)?)*\s*$');
    if (!validPageRange.hasMatch(trimmed)) {
      throw ArgumentError('Invalid page range format: "$rangeString". Use a format like "1-3,5,7-9".');
    }
    // Further validation could be added here (e.g., check if end > start in all sub-ranges).
    return PageRange._(trimmed);
  }

  /// Returns the underlying string value of the page range.
  String toValue() => _value;

  @override
  String toString() => 'PageRange("$_value")';
}

// Request classes for printing operations
class _PrintRequest {
  final int id;
  final String printerName;
  final Uint8List data;
  final String docName;
  final Map<String, String>? options;

  const _PrintRequest(
    this.id,
    this.printerName,
    this.data,
    this.docName,
    this.options,
  );
}

class _PrintJobsRequest {
  final int id;
  final String printerName;

  const _PrintJobsRequest(this.id, this.printerName);
}

class _PrintJobActionRequest {
  final int id;
  final String printerName;
  final int jobId;
  final String action; // 'pause', 'resume', 'cancel'

  const _PrintJobActionRequest(
    this.id,
    this.printerName,
    this.jobId,
    this.action,
  );
}

class _PrintPdfRequest {
  final int id;
  final String printerName;
  final String pdfFilePath;
  final String docName;
  final Map<String, String>? options;
  final PdfPrintScaling scaling;
  final int copies;
  final PageRange? pageRange;
  final String alignment;

  const _PrintPdfRequest(
    this.id,
    this.printerName,
    this.pdfFilePath,
    this.docName,
    this.options,
    this.scaling,
    this.copies,
    this.pageRange,
    this.alignment,
  );
}

class _GetCupsOptionsRequest {
  final int id;
  final String printerName;

  const _GetCupsOptionsRequest(this.id, this.printerName);
}

class _SubmitRawDataJobRequest {
  final int id;
  final String printerName;
  final Uint8List data;
  final String docName;
  final Map<String, String>? options;

  const _SubmitRawDataJobRequest(
    this.id,
    this.printerName,
    this.data,
    this.docName,
    this.options,
  );
}

class _SubmitPdfJobRequest {
  final int id;
  final String printerName;
  final String pdfFilePath;
  final String docName;
  final Map<String, String>? options;
  final PdfPrintScaling scaling;
  final int copies;
  final PageRange? pageRange;
  final String alignment;

  const _SubmitPdfJobRequest(
    this.id,
    this.printerName,
    this.pdfFilePath,
    this.docName,
    this.options,
    this.scaling,
    this.copies,
    this.pageRange,
    this.alignment,
  );
}

class _GetWindowsCapsRequest {
  final int id;
  final String printerName;

  const _GetWindowsCapsRequest(this.id, this.printerName);
}

// Response classes
class _PrintResponse {
  final int id;
  final bool result;

  const _PrintResponse(this.id, this.result);
}

class _PrintJobsResponse {
  final int id;
  final List<PrintJob> jobs;

  const _PrintJobsResponse(this.id, this.jobs);
}

class _PrintJobActionResponse {
  final int id;
  final bool result;

  const _PrintJobActionResponse(this.id, this.result);
}

class _PrintPdfResponse {
  final int id;
  final bool result;

  const _PrintPdfResponse(this.id, this.result);
}

class _GetCupsOptionsResponse {
  final int id;
  final List<CupsOption> options;

  const _GetCupsOptionsResponse(this.id, this.options);
}

class _SubmitJobResponse {
  final int id;
  final int jobId;

  const _SubmitJobResponse(this.id, this.jobId);
}

class _GetWindowsCapsResponse {
  final int id;
  final WindowsPrinterCapabilities? capabilities;

  const _GetWindowsCapsResponse(this.id, this.capabilities);
}

class _ErrorResponse {
  final int id;
  final Object error;
  final StackTrace? stackTrace;

  const _ErrorResponse(this.id, this.error, this.stackTrace);
}

const String _libName = 'printing_ffi'; // Updated library name

final DynamicLibrary _dylib = () {
  if (Platform.isMacOS) {
    return DynamicLibrary.open('$_libName.framework/$_libName');
  }
  if (Platform.isLinux) return DynamicLibrary.open('lib$_libName.so');
  if (Platform.isWindows) return DynamicLibrary.open('$_libName.dll');
  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}();

final PrintingFfiBindings _bindings = PrintingFfiBindings(
  _dylib,
); // Updated to PrintingFfiBindings

final _getLastError = _dylib.lookup<NativeFunction<Pointer<Utf8> Function()>>('get_last_error').asFunction<Pointer<Utf8> Function()>();

// --- Initialization and Logging ---

// Define the C function signature for registering the callback
typedef _RegisterLogCallbackNative = Void Function(Pointer<NativeFunction<Void Function(Pointer<Char>)>>);
// Define the Dart function signature
typedef _RegisterLogCallback = void Function(Pointer<NativeFunction<Void Function(Pointer<Char>)>>);

/// A function that handles log messages from the native side.
typedef LogHandler = void Function(String message);

// The user-provided log handler.
LogHandler? _customLogHandler;

/// Top-level function to handle logs from native code.
/// This must be a top-level or static function to be used with `Pointer.fromFunction`.
void _logHandler(Pointer<Char> message) {
  final logMessage = message.cast<Utf8>().toDartString();
  if (_customLogHandler != null) {
    _customLogHandler!(logMessage);
  } else {
    // Default behavior if no handler is provided.
    debugPrint(logMessage);
  }
}

/// Initializes the printing_ffi plugin.
///
/// This function sets up necessary configurations, such as registering a
/// log handler to receive debug messages from the native code. It's recommended
/// to call this once when your application starts. An optional [logHandler]
/// can be provided to process log messages from the native layer.
void initializePrintingFfi({LogHandler? logHandler}) {
  _customLogHandler = logHandler;
  final registerer = _dylib.lookup<NativeFunction<_RegisterLogCallbackNative>>('register_log_callback').asFunction<_RegisterLogCallback>();
  // Use Pointer.fromFunction to get a pointer to our top-level log handler.
  // This is the correct and most efficient way to create a callback from a
  // static or top-level function.
  registerer(Pointer.fromFunction<Void Function(Pointer<Char>)>(_logHandler));
}

// Example functions from template
int sum(int a, int b) => _bindings.sum(a, b);

// Printing functions
List<Printer> listPrinters() {
  // Call the native function to get a pointer to the PrinterList struct.
  final printerListPtr = _bindings.get_printers();

  // If the pointer is null, it means an error occurred or no printers were found.
  if (printerListPtr == nullptr) {
    return [];
  }

  try {
    // Dereference the pointer to access the struct's data.
    final printerList = printerListPtr.ref;
    final printers = <Printer>[];
    for (var i = 0; i < printerList.count; i++) {
      printers.add(_printerFromInfo(printerList.printers[i]));
    }
    return printers;
  } finally {
    // IMPORTANT: Free the memory allocated by the native code.
    _bindings.free_printer_list(printerListPtr);
  }
}

/// Returns the default printer on the system, or `null` if none is found.
Printer? getDefaultPrinter() {
  final printerInfoPtr = _bindings.get_default_printer();

  if (printerInfoPtr == nullptr) {
    return null;
  }

  try {
    // Convert the native struct to a Dart object.
    return _printerFromInfo(printerInfoPtr.ref);
  } finally {
    // IMPORTANT: Free the memory allocated by the native code.
    _bindings.free_printer_info(printerInfoPtr);
  }
}

/// Converts a native [PrinterInfo] struct to a Dart [Printer] object.
Printer _printerFromInfo(PrinterInfo info) {
  final model = info.model.cast<Utf8>().toDartString();
  final location = info.location.cast<Utf8>().toDartString();
  final comment = info.comment.cast<Utf8>().toDartString();

  return Printer(
    name: info.name.cast<Utf8>().toDartString(),
    state: info.state,
    url: info.url.cast<Utf8>().toDartString(),
    model: model.isEmpty ? null : model,
    location: location.isEmpty ? null : location,
    comment: comment.isEmpty ? null : comment,
    isDefault: info.is_default,
    isAvailable: info.is_available,
  );
}

/// Opens the native printer properties dialog for the specified printer.
///
/// On Windows, this opens the standard system dialog for printer properties.
/// Changes made by the user are applied to the printer's default settings.
///
/// On macOS and Linux, this will attempt to open the CUPS web interface
/// for the printer in the default web browser (e.g., `http://localhost:631/printers/My_Printer`).
/// This requires the CUPS web interface to be enabled.
///
/// - [printerName]: The name of the target printer.
/// - [hwnd]: (Windows only) The handle to the parent window. Can be obtained from packages
///   like `win32` or by other platform-specific means. A value of 0 is often
///   acceptable for a modeless dialog.
///
/// Returns a [PrinterPropertiesResult] indicating whether the user confirmed
/// the changes, cancelled the dialog, or an error occurred.
Future<PrinterPropertiesResult> openPrinterProperties(String printerName, {int hwnd = 0}) async {
  // This is a synchronous call, so no need for an isolate.
  final namePtr = printerName.toNativeUtf8();
  try {
    // Use the generated binding directly.
    final result = _bindings.open_printer_properties(namePtr.cast(), hwnd);
    return switch (result) {
      1 => PrinterPropertiesResult.ok,
      2 => PrinterPropertiesResult.cancel,
      _ => PrinterPropertiesResult.error,
    };
  } finally {
    malloc.free(namePtr);
  }
}

/// Sends raw data directly to the specified printer.
///
/// This is useful for printing formats like ZPL, ESC/POS, or other
/// printer-specific command languages without any intermediate processing.
///
/// - [printerName]: The name of the target printer.
/// - [data]: The raw byte data to be printed.
/// - [docName]: The name of the document to show in the print queue.
/// - [options]: A list of [PrintOption] objects to configure the print job.
///
/// Returns `true` if the data was sent successfully. Throws a
/// [PrintingFfiException] on failure.
Future<bool> rawDataToPrinter(
  String printerName,
  Uint8List data, {
  String docName = 'Flutter Document',
  List<PrintOption> options = const [],
}) async {
  final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
  final int requestId = _nextPrintRequestId++;
  final optionsMap = _buildOptions(options);
  final _PrintRequest request = _PrintRequest(
    requestId,
    printerName,
    data,
    docName,
    optionsMap,
  );
  final Completer<bool> completer = Completer<bool>();
  _printRequests[requestId] = completer;
  helperIsolateSendPort.send(request);
  return completer.future;
}

/// Prints a PDF file to the specified printer.
///
/// On Windows, this uses the bundled `pdfium` library to render the PDF and
/// print it directly, offering robust and self-contained functionality.
///
/// On macOS and Linux, CUPS handles PDF printing natively.
///
/// - [printerName]: The name of the target printer.
/// - [pdfFilePath]: The local path to the PDF file.
/// - [docName]: The name of the document to show in the print queue.
/// - [scaling]: The scaling mode for Windows printing (defaults to [PdfPrintScaling.shrinkToFit]).
/// - [copies]: The number of copies to print. Defaults to 1.
/// - [pageRange]: A [PageRange] object specifying the pages to print.
///   If `null`, all pages will be printed.
///   The native layer will still validate the range against the PDF's page count,
///   which may cause the print to fail if the range is out of bounds.
/// - [options]: A list of [PrintOption] objects to configure the print job.
///   This can include settings like paper size, orientation, and color mode.
///   On Windows, alignment can also be configured (e.g., using [AlignmentOption(PdfPrintAlignment.topLeft)]).
Future<bool> printPdf(
  String printerName,
  String pdfFilePath, {
  String docName = 'Flutter PDF Document',
  PdfPrintScaling scaling = PdfPrintScaling.shrinkToFit,
  int? copies,
  PageRange? pageRange,
  List<PrintOption> options = const [],
}) async {
  // On Windows, run synchronously on the main isolate to avoid cross-isolate callbacks.
  if (Platform.isWindows) {
    final optionsMap = _buildOptions(options);
    final alignment = optionsMap.remove('alignment') ?? 'center';
    final namePtr = printerName.toNativeUtf8();
    final pathPtr = pdfFilePath.toNativeUtf8();
    final docNamePtr = docName.toNativeUtf8();
    final pageRangeValue = pageRange?.toValue();
    final alignmentPtr = alignment.toNativeUtf8();
    final pageRangePtr = pageRangeValue?.toNativeUtf8() ?? nullptr;
    try {
      final opts = {...optionsMap};
      if (scaling is _PdfPrintScalingCustom) {
        opts['custom-scale-factor'] = (scaling).scale.toString();
      }

      final int numOptions = opts.length;
      Pointer<Pointer<Utf8>> keysPtr = nullptr;
      Pointer<Pointer<Utf8>> valuesPtr = nullptr;
      if (numOptions > 0) {
        keysPtr = malloc<Pointer<Utf8>>(numOptions);
        valuesPtr = malloc<Pointer<Utf8>>(numOptions);
        int i = 0;
        for (var entry in opts.entries) {
          keysPtr[i] = entry.key.toNativeUtf8();
          valuesPtr[i] = entry.value.toNativeUtf8();
          i++;
        }
      }

      try {
        final bool result = _bindings.print_pdf(
          namePtr.cast(),
          pathPtr.cast(),
          docNamePtr.cast(),
          scaling.nativeValue,
          copies ?? 1,
          pageRangePtr.cast(),
          numOptions,
          keysPtr.cast(),
          valuesPtr.cast(),
          alignmentPtr.cast(),
        );
        if (!result) {
          final errorMsg = _getLastError().toDartString();
          throw PrintingFfiException(errorMsg);
        }
        return true;
      } finally {
        if (numOptions > 0) {
          for (var i = 0; i < numOptions; i++) {
            malloc.free(keysPtr[i]);
            malloc.free(valuesPtr[i]);
          }
          malloc.free(keysPtr);
          malloc.free(valuesPtr);
        }
      }
    } finally {
      malloc.free(namePtr);
      malloc.free(pathPtr);
      malloc.free(docNamePtr);
      if (pageRangePtr != nullptr) malloc.free(pageRangePtr);
      malloc.free(alignmentPtr);
    }
  }

  final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
  final int requestId = _nextPrintPdfRequestId++;
  final optionsMap = _buildOptions(options);
  final alignment = optionsMap.remove('alignment') ?? 'center';
  final _PrintPdfRequest request = _PrintPdfRequest(
    requestId,
    printerName,
    pdfFilePath,
    docName,
    optionsMap,
    scaling,
    copies ?? 1,
    pageRange,
    alignment,
  );
  final Completer<bool> completer = Completer<bool>();
  _printPdfRequests[requestId] = completer;
  helperIsolateSendPort.send(request);
  return completer.future;
}

/// Submits a raw data job to the printer and returns a stream of [PrintJob]
/// objects to track its status.
///
/// This is useful for monitoring the job's progress in real-time. The stream
/// will close automatically when the job reaches a terminal state (e.g.,
/// completed, canceled, or error).
///
/// - [printerName]: The name of the target printer.
/// - [data]: The raw byte data to be printed.
/// - [docName]: The name of the document to be shown in the print queue.
/// - [pollInterval]: The duration between status checks.
/// - [options]: A list of [PrintOption] objects to configure the print job.
Stream<PrintJob> rawDataToPrinterAndStreamStatus(
  String printerName,
  Uint8List data, {
  String docName = 'Flutter Raw Data',
  Duration pollInterval = const Duration(seconds: 2),
  List<PrintOption> options = const [],
}) {
  return _streamJobStatus(
    printerName: printerName,
    pollInterval: pollInterval,
    submitJob: () => _sendRawDataJobRequest(
      printerName,
      data,
      docName: docName,
      options: _buildOptions(options),
    ),
  );
}

/// Submits a PDF file to the printer and returns a stream of [PrintJob]
/// objects to track its status.
///
/// This is useful for monitoring the job's progress in real-time. The stream
/// will close automatically when the job reaches a terminal state (e.g.,
/// completed, canceled, or error).
///
/// See [printPdf] for more details on parameters.
Stream<PrintJob> printPdfAndStreamStatus(
  String printerName,
  String pdfFilePath, {
  String docName = 'Flutter PDF Document',
  PdfPrintScaling scaling = PdfPrintScaling.shrinkToFit,
  int? copies,
  PageRange? pageRange,
  List<PrintOption> options = const [],
  Duration pollInterval = const Duration(seconds: 2),
}) {
  return _streamJobStatus(
    printerName: printerName,
    pollInterval: pollInterval,
    submitJob: () {
      final optionsMap = _buildOptions(options);
      final alignment = optionsMap.remove('alignment') ?? 'center';
      return _sendPdfJobRequest(
        printerName,
        pdfFilePath,
        docName: docName,
        scaling: scaling,
        copies: copies,
        pageRange: pageRange,
        options: optionsMap,
        alignment: alignment,
      );
    },
  );
}

Map<String, String> _buildOptions(List<PrintOption> options) {
  final Map<String, String> optionsMap = {};
  for (final option in options) {
    switch (option) {
      case WindowsPaperSizeOption(id: final id):
        optionsMap['paper-size-id'] = id.toString();
      case WindowsPaperSourceOption(id: final id):
        optionsMap['paper-source-id'] = id.toString();
      case OrientationOption(orientation: final orientation):
        optionsMap['orientation'] = orientation.name;
      case GenericCupsOption(name: final name, value: final value):
        optionsMap[name] = value;
      case ColorModeOption(mode: final mode):
        optionsMap['color-mode'] = mode.name;
      case PrintQualityOption(quality: final quality):
        optionsMap['print-quality'] = quality.name;
      case WindowsMediaTypeOption(id: final id):
        optionsMap['media-type-id'] = id.toString();
      case AlignmentOption(alignment: final alignment):
        optionsMap['alignment'] = alignment.name;
      case CollateOption(collate: final collate):
        optionsMap['collate'] = collate.toString();
      case DuplexOption(mode: final mode):
        optionsMap['duplex'] = mode.name;
    }
  }
  return optionsMap;
}

/// Generic internal function to handle job submission and status polling.
Stream<PrintJob> _streamJobStatus({
  required String printerName,
  required Duration pollInterval,
  required Future<int> Function() submitJob,
}) {
  late StreamController<PrintJob> controller;
  Timer? poller;
  PrintJob? lastJob;

  Future<void> poll(int jobId) async {
    if (controller.isClosed) return;
    try {
      final jobs = await listPrintJobs(printerName);
      PrintJob? foundJob;
      try {
        foundJob = jobs.firstWhere((j) => j.id == jobId);
      } on StateError {
        // Job not found in the current list.
        foundJob = null;
      }

      if (foundJob != null) {
        // We found the job, so we can update its status.
        if (foundJob.rawStatus != lastJob?.rawStatus) {
          controller.add(foundJob);
        }
        lastJob = foundJob; // Update the last known state.

        final status = foundJob.status;
        if (status == PrintJobStatus.completed || status == PrintJobStatus.canceled || status == PrintJobStatus.aborted || status == PrintJobStatus.error) {
          poller?.cancel();
          await controller.close();
        }
      } else {
        // The job is not in the active queue. If we have seen it before,
        // it means it has now disappeared, so we can assume it's completed.
        // We emit one final 'completed' status before closing the stream.
        if (lastJob != null && lastJob!.status != PrintJobStatus.completed) {
          // The job was in a non-terminal state and now it's gone.
          // Synthesize a 'completed' status update.
          // For CUPS, '9' is IPP_JOB_COMPLETED.
          // For Windows, '0x00001000' is JOB_STATUS_COMPLETE.
          final completedRawStatus = Platform.isWindows ? 0x00001000 : 9;
          final finalJob = PrintJob(lastJob!.id, lastJob!.title, completedRawStatus);
          if (finalJob.rawStatus != lastJob!.rawStatus) {
            controller.add(finalJob);
          }
        }
        poller?.cancel();
        await controller.close();
      }
    } catch (e, s) {
      if (!controller.isClosed) controller.addError(e, s);
      poller?.cancel();
      await controller.close();
    }
  }

  controller = StreamController<PrintJob>(
    onListen: () async {
      final jobId = await submitJob();
      if (jobId <= 0) {
        controller.addError(Exception('Failed to submit job to the print queue.'));
        await controller.close();
      } else {
        poller = Timer.periodic(pollInterval, (_) => poll(jobId));
        poll(jobId); // Initial poll
      }
    },
    onCancel: () {
      poller?.cancel();
    },
  );

  return controller.stream;
}

/// Fetches the list of supported CUPS options for a given printer.
///
/// This function is only effective on macOS and Linux. On Windows, it will
/// return an empty list.
///
/// - [printerName]: The name of the target printer.
///
/// Returns a list of [CupsOption] objects, each describing a configurable
/// setting for the printer.
Future<List<CupsOption>> getSupportedCupsOptions(String printerName) async {
  // This function is only supported on CUPS-based systems.
  if (!Platform.isMacOS && !Platform.isLinux) {
    return [];
  }

  final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
  final int requestId = _nextGetCupsOptionsRequestId++;
  final _GetCupsOptionsRequest request = _GetCupsOptionsRequest(requestId, printerName);
  final Completer<List<CupsOption>> completer = Completer<List<CupsOption>>();
  _getCupsOptionsRequests[requestId] = completer;
  helperIsolateSendPort.send(request);
  return completer.future;
}

/// Fetches capabilities for a given printer on Windows, such as supported
/// paper sizes and resolutions.
///
/// Returns `null` if not on Windows or if capabilities cannot be retrieved.
Future<WindowsPrinterCapabilities?> getWindowsPrinterCapabilities(String printerName) async {
  if (!Platform.isWindows) {
    return null;
  }
  final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
  final int requestId = _nextGetWindowsCapsRequestId++;
  final request = _GetWindowsCapsRequest(requestId, printerName); // Corrected
  final completer = Completer<WindowsPrinterCapabilities?>();
  _getWindowsCapsRequests[requestId] = completer;
  helperIsolateSendPort.send(request);
  return completer.future;
}

/// Fetches the current list of print jobs for a given printer.
///
/// - [printerName]: The name of the target printer.
///
/// Returns a list of [PrintJob] objects currently in the queue.
Future<List<PrintJob>> listPrintJobs(String printerName) async {
  final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
  final int requestId = _nextPrintJobsRequestId++;
  final _PrintJobsRequest request = _PrintJobsRequest(requestId, printerName);
  final Completer<List<PrintJob>> completer = Completer<List<PrintJob>>();
  _printJobsRequests[requestId] = completer;
  helperIsolateSendPort.send(request);
  return completer.future;
}

/// Returns a stream of print jobs for the specified printer.
///
/// This function polls for print jobs at a given interval and emits a new list
/// of jobs. This is useful for building reactive UIs that automatically update
/// as the print queue changes.
///
/// - [printerName]: The name of the target printer.
/// - [pollInterval]: The duration between each poll for print jobs. Defaults to 2 seconds.
Stream<List<PrintJob>> listPrintJobsStream(
  String printerName, {
  Duration pollInterval = const Duration(seconds: 2),
}) {
  late StreamController<List<PrintJob>> controller;
  Timer? timer;

  void startPolling() {
    if (timer?.isActive ?? false) return;
    timer = Timer.periodic(pollInterval, (_) async {
      if (controller.isClosed) {
        timer?.cancel();
        return;
      }
      try {
        final jobs = await listPrintJobs(printerName);
        if (!controller.isClosed) {
          controller.add(jobs);
        }
      } catch (e, s) {
        if (!controller.isClosed) {
          controller.addError(e, s);
        }
      }
    });
  }

  void stopPolling() {
    timer?.cancel();
    timer = null;
  }

  controller = StreamController<List<PrintJob>>(
    onListen: () {
      // Immediately fetch jobs on listen, then start polling.
      listPrintJobs(printerName)
          .then((jobs) {
            if (!controller.isClosed) {
              controller.add(jobs);
            }
            startPolling();
          })
          .catchError((e, s) {
            if (!controller.isClosed) {
              controller.addError(e, s);
            }
          });
    },
    onPause: stopPolling,
    onResume: startPolling,
    onCancel: stopPolling,
  );

  return controller.stream;
}

/// Pauses a specific print job.
///
/// - [printerName]: The name of the printer where the job is queued.
/// - [jobId]: The ID of the job to pause.
Future<bool> pausePrintJob(String printerName, int jobId) async {
  final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
  final int requestId = _nextPrintJobActionRequestId++;
  final _PrintJobActionRequest request = _PrintJobActionRequest(
    requestId,
    printerName,
    jobId,
    'pause',
  );
  final Completer<bool> completer = Completer<bool>();
  _printJobActionRequests[requestId] = completer;
  helperIsolateSendPort.send(request);
  return completer.future;
}

/// Resumes a paused print job.
///
/// - [printerName]: The name of the printer where the job is queued.
/// - [jobId]: The ID of the job to resume.
Future<bool> resumePrintJob(String printerName, int jobId) async {
  final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
  final int requestId = _nextPrintJobActionRequestId++;
  final _PrintJobActionRequest request = _PrintJobActionRequest(
    requestId,
    printerName,
    jobId,
    'resume',
  );
  final Completer<bool> completer = Completer<bool>();
  _printJobActionRequests[requestId] = completer;
  helperIsolateSendPort.send(request);
  return completer.future;
}

/// Cancels a print job.
///
/// - [printerName]: The name of the printer where the job is queued.
/// - [jobId]: The ID of the job to cancel.
Future<bool> cancelPrintJob(String printerName, int jobId) async {
  final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
  final int requestId = _nextPrintJobActionRequestId++;
  final _PrintJobActionRequest request = _PrintJobActionRequest(
    requestId,
    printerName,
    jobId,
    'cancel',
  );
  final Completer<bool> completer = Completer<bool>();
  _printJobActionRequests[requestId] = completer;
  helperIsolateSendPort.send(request);
  return completer.future;
}

Future<int> _sendRawDataJobRequest(
  String printerName,
  Uint8List data, {
  String docName = 'Flutter Document',
  Map<String, String> options = const {},
}) async {
  final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
  final int requestId = _nextSubmitRawDataJobRequestId++;
  final request = _SubmitRawDataJobRequest(
    requestId,
    printerName,
    data,
    docName,
    options,
  );
  final completer = Completer<int>();
  _submitRawDataJobRequests[requestId] = completer;
  helperIsolateSendPort.send(request);
  return completer.future;
}

Future<int> _sendPdfJobRequest(
  String printerName,
  String pdfFilePath, {
  String docName = 'Flutter PDF Document',
  PdfPrintScaling scaling = PdfPrintScaling.shrinkToFit,
  int? copies,
  PageRange? pageRange,
  Map<String, String> options = const {},
  String alignment = 'center',
}) async {
  // On Windows, run synchronously on the main isolate to avoid cross-isolate callbacks.
  if (Platform.isWindows) {
    final namePtr = printerName.toNativeUtf8();
    final pathPtr = pdfFilePath.toNativeUtf8();
    final docNamePtr = docName.toNativeUtf8();
    final pageRangeValue = pageRange?.toValue();
    final alignmentPtr = alignment.toNativeUtf8();
    final pageRangePtr = pageRangeValue?.toNativeUtf8() ?? nullptr;
    try {
      final opts = {...options};
      if (scaling is _PdfPrintScalingCustom) {
        opts['custom-scale-factor'] = (scaling).scale.toString();
      }

      final int numOptions = opts.length;
      Pointer<Pointer<Utf8>> keysPtr = nullptr;
      Pointer<Pointer<Utf8>> valuesPtr = nullptr;
      if (numOptions > 0) {
        keysPtr = malloc<Pointer<Utf8>>(numOptions);
        valuesPtr = malloc<Pointer<Utf8>>(numOptions);
        int i = 0;
        for (var entry in opts.entries) {
          keysPtr[i] = entry.key.toNativeUtf8();
          valuesPtr[i] = entry.value.toNativeUtf8();
          i++;
        }
      }

      try {
        final int jobId = _bindings.submit_pdf_job(
          namePtr.cast(),
          pathPtr.cast(),
          docNamePtr.cast(),
          scaling.nativeValue,
          copies ?? 1,
          pageRangePtr.cast(),
          numOptions,
          keysPtr.cast(),
          valuesPtr.cast(),
          alignmentPtr.cast(),
        );
        if (jobId <= 0) {
          final errorMsg = _getLastError().toDartString();
          throw PrintingFfiException(errorMsg);
        }
        return jobId;
      } finally {
        if (numOptions > 0) {
          for (var i = 0; i < numOptions; i++) {
            malloc.free(keysPtr[i]);
            malloc.free(valuesPtr[i]);
          }
          malloc.free(keysPtr);
          malloc.free(valuesPtr);
        }
      }
    } finally {
      malloc.free(namePtr);
      malloc.free(pathPtr);
      malloc.free(docNamePtr);
      if (pageRangePtr != nullptr) malloc.free(pageRangePtr);
      malloc.free(alignmentPtr);
    }
  }

  final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
  final int requestId = _nextSubmitPdfJobRequestId++;
  final request = _SubmitPdfJobRequest(
    requestId,
    printerName,
    pdfFilePath,
    docName,
    options,
    scaling,
    copies ?? 1,
    pageRange,
    alignment,
  );
  final completer = Completer<int>();
  _submitPdfJobRequests[requestId] = completer;
  helperIsolateSendPort.send(request);
  return completer.future;
}

// Isolate communication setup

int _nextPrintRequestId = 0;
int _nextPrintJobsRequestId = 0;
int _nextPrintJobActionRequestId = 0;
int _nextPrintPdfRequestId = 0;
int _nextGetCupsOptionsRequestId = 0;
int _nextSubmitRawDataJobRequestId = 0;
int _nextSubmitPdfJobRequestId = 0;
int _nextGetWindowsCapsRequestId = 0;

final Map<int, Completer<bool>> _printRequests = <int, Completer<bool>>{};
final Map<int, Completer<List<PrintJob>>> _printJobsRequests = <int, Completer<List<PrintJob>>>{};
final Map<int, Completer<bool>> _printJobActionRequests = <int, Completer<bool>>{};
final Map<int, Completer<bool>> _printPdfRequests = <int, Completer<bool>>{};
final Map<int, Completer<List<CupsOption>>> _getCupsOptionsRequests = <int, Completer<List<CupsOption>>>{};
final Map<int, Completer<WindowsPrinterCapabilities?>> _getWindowsCapsRequests = <int, Completer<WindowsPrinterCapabilities?>>{};
final Map<int, Completer<int>> _submitRawDataJobRequests = <int, Completer<int>>{};
final Map<int, Completer<int>> _submitPdfJobRequests = <int, Completer<int>>{};

void _failAllPendingRequests(Object error, [StackTrace? stackTrace]) {
  final allCompleters = [
    ..._printRequests.values,
    ..._printJobsRequests.values,
    ..._printJobActionRequests.values,
    ..._printPdfRequests.values,
    ..._getCupsOptionsRequests.values,
    ..._getWindowsCapsRequests.values,
    ..._submitRawDataJobRequests.values,
    ..._submitPdfJobRequests.values,
  ];

  for (final completer in allCompleters) {
    if (!completer.isCompleted) {
      completer.completeError(error, stackTrace);
    }
  }

  _printRequests.clear();
  _printJobsRequests.clear();
  _printJobActionRequests.clear();
  _printPdfRequests.clear();
  _getCupsOptionsRequests.clear();
  _getWindowsCapsRequests.clear();
  _submitRawDataJobRequests.clear();
  _submitPdfJobRequests.clear();
}

Future<SendPort> _helperIsolateSendPort = () async {
  final Completer<SendPort> completer = Completer<SendPort>();
  final ReceivePort receivePort = ReceivePort(); // Move this line up here

  receivePort.listen((dynamic data) {
    if (data is SendPort) {
      completer.complete(data);
      return;
    }

    // Handle fatal isolate errors
    if (data is List && data.length == 2 && data[0] is String) {
      final error = IsolateError('Uncaught exception in helper isolate: ${data[0]}');
      final stack = StackTrace.fromString(data[1].toString());
      if (!completer.isCompleted) completer.completeError(error, stack);
      _failAllPendingRequests(error, stack);
      receivePort.close();
      return;
    }

    // Handle unexpected isolate exit
    if (data == null) {
      final error = IsolateError('Helper isolate exited unexpectedly.');
      if (!completer.isCompleted) completer.completeError(error);
      _failAllPendingRequests(error);
      receivePort.close();
      return;
    }

    if (data is _PrintResponse) {
      final Completer<bool> completer = _printRequests[data.id]!;
      _printRequests.remove(data.id);
      completer.complete(data.result);
      return;
    }
    if (data is _PrintJobsResponse) {
      final Completer<List<PrintJob>> completer = _printJobsRequests[data.id]!;
      _printJobsRequests.remove(data.id);
      completer.complete(data.jobs);
      return;
    }
    if (data is _PrintJobActionResponse) {
      final Completer<bool> completer = _printJobActionRequests[data.id]!;
      _printJobActionRequests.remove(data.id);
      completer.complete(data.result);
      return;
    }
    if (data is _PrintPdfResponse) {
      final Completer<bool> completer = _printPdfRequests[data.id]!;
      _printPdfRequests.remove(data.id);
      completer.complete(data.result);
      return;
    }
    if (data is _GetCupsOptionsResponse) {
      final Completer<List<CupsOption>> completer = _getCupsOptionsRequests[data.id]!;
      _getCupsOptionsRequests.remove(data.id);
      completer.complete(data.options);
      return;
    }
    if (data is _SubmitJobResponse) {
      if (_submitRawDataJobRequests.containsKey(data.id)) {
        _submitRawDataJobRequests.remove(data.id)!.complete(data.jobId);
      } else if (_submitPdfJobRequests.containsKey(data.id)) {
        _submitPdfJobRequests.remove(data.id)!.complete(data.jobId);
      }
      return;
    }
    if (data is _GetWindowsCapsResponse) {
      _getWindowsCapsRequests.remove(data.id)!.complete(data.capabilities);
      return;
    }
    if (data is _ErrorResponse) {
      final Completer? requestCompleter;
      if (_printRequests.containsKey(data.id)) {
        requestCompleter = _printRequests.remove(data.id);
      } else if (_printJobsRequests.containsKey(data.id)) {
        requestCompleter = _printJobsRequests.remove(data.id);
      } else if (_printJobActionRequests.containsKey(data.id)) {
        requestCompleter = _printJobActionRequests.remove(data.id);
      } else if (_printPdfRequests.containsKey(data.id)) {
        requestCompleter = _printPdfRequests.remove(data.id);
      } else if (_getCupsOptionsRequests.containsKey(data.id)) {
        requestCompleter = _getCupsOptionsRequests.remove(data.id);
      } else if (_submitRawDataJobRequests.containsKey(data.id)) {
        requestCompleter = _submitRawDataJobRequests.remove(data.id);
      } else if (_submitPdfJobRequests.containsKey(data.id)) {
        requestCompleter = _submitPdfJobRequests.remove(data.id);
      } else if (_getWindowsCapsRequests.containsKey(data.id)) {
        requestCompleter = _getWindowsCapsRequests.remove(data.id);
      } else {
        requestCompleter = null;
      }
      requestCompleter?.completeError(data.error, data.stackTrace);
      return;
    }
    throw UnsupportedError('Unsupported message type: ${data.runtimeType}');
  });

  await Isolate.spawn(
    (SendPort sendPort) async {
      // Register the native log callback inside the helper isolate to ensure
      // the callback originates from the same isolate that performs FFI calls.
      try {
        final _RegisterLogCallback registerer = _dylib.lookup<NativeFunction<_RegisterLogCallbackNative>>('register_log_callback').asFunction<_RegisterLogCallback>();
        registerer(Pointer.fromFunction<Void Function(Pointer<Char>)>(_logHandler));
      } catch (_) {
        // If registration is unavailable, continue without crashing.
      }

      final ReceivePort helperReceivePort = ReceivePort()
        ..listen((dynamic data) {
          // ... rest of the isolate code remains the same
          if (data is _PrintRequest) {
            try {
              final namePtr = data.printerName.toNativeUtf8();
              final docNamePtr = data.docName.toNativeUtf8();
              final dataPtr = malloc<Uint8>(data.data.length);
              for (var i = 0; i < data.data.length; i++) {
                dataPtr[i] = data.data[i];
              }
              try {
                final options = {...?data.options};
                if (Platform.isMacOS || Platform.isLinux) {
                  // Translate generic options to CUPS/IPP standard options.
                  if (options.containsKey('orientation')) {
                    final orientationValue = options.remove('orientation');
                    options['orientation-requested'] = orientationValue == 'landscape' ? '4' : '3';
                  }
                  if (options.containsKey('color-mode')) {
                    final colorValue = options.remove('color-mode');
                    options['print-color-mode'] = colorValue!;
                  }
                  if (options.containsKey('print-quality')) {
                    final qualityValue = options.remove('print-quality');
                    switch (qualityValue) {
                      case 'draft':
                      case 'low':
                        options['print-quality'] = '3'; // IPP_QUALITY_DRAFT
                        break;
                      case 'normal':
                        options['print-quality'] = '4'; // IPP_QUALITY_NORMAL
                        break;
                      case 'high':
                        options['print-quality'] = '5'; // IPP_QUALITY_HIGH
                        break;
                    }
                  }

                  if (options.containsKey('duplex')) {
                    // Translate duplex option to CUPS standard values
                    final duplexValue = options.remove('duplex');
                    switch (duplexValue) {
                      case 'singleSided':
                        options['sides'] = 'one-sided';
                        break;
                      case 'duplexLongEdge':
                        options['sides'] = 'two-sided-long-edge';
                        break;
                      case 'duplexShortEdge':
                        options['sides'] = 'two-sided-short-edge';
                        break;
                    }
                  }
                }
                final int numOptions = options.length;
                Pointer<Pointer<Utf8>> keysPtr = nullptr;
                Pointer<Pointer<Utf8>> valuesPtr = nullptr;

                try {
                  if (numOptions > 0) {
                    keysPtr = malloc<Pointer<Utf8>>(numOptions);
                    valuesPtr = malloc<Pointer<Utf8>>(numOptions);
                    int i = 0;
                    for (var entry in options.entries) {
                      keysPtr[i] = entry.key.toNativeUtf8();
                      valuesPtr[i] = entry.value.toNativeUtf8();
                      i++;
                    }
                  }

                  final bool result = _bindings.raw_data_to_printer(
                    // Use generated binding
                    namePtr.cast(),
                    dataPtr,
                    data.data.length,
                    docNamePtr.cast(),
                    numOptions,
                    keysPtr.cast(),
                    valuesPtr.cast(),
                  );
                  if (result) {
                    sendPort.send(_PrintResponse(data.id, true));
                  } else {
                    final errorMsg = _getLastError().toDartString();
                    sendPort.send(_ErrorResponse(data.id, PrintingFfiException(errorMsg), StackTrace.current));
                  }
                } finally {
                  if (numOptions > 0) {
                    for (var i = 0; i < numOptions; i++) {
                      malloc.free(keysPtr[i]);
                      malloc.free(valuesPtr[i]);
                    }
                    malloc.free(keysPtr);
                    malloc.free(valuesPtr);
                  }
                }
              } finally {
                malloc.free(namePtr);
                malloc.free(docNamePtr);
                malloc.free(dataPtr);
              }
            } catch (e, s) {
              sendPort.send(_ErrorResponse(data.id, e, s));
            }
          } else if (data is _PrintJobsRequest) {
            try {
              final namePtr = data.printerName.toNativeUtf8();
              try {
                final jobListPtr = _bindings.get_print_jobs(namePtr.cast());
                final jobs = <PrintJob>[];
                if (jobListPtr != nullptr) {
                  try {
                    final jobList = jobListPtr.ref;
                    for (var i = 0; i < jobList.count; i++) {
                      final jobInfo = jobList.jobs[i];
                      jobs.add(
                        PrintJob(
                          jobInfo.id,
                          jobInfo.title.cast<Utf8>().toDartString(),
                          jobInfo.status,
                        ),
                      );
                    }
                  } finally {
                    // IMPORTANT: Free the memory for the job list.
                    _bindings.free_job_list(jobListPtr);
                  }
                }
                sendPort.send(_PrintJobsResponse(data.id, jobs));
              } finally {
                malloc.free(namePtr);
              }
            } catch (e, s) {
              sendPort.send(_ErrorResponse(data.id, e, s));
            }
          } else if (data is _PrintJobActionRequest) {
            try {
              final namePtr = data.printerName.toNativeUtf8();
              try {
                bool result = false;
                if (data.action == 'pause') {
                  result = _bindings.pause_print_job(namePtr.cast(), data.jobId);
                } else if (data.action == 'resume') {
                  result = _bindings.resume_print_job(namePtr.cast(), data.jobId);
                } else if (data.action == 'cancel') {
                  result = _bindings.cancel_print_job(namePtr.cast(), data.jobId);
                }
                sendPort.send(_PrintJobActionResponse(data.id, result));
              } finally {
                malloc.free(namePtr);
              }
            } catch (e, s) {
              sendPort.send(_ErrorResponse(data.id, e, s));
            }
          } else if (data is _PrintPdfRequest) {
            try {
              final namePtr = data.printerName.toNativeUtf8();
              final pathPtr = data.pdfFilePath.toNativeUtf8();
              final docNamePtr = data.docName.toNativeUtf8();
              final pageRangeValue = data.pageRange?.toValue();
              final alignmentPtr = data.alignment.toNativeUtf8();
              final pageRangePtr = pageRangeValue?.toNativeUtf8() ?? nullptr;
              try {
                // Handle cupsOptions for native call
                final options = {...?data.options};
                if (data.scaling is _PdfPrintScalingCustom) {
                  options['custom-scale-factor'] = (data.scaling as _PdfPrintScalingCustom).scale.toString();
                }
                if (Platform.isMacOS || Platform.isLinux) {
                  if (data.copies > 1) options['copies'] = data.copies.toString();
                  if (pageRangeValue != null && pageRangeValue.isNotEmpty) options['page-ranges'] = pageRangeValue;
                  // Translate generic options to CUPS/IPP standard options.
                  if (options.containsKey('orientation')) {
                    final orientationValue = options.remove('orientation');
                    options['orientation-requested'] = orientationValue == 'landscape' ? '4' : '3';
                  }
                  if (options.containsKey('color-mode')) {
                    final colorValue = options.remove('color-mode');
                    options['print-color-mode'] = colorValue!;
                  }
                  if (options.containsKey('print-quality')) {
                    final qualityValue = options.remove('print-quality');
                    switch (qualityValue) {
                      case 'draft':
                      case 'low':
                        options['print-quality'] = '3'; // IPP_QUALITY_DRAFT
                        break;
                      case 'normal':
                        options['print-quality'] = '4'; // IPP_QUALITY_NORMAL
                        break;
                      case 'high':
                        options['print-quality'] = '5'; // IPP_QUALITY_HIGH
                        break;
                    }
                  }

                  if (options.containsKey('duplex')) {
                    // Translate duplex option to CUPS standard values
                    final duplexValue = options.remove('duplex');
                    switch (duplexValue) {
                      case 'singleSided':
                        options['sides'] = 'one-sided';
                        break;
                      case 'duplexLongEdge':
                        options['sides'] = 'two-sided-long-edge';
                        break;
                      case 'duplexShortEdge':
                        options['sides'] = 'two-sided-short-edge';
                        break;
                    }
                  }
                }

                final int numOptions = options.length;
                Pointer<Pointer<Utf8>> keysPtr = nullptr;
                Pointer<Pointer<Utf8>> valuesPtr = nullptr;

                if (numOptions > 0) {
                  keysPtr = malloc<Pointer<Utf8>>(numOptions);
                  valuesPtr = malloc<Pointer<Utf8>>(numOptions);
                  int i = 0;
                  for (var entry in options.entries) {
                    keysPtr[i] = entry.key.toNativeUtf8();
                    valuesPtr[i] = entry.value.toNativeUtf8();
                    i++;
                  }
                }

                final bool result = _bindings.print_pdf(
                  // Use generated binding
                  namePtr.cast(),
                  pathPtr.cast(),
                  docNamePtr.cast(),
                  data.scaling.nativeValue,
                  data.copies,
                  pageRangePtr.cast(),
                  numOptions,
                  keysPtr.cast(),
                  valuesPtr.cast(),
                  alignmentPtr.cast(),
                );
                if (result) {
                  sendPort.send(_PrintPdfResponse(data.id, true));
                } else {
                  final errorMsg = _getLastError().toDartString();
                  sendPort.send(_ErrorResponse(data.id, PrintingFfiException(errorMsg), StackTrace.current));
                }

                if (numOptions > 0) {
                  for (var i = 0; i < numOptions; i++) {
                    malloc.free(keysPtr[i]);
                    malloc.free(valuesPtr[i]);
                  }
                  malloc.free(keysPtr);
                  malloc.free(valuesPtr);
                }
              } finally {
                malloc.free(namePtr);
                malloc.free(pathPtr);
                malloc.free(docNamePtr);
                if (pageRangePtr != nullptr) malloc.free(pageRangePtr);
                malloc.free(alignmentPtr);
              }
            } catch (e, s) {
              sendPort.send(_ErrorResponse(data.id, e, s));
            }
          } else if (data is _GetCupsOptionsRequest) {
            try {
              final namePtr = data.printerName.toNativeUtf8();
              try {
                final optionListPtr = _bindings.get_supported_cups_options(namePtr.cast());
                final options = <CupsOption>[];
                if (optionListPtr != nullptr) {
                  try {
                    final optionList = optionListPtr.ref;
                    for (var i = 0; i < optionList.count; i++) {
                      final optionInfo = optionList.options[i];
                      final supportedValues = <CupsOptionChoice>[];
                      final choiceList = optionInfo.supported_values;
                      for (var j = 0; j < choiceList.count; j++) {
                        final choiceInfo = choiceList.choices[j];
                        supportedValues.add(
                          CupsOptionChoice(
                            choice: choiceInfo.choice.cast<Utf8>().toDartString(),
                            text: choiceInfo.text.cast<Utf8>().toDartString(),
                          ),
                        );
                      }
                      options.add(
                        CupsOption(
                          name: optionInfo.name.cast<Utf8>().toDartString(),
                          defaultValue: optionInfo.default_value.cast<Utf8>().toDartString(),
                          supportedValues: supportedValues,
                        ),
                      );
                    }
                  } finally {
                    _bindings.free_cups_option_list(optionListPtr);
                  }
                }
                sendPort.send(_GetCupsOptionsResponse(data.id, options));
              } finally {
                malloc.free(namePtr);
              }
            } catch (e, s) {
              sendPort.send(_ErrorResponse(data.id, e, s));
            }
          } else if (data is _SubmitRawDataJobRequest) {
            try {
              final namePtr = data.printerName.toNativeUtf8();
              final docNamePtr = data.docName.toNativeUtf8();
              final dataPtr = malloc<Uint8>(data.data.length);
              for (var i = 0; i < data.data.length; i++) {
                dataPtr[i] = data.data[i];
              }
              try {
                final options = {...?data.options};
                if (Platform.isMacOS || Platform.isLinux) {
                  // Translate generic options to CUPS/IPP standard options.
                  if (options.containsKey('orientation')) {
                    final orientationValue = options.remove('orientation');
                    options['orientation-requested'] = orientationValue == 'landscape' ? '4' : '3';
                  }
                  if (options.containsKey('color-mode')) {
                    final colorValue = options.remove('color-mode');
                    options['print-color-mode'] = colorValue!;
                  }
                  if (options.containsKey('print-quality')) {
                    final qualityValue = options.remove('print-quality');
                    switch (qualityValue) {
                      case 'draft':
                      case 'low':
                        options['print-quality'] = '3'; // IPP_QUALITY_DRAFT
                        break;
                      case 'normal':
                        options['print-quality'] = '4'; // IPP_QUALITY_NORMAL
                        break;
                      case 'high':
                        options['print-quality'] = '5'; // IPP_QUALITY_HIGH
                        break;
                    }
                  }

                  if (options.containsKey('duplex')) {
                    // Translate duplex option to CUPS standard values
                    final duplexValue = options.remove('duplex');
                    switch (duplexValue) {
                      case 'singleSided':
                        options['sides'] = 'one-sided';
                        break;
                      case 'duplexLongEdge':
                        options['sides'] = 'two-sided-long-edge';
                        break;
                      case 'duplexShortEdge':
                        options['sides'] = 'two-sided-short-edge';
                        break;
                    }
                  }
                }
                final int numOptions = options.length;
                Pointer<Pointer<Utf8>> keysPtr = nullptr;
                Pointer<Pointer<Utf8>> valuesPtr = nullptr;

                try {
                  if (numOptions > 0) {
                    keysPtr = malloc<Pointer<Utf8>>(numOptions);
                    valuesPtr = malloc<Pointer<Utf8>>(numOptions);
                    int i = 0;
                    for (var entry in options.entries) {
                      keysPtr[i] = entry.key.toNativeUtf8();
                      valuesPtr[i] = entry.value.toNativeUtf8();
                      i++;
                    }
                  }

                  final int jobId = _bindings.submit_raw_data_job(
                    // Use generated binding
                    namePtr.cast(),
                    dataPtr,
                    data.data.length,
                    docNamePtr.cast(),
                    numOptions,
                    keysPtr.cast(),
                    valuesPtr.cast(),
                  );
                  if (jobId > 0) {
                    sendPort.send(_SubmitJobResponse(data.id, jobId));
                  } else {
                    final errorMsg = _getLastError().toDartString();
                    sendPort.send(_ErrorResponse(data.id, PrintingFfiException(errorMsg), StackTrace.current));
                  }
                } finally {
                  if (numOptions > 0) {
                    for (var i = 0; i < numOptions; i++) {
                      malloc.free(keysPtr[i]);
                      malloc.free(valuesPtr[i]);
                    }
                    malloc.free(keysPtr);
                    malloc.free(valuesPtr);
                  }
                }
              } finally {
                malloc.free(namePtr);
                malloc.free(docNamePtr);
                malloc.free(dataPtr);
              }
            } catch (e, s) {
              sendPort.send(_ErrorResponse(data.id, e, s));
            }
          } else if (data is _SubmitPdfJobRequest) {
            try {
              final namePtr = data.printerName.toNativeUtf8();
              final pathPtr = data.pdfFilePath.toNativeUtf8();
              final docNamePtr = data.docName.toNativeUtf8();
              final pageRangeValue = data.pageRange?.toValue();
              final alignmentPtr = data.alignment.toNativeUtf8();
              final pageRangePtr = pageRangeValue?.toNativeUtf8() ?? nullptr;
              try {
                final options = {...?data.options};
                if (data.scaling is _PdfPrintScalingCustom) {
                  options['custom-scale-factor'] = (data.scaling as _PdfPrintScalingCustom).scale.toString();
                }
                if (Platform.isMacOS || Platform.isLinux) {
                  if (data.copies > 1) options['copies'] = data.copies.toString();
                  if (pageRangeValue != null && pageRangeValue.isNotEmpty) options['page-ranges'] = pageRangeValue;
                  // Translate generic options to CUPS/IPP standard options.
                  if (options.containsKey('orientation')) {
                    final orientationValue = options.remove('orientation');
                    options['orientation-requested'] = orientationValue == 'landscape' ? '4' : '3';
                  }
                  if (options.containsKey('color-mode')) {
                    final colorValue = options.remove('color-mode');
                    options['print-color-mode'] = colorValue!;
                  }
                  if (options.containsKey('print-quality')) {
                    final qualityValue = options.remove('print-quality');
                    switch (qualityValue) {
                      case 'draft':
                      case 'low':
                        options['print-quality'] = '3'; // IPP_QUALITY_DRAFT
                        break;
                      case 'normal':
                        options['print-quality'] = '4'; // IPP_QUALITY_NORMAL
                        break;
                      case 'high':
                        options['print-quality'] = '5'; // IPP_QUALITY_HIGH
                        break;
                    }
                  }

                  if (options.containsKey('duplex')) {
                    // Translate duplex option to CUPS standard values
                    final duplexValue = options.remove('duplex');
                    switch (duplexValue) {
                      case 'singleSided':
                        options['sides'] = 'one-sided';
                        break;
                      case 'duplexLongEdge':
                        options['sides'] = 'two-sided-long-edge';
                        break;
                      case 'duplexShortEdge':
                        options['sides'] = 'two-sided-short-edge';
                        break;
                    }
                  }
                }

                final int numOptions = options.length;
                Pointer<Pointer<Utf8>> keysPtr = nullptr;
                Pointer<Pointer<Utf8>> valuesPtr = nullptr;

                if (numOptions > 0) {
                  keysPtr = malloc<Pointer<Utf8>>(numOptions);
                  valuesPtr = malloc<Pointer<Utf8>>(numOptions);
                  int i = 0;
                  for (var entry in options.entries) {
                    keysPtr[i] = entry.key.toNativeUtf8();
                    valuesPtr[i] = entry.value.toNativeUtf8();
                    i++;
                  }
                }

                final int jobId = _bindings.submit_pdf_job(
                  // Use generated binding
                  namePtr.cast(),
                  pathPtr.cast(),
                  docNamePtr.cast(),
                  data.scaling.nativeValue,
                  data.copies,
                  pageRangePtr.cast(),
                  numOptions,
                  keysPtr.cast(),
                  valuesPtr.cast(),
                  alignmentPtr.cast(),
                );
                if (jobId > 0) {
                  sendPort.send(_SubmitJobResponse(data.id, jobId));
                } else {
                  final errorMsg = _getLastError().toDartString();
                  sendPort.send(_ErrorResponse(data.id, PrintingFfiException(errorMsg), StackTrace.current));
                }

                if (numOptions > 0) {
                  for (var i = 0; i < numOptions; i++) {
                    malloc.free(keysPtr[i]);
                    malloc.free(valuesPtr[i]);
                  }
                  malloc.free(keysPtr);
                  malloc.free(valuesPtr);
                }
              } finally {
                malloc.free(namePtr);
                malloc.free(pathPtr);
                malloc.free(docNamePtr);
                if (pageRangePtr != nullptr) malloc.free(pageRangePtr);
                malloc.free(alignmentPtr);
              }
            } catch (e, s) {
              sendPort.send(_ErrorResponse(data.id, e, s));
            }
          } else if (data is _GetWindowsCapsRequest) {
            try {
              final namePtr = data.printerName.toNativeUtf8();
              try {
                final capsPtr = _bindings.get_windows_printer_capabilities(namePtr.cast());
                if (capsPtr == nullptr) {
                  sendPort.send(_GetWindowsCapsResponse(data.id, null));
                } else {
                  try {
                    final capsStruct = capsPtr.ref;
                    final paperSizes = <WindowsPaperSize>[];
                    for (var i = 0; i < capsStruct.paper_sizes.count; i++) {
                      final paperStruct = capsStruct.paper_sizes.papers[i];
                      paperSizes.add(
                        WindowsPaperSize(
                          id: paperStruct.id,
                          name: paperStruct.name.cast<Utf8>().toDartString(),
                          widthMillimeters: paperStruct.width_mm,
                          heightMillimeters: paperStruct.height_mm,
                        ),
                      );
                    }
                    final paperSources = <WindowsPaperSource>[];
                    for (var i = 0; i < capsStruct.paper_sources.count; i++) {
                      final sourceStruct = capsStruct.paper_sources.sources[i];
                      paperSources.add(
                        WindowsPaperSource(
                          id: sourceStruct.id,
                          name: sourceStruct.name.cast<Utf8>().toDartString(),
                        ),
                      );
                    }
                    final mediaTypes = <WindowsMediaType>[];
                    for (var i = 0; i < capsStruct.media_types.count; i++) {
                      final mediaStruct = capsStruct.media_types.types[i];
                      mediaTypes.add(
                        WindowsMediaType(
                          id: mediaStruct.id,
                          name: mediaStruct.name.cast<Utf8>().toDartString(),
                        ),
                      );
                    }
                    final resolutions = <WindowsResolution>[];
                    for (var i = 0; i < capsStruct.resolutions.count; i++) {
                      final resStruct = capsStruct.resolutions.resolutions[i];
                      resolutions.add(
                        WindowsResolution(
                          xdpi: resStruct.x_dpi,
                          ydpi: resStruct.y_dpi,
                        ),
                      );
                    }
                    final capabilities = WindowsPrinterCapabilities(
                      paperSizes: paperSizes,
                      paperSources: paperSources,
                      mediaTypes: mediaTypes,
                      resolutions: resolutions,
                      isColorSupported: capsStruct.is_color_supported,
                      isMonochromeSupported: capsStruct.is_monochrome_supported,
                      supportsLandscape: capsStruct.supports_landscape,
                    );
                    sendPort.send(_GetWindowsCapsResponse(data.id, capabilities));
                  } finally {
                    _bindings.free_windows_printer_capabilities(capsPtr);
                  }
                }
              } finally {
                malloc.free(namePtr);
              }
            } catch (e, s) {
              sendPort.send(_ErrorResponse(data.id, e, s));
            }
          } else {
            throw UnsupportedError(
              'Unsupported message type: ${data.runtimeType}',
            );
          }
        });

      sendPort.send(helperReceivePort.sendPort);
    },
    receivePort.sendPort,
    // Now receivePort is properly declared and can be referenced
    onError: receivePort.sendPort,
    onExit: receivePort.sendPort,
    // ignore: invalid_return_type_for_catch_error
  ).catchError((e, s) => completer.completeError(e, s));

  return completer.future;
}();
