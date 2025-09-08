import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
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
enum PdfPrintScaling {
  /// Scale the page to fit the printable area of the paper, maintaining aspect ratio.
  fitPage,

  /// Print the page at its actual size (100% scale), centered on the paper.
  actualSize,
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
  final String name;
  final double widthMillimeters;
  final double heightMillimeters;

  WindowsPaperSize({
    required this.name,
    required this.widthMillimeters,
    required this.heightMillimeters,
  });

  @override
  String toString() => '$name (${widthMillimeters.toStringAsFixed(1)} x ${heightMillimeters.toStringAsFixed(1)} mm)';
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
  final List<WindowsResolution> resolutions;

  WindowsPrinterCapabilities({required this.paperSizes, required this.resolutions});
}

/// Exception thrown when the helper isolate encounters a fatal error or exits unexpectedly.
class IsolateError extends Error {
  final String message;
  IsolateError(this.message);
  @override
  String toString() => 'IsolateError: $message';
}

// Request classes for printing operations
class _PrintRequest {
  final int id;
  final String printerName;
  final Uint8List data;
  final String docName;

  const _PrintRequest(this.id, this.printerName, this.data, this.docName);
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
  final Map<String, String>? cupsOptions;
  final PdfPrintScaling scaling;

  const _PrintPdfRequest(
    this.id,
    this.printerName,
    this.pdfFilePath,
    this.docName,
    this.cupsOptions,
    this.scaling,
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

  const _SubmitRawDataJobRequest(this.id, this.printerName, this.data, this.docName);
}

class _SubmitPdfJobRequest {
  final int id;
  final String printerName;
  final String pdfFilePath;
  final String docName;
  final Map<String, String>? cupsOptions;
  final PdfPrintScaling scaling;

  const _SubmitPdfJobRequest(
    this.id,
    this.printerName,
    this.pdfFilePath,
    this.docName,
    this.cupsOptions,
    this.scaling,
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

// Manually look up the new functions for submitting jobs.
final _submit_raw_data_job = _dylib.lookupFunction<Int32 Function(Pointer<Utf8>, Pointer<Uint8>, Int32, Pointer<Utf8>), int Function(Pointer<Utf8>, Pointer<Uint8>, int, Pointer<Utf8>)>('submit_raw_data_job');

final _submit_pdf_job = _dylib
    .lookupFunction<Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Int32, Int32, Pointer<Pointer<Utf8>>, Pointer<Pointer<Utf8>>), int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, int, int, Pointer<Pointer<Utf8>>, Pointer<Pointer<Utf8>>)>(
      'submit_pdf_job',
    );

// --- FFI Structs for Windows Capabilities ---
final class _PaperSize extends Struct {
  external Pointer<Utf8> name;
  @Float()
  external double width_mm;
  @Float()
  external double height_mm;
}

final class _PaperSizeList extends Struct {
  @Int()
  external int count;
  external Pointer<_PaperSize> papers;
}

final class _Resolution extends Struct {
  @Long()
  external int x_dpi;
  @Long()
  external int y_dpi;
}

final class _ResolutionList extends Struct {
  @Int()
  external int count;
  external Pointer<_Resolution> resolutions;
}

final class _WindowsPrinterCapabilitiesStruct extends Struct {
  external _PaperSizeList paper_sizes;
  external _ResolutionList resolutions;
}

// --- FFI Lookups for Windows Capabilities ---
final _get_windows_printer_capabilities = _dylib.lookupFunction<Pointer<_WindowsPrinterCapabilitiesStruct> Function(Pointer<Utf8>), Pointer<_WindowsPrinterCapabilitiesStruct> Function(Pointer<Utf8>)>('get_windows_printer_capabilities');

final _free_windows_printer_capabilities = _dylib.lookupFunction<Void Function(Pointer<_WindowsPrinterCapabilitiesStruct>), void Function(Pointer<_WindowsPrinterCapabilitiesStruct>)>('free_windows_printer_capabilities');

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

Future<bool> rawDataToPrinter(
  String printerName,
  Uint8List data, {
  String docName = 'Flutter Document',
}) async {
  final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
  final int requestId = _nextPrintRequestId++;
  final _PrintRequest request = _PrintRequest(
    requestId,
    printerName,
    data,
    docName,
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
/// On macOS and Linux, CUPS handles PDF printing natively. You can pass
/// CUPS-specific options via the [cupsOptions] map.
///
/// - [printerName]: The name of the target printer.
/// - [pdfFilePath]: The local path to the PDF file.
/// - [docName]: The name of the document to be shown in the print queue.
/// - [scaling]: The scaling mode for Windows printing (defaults to [PdfPrintScaling.fitPage]).
/// - [cupsOptions]: A map of CUPS options (e.g., `{'media': 'A4', 'orientation-requested': '4'}`).
///   This is only used on macOS and Linux.
Future<bool> printPdf(
  String printerName,
  String pdfFilePath, {
  String docName = 'Flutter PDF Document',
  PdfPrintScaling scaling = PdfPrintScaling.fitPage,
  Map<String, String>? cupsOptions,
}) async {
  final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
  final int requestId = _nextPrintPdfRequestId++;
  final _PrintPdfRequest request = _PrintPdfRequest(
    requestId,
    printerName,
    pdfFilePath,
    docName,
    cupsOptions,
    scaling,
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
Stream<PrintJob> rawDataToPrinterAndStreamStatus(
  String printerName,
  Uint8List data, {
  String docName = 'Flutter Raw Data',
  Duration pollInterval = const Duration(seconds: 2),
}) {
  return _streamJobStatus(
    printerName: printerName,
    pollInterval: pollInterval,
    submitJob: () => _submitRawDataJob(printerName, data, docName: docName),
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
  PdfPrintScaling scaling = PdfPrintScaling.fitPage,
  Map<String, String>? cupsOptions,
  Duration pollInterval = const Duration(seconds: 2),
}) {
  return _streamJobStatus(
    printerName: printerName,
    pollInterval: pollInterval,
    submitJob: () => _submitPdfJob(
      printerName,
      pdfFilePath,
      docName: docName,
      scaling: scaling,
      cupsOptions: cupsOptions,
    ),
  );
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
      final currentJob = jobs.firstWhere((j) => j.id == jobId, orElse: () => lastJob!);

      if (currentJob.rawStatus != lastJob?.rawStatus) {
        controller.add(currentJob);
        lastJob = currentJob;
      }

      final status = currentJob.status;
      if (status == PrintJobStatus.completed || status == PrintJobStatus.canceled || status == PrintJobStatus.aborted || status == PrintJobStatus.error) {
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
  final request = _GetWindowsCapsRequest(requestId, printerName);
  final completer = Completer<WindowsPrinterCapabilities?>();
  _getWindowsCapsRequests[requestId] = completer;
  helperIsolateSendPort.send(request);
  return completer.future;
}

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

Future<int> _submitRawDataJob(
  String printerName,
  Uint8List data, {
  String docName = 'Flutter Document',
}) async {
  final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
  final int requestId = _nextSubmitRawDataJobRequestId++;
  final request = _SubmitRawDataJobRequest(requestId, printerName, data, docName);
  final completer = Completer<int>();
  _submitRawDataJobRequests[requestId] = completer;
  helperIsolateSendPort.send(request);
  return completer.future;
}

Future<int> _submitPdfJob(
  String printerName,
  String pdfFilePath, {
  String docName = 'Flutter PDF Document',
  PdfPrintScaling scaling = PdfPrintScaling.fitPage,
  Map<String, String>? cupsOptions,
}) async {
  final SendPort helperIsolateSendPort = await _helperIsolateSendPort;
  final int requestId = _nextSubmitPdfJobRequestId++;
  final request = _SubmitPdfJobRequest(
    requestId,
    printerName,
    pdfFilePath,
    docName,
    cupsOptions,
    scaling,
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
                final bool result = _bindings.raw_data_to_printer(
                  namePtr.cast(),
                  dataPtr,
                  data.data.length,
                  docNamePtr.cast(),
                );
                sendPort.send(_PrintResponse(data.id, result));
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
              try {
                // Handle cupsOptions for native call
                final int numOptions = (Platform.isMacOS || Platform.isLinux) ? data.cupsOptions?.length ?? 0 : 0;
                Pointer<Pointer<Utf8>> keysPtr = nullptr;
                Pointer<Pointer<Utf8>> valuesPtr = nullptr;

                if (numOptions > 0) {
                  keysPtr = malloc<Pointer<Utf8>>(numOptions);
                  valuesPtr = malloc<Pointer<Utf8>>(numOptions);
                  int i = 0;
                  for (var entry in data.cupsOptions!.entries) {
                    keysPtr[i] = entry.key.toNativeUtf8();
                    valuesPtr[i] = entry.value.toNativeUtf8();
                    i++;
                  }
                }

                final bool result = _bindings.print_pdf(
                  namePtr.cast(),
                  pathPtr.cast(),
                  docNamePtr.cast(),
                  data.scaling.index,
                  numOptions,
                  keysPtr.cast(),
                  valuesPtr.cast(),
                );
                sendPort.send(_PrintPdfResponse(data.id, result));

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
                final int jobId = _submit_raw_data_job(
                  namePtr.cast(),
                  dataPtr,
                  data.data.length,
                  docNamePtr.cast(),
                );
                sendPort.send(_SubmitJobResponse(data.id, jobId));
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
              try {
                final int numOptions = (Platform.isMacOS || Platform.isLinux) ? data.cupsOptions?.length ?? 0 : 0;
                Pointer<Pointer<Utf8>> keysPtr = nullptr;
                Pointer<Pointer<Utf8>> valuesPtr = nullptr;

                if (numOptions > 0) {
                  keysPtr = malloc<Pointer<Utf8>>(numOptions);
                  valuesPtr = malloc<Pointer<Utf8>>(numOptions);
                  int i = 0;
                  for (var entry in data.cupsOptions!.entries) {
                    keysPtr[i] = entry.key.toNativeUtf8();
                    valuesPtr[i] = entry.value.toNativeUtf8();
                    i++;
                  }
                }

                final int jobId = _submit_pdf_job(
                  namePtr.cast(),
                  pathPtr.cast(),
                  docNamePtr.cast(),
                  data.scaling.index,
                  numOptions,
                  keysPtr.cast(),
                  valuesPtr.cast(),
                );
                sendPort.send(_SubmitJobResponse(data.id, jobId));

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
              }
            } catch (e, s) {
              sendPort.send(_ErrorResponse(data.id, e, s));
            }
          } else if (data is _GetWindowsCapsRequest) {
            try {
              final namePtr = data.printerName.toNativeUtf8();
              try {
                final capsPtr = _get_windows_printer_capabilities(namePtr.cast());
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
                          name: paperStruct.name.toDartString(),
                          widthMillimeters: paperStruct.width_mm,
                          heightMillimeters: paperStruct.height_mm,
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
                      resolutions: resolutions,
                    );
                    sendPort.send(_GetWindowsCapsResponse(data.id, capabilities));
                  } finally {
                    _free_windows_printer_capabilities(capsPtr);
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
