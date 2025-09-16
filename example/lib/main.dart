import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing_ffi/printing_ffi.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'widgets.dart';

/// A local helper class to represent the custom scaling option in the UI.
/// This is a marker class for the SegmentedButton.
class _CustomScaling {
  const _CustomScaling();
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize the FFI plugin and provide a custom log handler.
  // This allows you to route native logs to your own logging infrastructure.
  initializePrintingFfi(
    logHandler: (message) {
      debugPrint('CUSTOM LOG HANDLER: $message');
    },
  );
  runApp(const PrintingFfiExampleApp());
}

class PrintingFfiExampleApp extends StatelessWidget {
  const PrintingFfiExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ShadApp.custom(
      themeMode: ThemeMode.light,
      darkTheme: ShadThemeData(
        brightness: Brightness.light,
        colorScheme: const ShadSlateColorScheme.dark(),
      ),
      appBuilder: (context) {
        return MaterialApp(
          title: 'Printing FFI Example',
          theme: Theme.of(context),
          builder: (context, child) {
            return ShadAppBuilder(child: child!);
          },
          home: const PrintingScreen(),
        );
      },
    );
  }
}

class PrintingScreen extends StatefulWidget {
  const PrintingScreen({super.key});

  @override
  State<PrintingScreen> createState() => _PrintingScreenState();
}

class _PrintingScreenState extends State<PrintingScreen> {
  List<Printer> _printers = [];
  Printer? _selectedPrinter;
  List<PrintJob> _jobs = [];
  StreamSubscription<List<PrintJob>>? _jobsSubscription;
  List<CupsOption>? _cupsOptions;
  Map<String, String> _selectedCupsOptions = {};
  WindowsPrinterCapabilities? _windowsCapabilities;
  WindowsPaperSize? _selectedPaperSize;
  WindowsPaperSource? _selectedPaperSource;
  WindowsOrientation _selectedOrientation = WindowsOrientation.portrait;
  ColorMode _selectedColorMode = ColorMode.color;
  PrintQuality _selectedPrintQuality = PrintQuality.normal;
  PdfPrintAlignment _selectedAlignment = PdfPrintAlignment.center;

  // Collate option for multiple copies
  // When true: Complete copies are printed together (1,2,3,4,5,6 - 1,2,3,4,5,6)
  // When false: All copies of each page are printed together (1,1 - 2,2 - 3,3 - 4,4 - 5,5 - 6,6)
  bool _collate = true;

  bool _isLoadingPrinters = false;
  bool _isLoadingJobs = false;
  bool _isLoadingCupsOptions = false;
  bool _isLoadingWindowsCaps = false;

  final TextEditingController _rawDataController = TextEditingController(
    text: 'Hello, FFI!',
  );
  Object _selectedScaling = PdfPrintScaling.fitToPrintableArea;
  final TextEditingController _customScaleController = TextEditingController(
    text: '1.0',
  );
  final TextEditingController _copiesController = TextEditingController(
    text: '1',
  );
  final TextEditingController _pageRangeController = TextEditingController();
  String? _selectedPdfPath;

  ///int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _refreshPrinters();
  }

  @override
  void dispose() {
    _rawDataController.dispose();
    _jobsSubscription?.cancel();
    _copiesController.dispose();
    _pageRangeController.dispose();
    _customScaleController.dispose();
    super.dispose();
  }

  void _showSnackbar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
      ),
    );
  }

  Future<void> _refreshPrinters() async {
    setState(() {
      _isLoadingPrinters = true;
      _printers = [];
      _selectedPrinter = null;
      _jobs = [];
      _cupsOptions = null;
      _selectedCupsOptions = {};
      _windowsCapabilities = null;
      _selectedPaperSize = null;
      _selectedPaperSource = null;
      _selectedOrientation = WindowsOrientation.portrait;
      _selectedColorMode = ColorMode.color;
      _selectedPrintQuality = PrintQuality.normal;
      _collate = true;
      _selectedPdfPath = null;
    });
    try {
      final printers = listPrinters();
      setState(() {
        _printers = printers;
        if (printers.isNotEmpty) {
          _selectedPrinter = printers.firstWhere(
            (p) => p.isDefault,
            orElse: () => printers.first,
          );
          _onPrinterSelected(_selectedPrinter);
        }
      });
    } catch (e) {
      _showSnackbar('Failed to get printers: $e', isError: true);
    } finally {
      setState(() {
        _isLoadingPrinters = false;
      });
    }
  }

  void _onPrinterSelected(Printer? printer) {
    if (printer == null) return;
    setState(() {
      _jobsSubscription?.cancel();
      _jobs = [];
      _selectedPrinter = printer;
      _subscribeToJobs();
      _fetchCupsOptions();
      _fetchWindowsCapabilities();
    });
  }

  void _subscribeToJobs() {
    if (_selectedPrinter == null) return;
    _jobsSubscription?.cancel();
    setState(() => _isLoadingJobs = true);
    _jobsSubscription = listPrintJobsStream(_selectedPrinter!.name).listen(
      (jobs) {
        if (!mounted) return;
        setState(() {
          _jobs = jobs;
          _isLoadingJobs = false;
        });
      },
      onError: (e) {
        if (!mounted) return;
        _showSnackbar('Error fetching jobs: $e', isError: true);
        setState(() => _isLoadingJobs = false);
      },
    );
  }

  Future<void> _fetchCupsOptions() async {
    if (_selectedPrinter == null) return;
    setState(() {
      _isLoadingCupsOptions = true;
      _cupsOptions = null;
    });

    try {
      final options = await getSupportedCupsOptions(_selectedPrinter!.name);
      if (!mounted) return;
      final defaultOptions = <String, String>{};
      for (final option in options) {
        defaultOptions[option.name] = option.defaultValue;
      }
      setState(() {
        _cupsOptions = options;
        _selectedCupsOptions = defaultOptions;
      });
    } catch (e) {
      _showSnackbar('Failed to get CUPS options: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoadingCupsOptions = false);
    }
  }

  Future<void> _fetchWindowsCapabilities() async {
    if (_selectedPrinter == null || !Platform.isWindows) return;
    setState(() => _isLoadingWindowsCaps = true);
    try {
      final caps = await getWindowsPrinterCapabilities(_selectedPrinter!.name);
      if (!mounted) return;
      setState(() {
        _windowsCapabilities = caps;
        // Set defaults
        if (caps?.paperSizes.isNotEmpty ?? false) {
          _selectedPaperSize = caps!.paperSizes.first;
        }
        if (caps?.paperSources.isNotEmpty ?? false) {
          _selectedPaperSource = caps!.paperSources.first;
        }
        _selectedOrientation = WindowsOrientation.portrait;
      });
    } catch (e) {
      _showSnackbar('Failed to get Windows capabilities: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoadingWindowsCaps = false);
    }
  }

  // Builds the list of options to be sent to the native print functions.
  List<PrintOption> _buildPrintOptions({Map<String, String>? cupsOptions}) {
    final options = <PrintOption>[];
    if (Platform.isWindows) {
      if (_selectedPaperSize != null) {
        options.add(WindowsPaperSizeOption(_selectedPaperSize!.id));
      }
      if (_selectedPaperSource != null) {
        options.add(WindowsPaperSourceOption(_selectedPaperSource!.id));
      }
      options.add(AlignmentOption(_selectedAlignment));
    }
    options.add(OrientationOption(_selectedOrientation));
    options.add(ColorModeOption(_selectedColorMode));
    options.add(PrintQualityOption(_selectedPrintQuality));

    if (Platform.isWindows &&
        (_windowsCapabilities?.mediaTypes.any((t) => t.name == 'Photo') ??
            false)) {
      // Example of setting a specific media type if available
    }

    if (cupsOptions != null) {
      cupsOptions.forEach((key, value) {
        options.add(GenericCupsOption(key, value));
      });
    }
    // Include collate option for multiple copies (applies on both Windows and CUPS where supported)
    // This controls whether complete copies are printed together or all copies of each page
    options.add(CollateOption(_collate));
    return options;
  }

  Future<String?> _getPdfPath() async {
    if (_selectedPdfPath != null) {
      return _selectedPdfPath;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      setState(() {
        _selectedPdfPath = path;
      });
      return path;
    }
    return null;
  }

  Future<void> _printPdf({
    Map<String, String>? cupsOptions,
    required int copies,
    required String pageRangeString,
  }) async {
    if (_selectedPrinter == null) {
      _showSnackbar('No printer selected!', isError: true);
      return;
    }
    PageRange? pageRange;
    if (pageRangeString.trim().isNotEmpty) {
      try {
        pageRange = PageRange.parse(pageRangeString);
      } on ArgumentError catch (e) {
        _showSnackbar('Invalid page range: ${e.message}', isError: true);
        return;
      }
    }
    final path = await _getPdfPath();
    if (path != null) {
      try {
        final options = _buildPrintOptions(cupsOptions: cupsOptions);
        _showSnackbar('Printing PDF...');

        final PdfPrintScaling scaling;
        if (_selectedScaling is _CustomScaling) {
          final scaleValue = double.tryParse(_customScaleController.text);
          if (scaleValue == null || scaleValue <= 0) {
            _showSnackbar(
              'Invalid custom scale value. It must be a positive number.',
              isError: true,
            );
            return;
          }
          scaling = PdfPrintScaling.custom(scaleValue);
        } else {
          scaling = _selectedScaling as PdfPrintScaling;
        }
        final success = await printPdf(
          _selectedPrinter!.name,
          path,
          docName: 'My Flutter PDF',
          options: options,
          scaling: scaling,
          copies: copies,
          pageRange: pageRange,
        );
        if (!mounted) return;
        if (success) {
          _showSnackbar('PDF sent to printer successfully!');
        }
      } on PrintingFfiException catch (e) {
        _showSnackbar('Failed to print PDF: ${e.message}', isError: true);
      } catch (e) {
        _showSnackbar(
          'An unexpected error occurred while printing: $e',
          isError: true,
        );
      }
    }
  }

  Future<void> _printPdfAndTrack() async {
    if (_selectedPrinter == null) {
      _showSnackbar('No printer selected!', isError: true);
      return;
    }
    final path = await _getPdfPath();
    if (path != null) {
      final copies = int.tryParse(_copiesController.text) ?? 1;
      final pageRangeString = _pageRangeController.text;
      PageRange? pageRange;
      if (pageRangeString.trim().isNotEmpty) {
        try {
          pageRange = PageRange.parse(pageRangeString);
        } on ArgumentError catch (e) {
          _showSnackbar('Invalid page range: ${e.message}', isError: true);
          return;
        }
      }
      final options = _buildPrintOptions();

      final PdfPrintScaling scaling;
      if (_selectedScaling is _CustomScaling) {
        final scaleValue = double.tryParse(_customScaleController.text);
        if (scaleValue == null || scaleValue <= 0) {
          _showSnackbar(
            'Invalid custom scale value. It must be a positive number.',
            isError: true,
          );
          return;
        }
        scaling = PdfPrintScaling.custom(scaleValue);
      } else {
        scaling = _selectedScaling as PdfPrintScaling;
      }

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => PrintStatusDialog(
          printerName: _selectedPrinter!.name,
          jobStream: printPdfAndStreamStatus(
            _selectedPrinter!.name,
            path,
            options: options,
            scaling: scaling,
            copies: copies,
            pageRange: pageRange,
          ),
        ),
      );
    }
  }

  Future<void> _printRawDataAndTrack() async {
    if (_selectedPrinter == null) {
      _showSnackbar('No printer selected!', isError: true);
      return;
    }
    // Construct ZPL data with the text from the input field.
    final textToPrint = _rawDataController.text;
    if (textToPrint.isEmpty) {
      _showSnackbar('Please enter some text to print.', isError: true);
      return;
    }
    final zplData = '^XA^FO50,50^A0N,50,50^FD$textToPrint^FS^XZ';
    final data = Uint8List.fromList(zplData.codeUnits);

    final options = _buildPrintOptions(cupsOptions: _selectedCupsOptions);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PrintStatusDialog(
        printerName: _selectedPrinter!.name,
        jobStream: rawDataToPrinterAndStreamStatus(
          _selectedPrinter!.name,
          data,
          docName: 'My Tracked ZPL Label',
          options: options,
        ),
      ),
    );
  }

  Future<void> _printRawData() async {
    if (_selectedPrinter == null) {
      _showSnackbar('No printer selected!', isError: true);
      return;
    }
    // Construct ZPL data with the text from the input field.
    final textToPrint = _rawDataController.text;
    if (textToPrint.isEmpty) {
      _showSnackbar('Please enter some text to print.', isError: true);
      return;
    }
    final zplData = '^XA^FO50,50^A0N,50,50^FD$textToPrint^FS^XZ';
    final data = Uint8List.fromList(zplData.codeUnits);

    final options = _buildPrintOptions(cupsOptions: _selectedCupsOptions);
    _showSnackbar('Sending raw ZPL data...');
    final success = await rawDataToPrinter(
      _selectedPrinter!.name,
      data,
      docName: 'My ZPL Label',
      options: options,
    );
    if (!mounted) return;
    if (success) {
      _showSnackbar('Raw data sent successfully!');
    } else {
      _showSnackbar('Failed to send raw data.', isError: true);
    }
  }

  Future<void> _manageJob(int jobId, String action) async {
    if (_selectedPrinter == null) return;
    bool success = false;
    try {
      switch (action) {
        case 'pause':
          success = await pausePrintJob(_selectedPrinter!.name, jobId);
          break;
        case 'resume':
          success = await resumePrintJob(_selectedPrinter!.name, jobId);
          break;
        case 'cancel':
          success = await cancelPrintJob(_selectedPrinter!.name, jobId);
          break;
      }
      if (!mounted) return;
      _showSnackbar(
        'Job $action ${success ? 'succeeded' : 'failed'}.',
        isError: !success,
      );
    } catch (e) {
      _showSnackbar('Error managing job: $e', isError: true);
    }
  }

  Future<void> _showWindowsCapabilities() async {
    if (_selectedPrinter == null || !Platform.isWindows) return;

    final capabilities = await getWindowsPrinterCapabilities(
      _selectedPrinter!.name,
    );

    if (!mounted) return;

    if (capabilities == null) {
      _showSnackbar(
        'Could not retrieve capabilities for this printer.',
        isError: true,
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Capabilities for ${_selectedPrinter!.name}'),
        content: SizedBox(
          width: 400,
          height: 500,
          child: ListView(
            children: [
              Text(
                'Paper Sizes (${capabilities.paperSizes.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final paper in capabilities.paperSizes)
                ListTile(
                  dense: true,
                  title: Text(paper.name),
                  subtitle: Text(
                    'ID: ${paper.id}, ${paper.widthMillimeters.toStringAsFixed(1)} x ${paper.heightMillimeters.toStringAsFixed(1)} mm',
                  ),
                ),
              const Divider(),
              Text(
                'Paper Sources (${capabilities.paperSources.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final paper in capabilities.paperSources)
                ListTile(
                  dense: true,
                  title: Text(paper.name),
                  subtitle: Text(paper.toString()),
                ),
              const Divider(),
              Text(
                'Media Types (${capabilities.mediaTypes.length})',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final media in capabilities.mediaTypes)
                ListTile(
                  dense: true,
                  title: Text(media.name),
                  subtitle: Text('ID: ${media.id}'),
                ),
              const Divider(),
              Text(
                'Supported Resolutions',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final res in capabilities.resolutions)
                ListTile(title: Text(res.toString())),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Printing FFI Example'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_outlined),
              onPressed: _refreshPrinters,
            ),
          ],
          bottom: _selectedPrinter != null
              ? TabBar(
                  // onTap: (index) => setState(() => _tabIndex = index),
                  tabs: const [
                    Tab(icon: Icon(Icons.print_outlined), text: 'Standard'),
                    Tab(
                      icon: Icon(Icons.settings_applications),
                      text: 'Advanced (CUPS)',
                    ),
                  ],
                )
              : null,
        ),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPrinterSelector(),
              const SizedBox(height: 20),
              if (_selectedPrinter != null)
                Expanded(
                  child: TabBarView(
                    physics: const NeverScrollableScrollPhysics(),
                    children: [_buildSimpleTab(), _buildAdvancedTab()],
                  ),
                ),
              if (_isLoadingPrinters)
                const Center(child: CircularProgressIndicator()),
              if (!_isLoadingPrinters && _printers.isEmpty)
                const Center(
                  child: Text('No printers found. Press refresh to try again.'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSimpleTab() {
    return ListView(
      children: [
        StandardActionsCard(
          selectedScaling: _selectedScaling,
          onScalingChanged: (newSelection) {
            setState(() {
              _selectedScaling = newSelection.first;
            });
          },
          customScaleController: _customScaleController,
          selectedPdfPath: _selectedPdfPath,
          onClearPdfPath: () {
            setState(() {
              _selectedPdfPath = null;
            });
          },
          onPrintPdf:
              ({cupsOptions, required copies, required pageRangeString}) {
                _printPdf(
                  cupsOptions: cupsOptions,
                  copies: copies,
                  pageRangeString: pageRangeString,
                );
              },
          copiesController: _copiesController,
          pageRangeController: _pageRangeController,
          collate: _collate,
          onCollateChanged: (v) => setState(() => _collate = v),
          onPrintPdfAndTrack: _printPdfAndTrack,
          onShowWindowsCapabilities: _showWindowsCapabilities,
          rawDataController: _rawDataController,
          onPrintRawData: _printRawData,
          onPrintRawDataAndTrack: _printRawDataAndTrack,
          platformSettings: _buildPlatformSettings(),
        ),
        const SizedBox(height: 20),
        JobsList(
          isLoading: _isLoadingJobs,
          jobs: _jobs,
          onManageJob: _manageJob,
        ),
      ],
    );
  }

  Widget _buildPrinterSelector() {
    return PrinterSelector(
      printers: _printers,
      selectedPrinter: _selectedPrinter,
      onChanged: _onPrinterSelected,
    );
  }

  Widget _buildPlatformSettings() {
    return PlatformSettings(
      isLoading: _isLoadingWindowsCaps,
      windowsCapabilities: _windowsCapabilities,
      selectedPaperSize: _selectedPaperSize,
      onPaperSizeChanged: (p) => setState(() => _selectedPaperSize = p),
      selectedPaperSource: _selectedPaperSource,
      onPaperSourceChanged: (s) => setState(() => _selectedPaperSource = s),
      selectedAlignment: _selectedAlignment,
      onAlignmentChanged: (a) =>
          setState(() => _selectedAlignment = a ?? PdfPrintAlignment.center),
      selectedPrintQuality: _selectedPrintQuality,
      onPrintQualityChanged: (q) =>
          setState(() => _selectedPrintQuality = q ?? PrintQuality.normal),
      selectedColorMode: _selectedColorMode,
      onColorModeChanged: (c) =>
          setState(() => _selectedColorMode = c ?? ColorMode.color),
      selectedOrientation: _selectedOrientation,
      onOrientationChanged: (o) => setState(
        () => _selectedOrientation = o ?? WindowsOrientation.portrait,
      ),
      onOpenProperties: () async {
        if (_selectedPrinter == null) return;
        try {
          final result = await openPrinterProperties(
            _selectedPrinter!.name,
            hwnd: 0,
          );
          if (!mounted) return;
          switch (result) {
            case PrinterPropertiesResult.ok:
              _showSnackbar('Printer properties updated successfully.');
              _fetchWindowsCapabilities();
              break;
            case PrinterPropertiesResult.cancel:
              _showSnackbar(
                'Printer properties dialog was cancelled.',
                isError: false,
              );
              break;
            case PrinterPropertiesResult.error:
              _showSnackbar(
                'Could not open printer properties.',
                isError: true,
              );
              break;
          }
        } catch (e) {
          _showSnackbar('Error opening properties: $e', isError: true);
        }
      },
      onShowCapabilities: _showWindowsCapabilities,
    );
  }

  Widget _buildAdvancedTab() {
    return AdvancedTab(
      isLoading: _isLoadingCupsOptions,
      cupsOptions: _cupsOptions,
      selectedCupsOptions: _selectedCupsOptions,
      onOptionChanged: (key, value) {
        setState(() {
          _selectedCupsOptions[key] = value;
        });
      },
      onPrint: () => _printPdf(
        cupsOptions: _selectedCupsOptions,
        copies: int.tryParse(_copiesController.text) ?? 1,
        pageRangeString: _pageRangeController.text,
      ),
    );
  }
}
