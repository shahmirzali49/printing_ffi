import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing_ffi/printing_ffi.dart';

extension ColorExt on Color {
  /// Flutter 3.29, Migration helper for withOpacity Function
  Color withOpacityx(double value) {
    return withValues(alpha: value);
  }
}

void main() {
  runApp(const PrintingFfiExampleApp());
}

class PrintingFfiExampleApp extends StatelessWidget {
  const PrintingFfiExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Printing FFI Example',
      theme: ThemeData(
        primarySwatch: Colors.blueGrey,
        useMaterial3: true,
        brightness: Brightness.light,
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      home: const PrintingScreen(),
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

  bool _isLoadingPrinters = false;
  bool _isLoadingJobs = false;
  bool _isLoadingCupsOptions = false;
  bool _isLoadingWindowsCaps = false;

  final TextEditingController _rawDataController = TextEditingController(
    text: 'Hello, FFI!',
  );
  PdfPrintScaling _selectedScaling = PdfPrintScaling.fitPage;
  final TextEditingController _copiesController = TextEditingController(
    text: '1',
  );
  final TextEditingController _pageRangeController = TextEditingController();

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

  List<PrintOption> _buildPrintOptions({Map<String, String>? cupsOptions}) {
    final options = <PrintOption>[];
    if (Platform.isWindows) {
      if (_selectedPaperSize != null) {
        options.add(WindowsPaperSizeOption(_selectedPaperSize!.id));
      }
      if (_selectedPaperSource != null) {
        options.add(WindowsPaperSourceOption(_selectedPaperSource!.id));
      }
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
    return options;
  }

  Future<void> _printPdf({
    Map<String, String>? cupsOptions,
    required PdfPrintScaling scaling,
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
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      try {
        final options = _buildPrintOptions(cupsOptions: cupsOptions);
        _showSnackbar('Printing PDF...');
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
        } else {
          _showSnackbar(
            'Failed to print PDF. The printer may be offline or the page range may be invalid for the document.',
            isError: true,
          );
        }
      } on ArgumentError catch (e) {
        _showSnackbar('Invalid argument: ${e.message}', isError: true);
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
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null && result.files.single.path != null) {
      final copies = int.tryParse(_copiesController.text) ?? 1;
      final pageRangeString = _pageRangeController.text;
      final path = result.files.single.path!;
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
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _PrintStatusDialog(
          printerName: _selectedPrinter!.name,
          jobStream: printPdfAndStreamStatus(
            _selectedPrinter!.name,
            path,
            options: options,
            scaling: _selectedScaling,
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
      builder: (context) => _PrintStatusDialog(
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
        _buildStandardActions(),
        const SizedBox(height: 20),
        _buildJobsList(),
      ],
    );
  }

  Widget _buildPrinterSelector() {
    return Row(
      children: [
        const Text('Printer:', style: TextStyle(fontSize: 16)),
        const SizedBox(width: 10),
        Expanded(
          child: DropdownButton<Printer>(
            value: _selectedPrinter,
            isExpanded: true,
            items: _printers
                .map((p) => DropdownMenuItem(value: p, child: Text(p.name)))
                .toList(),
            onChanged: _onPrinterSelected,
            hint: const Text('Select a printer'),
          ),
        ),
      ],
    );
  }

  Widget _buildStandardActions() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Standard Actions',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            _buildPlatformSettings(),
            const SizedBox(height: 16),
            Center(
              child: Column(
                children: [
                  if (Platform.isWindows) ...[
                    SegmentedButton<PdfPrintScaling>(
                      segments: const [
                        ButtonSegment(
                          value: PdfPrintScaling.fitPage,
                          label: Text('Fit to Page'),
                        ),
                        ButtonSegment(
                          value: PdfPrintScaling.actualSize,
                          label: Text('Actual Size'),
                        ),
                      ],
                      selected: {_selectedScaling},
                      onSelectionChanged: (newSelection) {
                        setState(() {
                          _selectedScaling = newSelection.first;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  ElevatedButton.icon(
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('Print a PDF File'),
                    onPressed: () => _printPdf(
                      scaling: _selectedScaling,
                      copies: int.tryParse(_copiesController.text) ?? 1,
                      pageRangeString: _pageRangeController.text,
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _copiesController,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'Copies',
                            ),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _pageRangeController,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              labelText: 'Page Range',
                              hintText: 'e.g. 1-3, 5, 7-9',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Leave page range blank to print all pages.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.track_changes),
                    label: const Text('Print PDF and Track Status'),
                    onPressed: _printPdfAndTrack,
                  ),
                  if (Platform.isWindows) ...[
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: const Text('Show Printer Capabilities'),
                      onPressed: _showWindowsCapabilities,
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 32),
            Text(
              'Raw Data (ZPL Example)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _rawDataController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Text to print',
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.data_object),
                label: const Text('Print Raw Data'),
                onPressed: _printRawData,
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.track_changes),
                label: const Text('Print Raw Data and Track'),
                onPressed: _printRawDataAndTrack,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlatformSettings() {
    return Padding(
      padding: const EdgeInsets.only(top: 16.0),
      child: Card(
        elevation: 1,
        color: Theme.of(
          context,
        ).colorScheme.secondaryContainer.withOpacityx(0.3),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Platform Settings',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              if (Platform.isWindows) ...[
                if (_isLoadingWindowsCaps)
                  const Center(child: CircularProgressIndicator())
                else if (_windowsCapabilities != null) ...[
                  DropdownButtonFormField<WindowsPaperSize>(
                    initialValue: _selectedPaperSize,
                    decoration: const InputDecoration(
                      labelText: 'Paper Size (Windows)',
                      border: OutlineInputBorder(),
                    ),
                    items: _windowsCapabilities!.paperSizes
                        .map(
                          (p) =>
                              DropdownMenuItem(value: p, child: Text(p.name)),
                        )
                        .toList(),
                    onChanged: (p) => setState(() => _selectedPaperSize = p),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<WindowsPaperSource>(
                    initialValue: _selectedPaperSource,
                    decoration: const InputDecoration(
                      labelText: 'Paper Source (Windows)',
                      border: OutlineInputBorder(),
                    ),
                    items: _windowsCapabilities!.paperSources
                        .map(
                          (s) =>
                              DropdownMenuItem(value: s, child: Text(s.name)),
                        )
                        .toList(),
                    onChanged: (s) => setState(() => _selectedPaperSource = s),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
              DropdownButtonFormField<PrintQuality>(
                initialValue: _selectedPrintQuality,
                decoration: const InputDecoration(
                  labelText: 'Print Quality',
                  border: OutlineInputBorder(),
                ),
                items: PrintQuality.values
                    .map(
                      (q) => DropdownMenuItem(
                        value: q,
                        child: Text(
                          q.name[0].toUpperCase() + q.name.substring(1),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (q) => setState(
                  () => _selectedPrintQuality = q ?? PrintQuality.normal,
                ),
              ),
              const SizedBox(height: 12),
              Tooltip(
                message:
                    'Options may be disabled if the printer does not report support. If capabilities are unknown, all options are enabled.',
                child: DropdownButtonFormField<ColorMode>(
                  initialValue: _selectedColorMode,
                  decoration: const InputDecoration(
                    labelText: 'Color Mode',
                    border: OutlineInputBorder(),
                  ),
                  items: ColorMode.values
                      .map(
                        (c) => DropdownMenuItem(
                          value: c,
                          enabled:
                              (c == ColorMode.color &&
                                  (_windowsCapabilities?.isColorSupported ??
                                      true)) ||
                              (c == ColorMode.monochrome &&
                                  (_windowsCapabilities
                                          ?.isMonochromeSupported ??
                                      true)),
                          child: Text(
                            c.name[0].toUpperCase() + c.name.substring(1),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (c) =>
                      setState(() => _selectedColorMode = c ?? ColorMode.color),
                ),
              ),
              const SizedBox(height: 12),
              Tooltip(
                message:
                    'Options may be disabled if the printer does not report support. If capabilities are unknown, all options are enabled.',
                child: DropdownButtonFormField<WindowsOrientation>(
                  initialValue: _selectedOrientation,
                  decoration: const InputDecoration(
                    labelText: 'Orientation',
                    border: OutlineInputBorder(),
                  ),
                  items: WindowsOrientation.values
                      .map(
                        (o) => DropdownMenuItem(
                          value: o,
                          child: Text(
                            o.name[0].toUpperCase() + o.name.substring(1),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (o) => setState(
                    () =>
                        _selectedOrientation = o ?? WindowsOrientation.portrait,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Open Printer Properties'),
                  onPressed: () async {
                    if (_selectedPrinter == null) return;
                    try {
                      // For a real app, you might use the `win32` package
                      // to get the handle of the main window. For this
                      // example, 0 (NULL) is sufficient.
                      final result = await openPrinterProperties(
                        _selectedPrinter!.name,
                        hwnd: 0,
                      );
                      if (!mounted) return;
                      switch (result) {
                        case PrinterPropertiesResult.ok:
                          _showSnackbar(
                            'Printer properties updated successfully.',
                          );
                          // Refresh capabilities to reflect any changes made.
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
                      _showSnackbar(
                        'Error opening properties: $e',
                        isError: true,
                      );
                    }
                  },
                ),
              ),
              const SizedBox(height: 12),
              if (Platform.isWindows)
                Center(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: const Text('Show All Capabilities'),
                    onPressed: _showWindowsCapabilities,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildJobsList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Print Queue',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ],
        ),
        if (_isLoadingJobs) const Center(child: CircularProgressIndicator()),
        if (!_isLoadingJobs && _jobs.isEmpty)
          const Text('No active print jobs.'),
        if (!_isLoadingJobs && _jobs.isNotEmpty)
          SizedBox(
            height: 200,
            child: ListView.builder(
              itemCount: _jobs.length,
              itemBuilder: (context, index) {
                final job = _jobs[index];
                return Card(
                  child: ListTile(
                    title: Text(job.title),
                    subtitle: Text(
                      'ID: ${job.id} - Status: ${job.statusDescription}',
                    ),
                    trailing: Wrap(
                      spacing: 0,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.pause),
                          onPressed: () => _manageJob(job.id, 'pause'),
                        ),
                        IconButton(
                          icon: const Icon(Icons.play_arrow),
                          onPressed: () => _manageJob(job.id, 'resume'),
                        ),
                        IconButton(
                          icon: const Icon(Icons.cancel),
                          onPressed: () => _manageJob(job.id, 'cancel'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildAdvancedTab() {
    if (!Platform.isMacOS && !Platform.isLinux) {
      return const Center(
        child: Text(
          'Advanced CUPS options are only available on macOS and Linux.',
        ),
      );
    }
    return ListView(
      children: [
        Text('CUPS Options', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 10),
        if (_isLoadingCupsOptions)
          const Center(child: CircularProgressIndicator()),
        if (!_isLoadingCupsOptions &&
            (_cupsOptions == null || _cupsOptions!.isEmpty))
          const Text('No CUPS options found for this printer.'),
        if (!_isLoadingCupsOptions &&
            _cupsOptions != null &&
            _cupsOptions!.isNotEmpty) ...[
          ..._buildCupsOptionWidgets(),
          const SizedBox(height: 20),
          Center(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Print PDF with Selected Options'),
              onPressed: () => _printPdf(
                cupsOptions: _selectedCupsOptions,
                scaling: _selectedScaling,
                copies: int.tryParse(_copiesController.text) ?? 1,
                pageRangeString: _pageRangeController.text,
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _buildCupsOptionWidgets() {
    if (_cupsOptions == null) return [];
    return _cupsOptions!.map((option) {
      final currentValue = _selectedCupsOptions[option.name];
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                flex: 2,
                child: Text(
                  option.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 3,
                child: DropdownButton<String>(
                  value: currentValue,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  items: option.supportedValues.map((choice) {
                    return DropdownMenuItem<String>(
                      value: choice.choice,
                      child: Tooltip(
                        message: choice.text,
                        child: Text(
                          choice.text,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (newValue) {
                    if (newValue != null) {
                      setState(
                        () => _selectedCupsOptions[option.name] = newValue,
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }
}

class _PrintStatusDialog extends StatefulWidget {
  const _PrintStatusDialog({
    required this.jobStream,
    required this.printerName,
  });

  final Stream<PrintJob> jobStream;
  final String printerName;

  @override
  State<_PrintStatusDialog> createState() => _PrintStatusDialogState();
}

class _PrintStatusDialogState extends State<_PrintStatusDialog> {
  StreamSubscription<PrintJob>? _subscription;
  PrintJob? _job;
  Object? _error;
  bool _isDone = false;
  bool _isCancelling = false;

  @override
  void initState() {
    super.initState();
    _subscription = widget.jobStream.listen(
      (job) {
        if (mounted) setState(() => _job = job);
      },
      onError: (error) {
        if (mounted) setState(() => _error = error);
      },
      onDone: () {
        if (mounted) {
          setState(() => _isDone = true);
        }
      },
    );
  }

  Future<void> _cancelJob() async {
    if (_job == null || !mounted) return;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isCancelling = true);
    try {
      final success = await cancelPrintJob(widget.printerName, _job!.id);

      // After the await, the widget might have been disposed.
      if (!mounted) return;

      if (success) {
        // If successful, pop the dialog and show a confirmation snackbar.
        navigator.pop();
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Cancel command sent successfully.'),
            backgroundColor: Colors.blue,
          ),
        );
      } else {
        navigator.pop();
        // If failed, stay on the dialog and show an error.
        setState(() => _isCancelling = false);
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Failed to send cancel command.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCancelling = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Error cancelling job: $e')),
      );
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isJobTerminal =
        _job != null &&
        (_job!.status == PrintJobStatus.completed ||
            _job!.status == PrintJobStatus.canceled ||
            _job!.status == PrintJobStatus.aborted ||
            _job!.status == PrintJobStatus.error);

    // If the stream is done but we never got a job object, it means the job
    // completed so quickly it was never seen in the queue. We can treat this
    // as a successful completion.
    final isImplicitlyComplete = _isDone && _job == null && _error == null;

    final canCancel = !_isCancelling && !isJobTerminal && !_isDone;

    Widget content;
    if (_error != null) {
      content = Text(
        'Error: $_error',
        style: const TextStyle(color: Colors.red),
      );
    } else if (isImplicitlyComplete) {
      content = Text(
        'Job Completed',
        style: Theme.of(context).textTheme.titleMedium,
      );
    } else if (_job == null) {
      content = const CircularProgressIndicator();
    } else {
      content = Text(
        'Job #${_job!.id}: ${_job!.statusDescription}',
        style: Theme.of(context).textTheme.titleMedium,
      );
    }

    return AlertDialog(
      title: const Text('Tracking Print Job...'),
      content: SizedBox(width: 250, height: 100, child: Center(child: content)),
      actions: <Widget>[
        if (isJobTerminal || _error != null || isImplicitlyComplete)
          TextButton(
            child: const Text('Close'),
            onPressed: () => Navigator.of(context).pop(),
          )
        else
          TextButton(
            onPressed: canCancel ? _cancelJob : null,
            child: _isCancelling
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  )
                : const Text('Cancel'),
          ),
      ],
    );
  }
}
