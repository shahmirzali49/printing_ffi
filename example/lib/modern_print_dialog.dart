import 'dart:io';
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing_ffi/printing_ffi.dart';

/// A local helper class to represent the custom scaling option in the UI.
/// This is a marker class for the SegmentedButton.
class CustomScaling {
  const CustomScaling();
}

class ModernPrintDialog extends StatefulWidget {
  final String pdfPath;
  final String fileName;

  const ModernPrintDialog({
    super.key,
    required this.pdfPath,
    required this.fileName,
  });

  @override
  State<ModernPrintDialog> createState() => _ModernPrintDialogState();
}

class _ModernPrintDialogState extends State<ModernPrintDialog> {
  List<Printer> _printers = [];
  Printer? _selectedPrinter;
  bool _isLoadingPrinters = false;
  bool _isLoadingCapabilities = false;
  WindowsPrinterCapabilitiesModel? _windowsCapabilities;

  // Print options
  WindowsPaperSize? _selectedPaperSize;
  WindowsPaperSource? _selectedPaperSource;
  WindowsOrientation _selectedOrientation = WindowsOrientation.portrait;
  ColorMode _selectedColorMode = ColorMode.color;
  PrintQuality _selectedPrintQuality = PrintQuality.normal;
  PdfPrintAlignment _selectedAlignment = PdfPrintAlignment.center;
  DuplexMode _selectedDuplexMode = DuplexMode.singleSided;
  bool _collate = true;

  // PDF settings
  Object _selectedScaling = PdfPrintScaling.fitToPrintableArea;
  final TextEditingController _customScaleController = TextEditingController(
    text: '1.0',
  );
  final TextEditingController _pageRangeController = TextEditingController();
  String? _selectedPdfPath;

  // Print jobs
  List<PrintJob> _jobs = [];
  StreamSubscription<List<PrintJob>>? _jobsSubscription;
  bool _isLoadingJobs = false;

  // CUPS options
  List<CupsOptionModel>? _cupsOptions;
  Map<String, String> _selectedCupsOptions = {};
  bool _isLoadingCupsOptions = false;

  final TextEditingController _copiesController = TextEditingController(
    text: '1',
  );

  @override
  void initState() {
    super.initState();
    _initializePrinting();
  }

  @override
  void dispose() {
    _copiesController.dispose();
    _customScaleController.dispose();
    _pageRangeController.dispose();
    _jobsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initializePrinting() async {
    setState(() {
      _isLoadingPrinters = true;
      _printers = [];
      _selectedPrinter = null;
      _windowsCapabilities = null;
      _selectedPaperSize = null;
      _selectedPaperSource = null;
      _selectedOrientation = WindowsOrientation.portrait;
      _selectedColorMode = ColorMode.color;
      _selectedPrintQuality = PrintQuality.normal;
      _selectedAlignment = PdfPrintAlignment.center;
      _selectedDuplexMode = DuplexMode.singleSided;
      _collate = true;
      _selectedScaling = PdfPrintScaling.fitToPrintableArea;
      _selectedPdfPath = null;
      _jobs = [];
      _cupsOptions = null;
      _selectedCupsOptions = {};
    });

    try {
      final printers = PrintingFfi.instance.listPrinters();
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
      _showErrorSnackbar('Failed to get printers: $e');
    } finally {
      setState(() => _isLoadingPrinters = false);
    }
  }

  void _onPrinterSelected(Printer? printer) {
    if (printer == null) return;

    setState(() {
      _selectedPrinter = printer;
      _isLoadingCapabilities = true;
      _windowsCapabilities = null;
      _selectedPaperSize = null;
      _selectedPaperSource = null;
    });

    _fetchWindowsCapabilities();
    _subscribeToJobs();
    _fetchCupsOptions();
  }

  Future<void> _fetchWindowsCapabilities() async {
    if (_selectedPrinter == null || !Platform.isWindows) {
      setState(() => _isLoadingCapabilities = false);
      return;
    }

    try {
      final caps = await PrintingFfi.instance.getWindowsPrinterCapabilities(
        _selectedPrinter!.name,
      );
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
        _isLoadingCapabilities = false;
      });
    } catch (e) {
      if (!mounted) return;
      _showErrorSnackbar('Failed to get printer capabilities: $e');
      setState(() => _isLoadingCapabilities = false);
    }
  }

  ({PageRange? pageRange, PdfPrintScaling? scaling})? _parsePrintJobSettings() {
    // Parse Page Range
    final pageRangeString = _pageRangeController.text;
    PageRange? pageRange;
    if (pageRangeString.trim().isNotEmpty) {
      try {
        pageRange = PageRange.parse(pageRangeString);
      } on ArgumentError catch (e) {
        _showErrorSnackbar('Invalid page range: ${e.message}');
        return null;
      }
    }

    // Parse Scaling
    final PdfPrintScaling scaling;
    if (_selectedScaling is CustomScaling) {
      final scaleValue = double.tryParse(_customScaleController.text);
      if (scaleValue == null || scaleValue <= 0) {
        _showErrorSnackbar(
          'Invalid custom scale value. It must be a positive number.',
        );
        return null;
      }
      scaling = PdfPrintScaling.custom(scaleValue);
    } else {
      scaling = _selectedScaling as PdfPrintScaling;
    }
    return (pageRange: pageRange, scaling: scaling);
  }

  Future<void> _printPdf() async {
    if (_selectedPrinter == null) {
      _showErrorSnackbar('No printer selected!');
      return;
    }

    final path = await _getPdfPath();
    if (path == null) {
      _showErrorSnackbar('Please select a PDF file to print');
      return;
    }

    final settings = _parsePrintJobSettings();
    if (settings == null) return;

    final copies = int.tryParse(_copiesController.text) ?? 1;
    if (copies < 1) {
      _showErrorSnackbar('Copies must be at least 1');
      return;
    }

    try {
      final options = _buildPrintOptions(cupsOptions: _selectedCupsOptions);

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => PrintStatusDialog(
          printerName: _selectedPrinter!.name,
          jobStream: PrintingFfi.instance.printPdfAndStreamStatus(
            _selectedPrinter!.name,
            path,
            options: options,
            scaling: settings.scaling!,
            copies: copies,
            pageRange: settings.pageRange,
          ),
        ),
      );
    } on PrintingFfiException catch (e) {
      _showErrorSnackbar('Failed to print PDF: ${e.message}');
    } catch (e) {
      _showErrorSnackbar('An unexpected error occurred: $e');
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
      options.add(AlignmentOption(_selectedAlignment));
    }

    options.add(OrientationOption(_selectedOrientation));
    options.add(ColorModeOption(_selectedColorMode));
    options.add(PrintQualityOption(_selectedPrintQuality));
    options.add(DuplexOption(_selectedDuplexMode));
    options.add(CollateOption(_collate));

    if (cupsOptions != null) {
      cupsOptions.forEach((key, value) {
        options.add(GenericCupsOption(key, value));
      });
    }

    return options;
  }

  Future<void> _showPrinterCapabilities() async {
    if (_selectedPrinter == null || !Platform.isWindows) return;

    final capabilities = await PrintingFfi.instance
        .getWindowsPrinterCapabilities(_selectedPrinter!.name);
    if (!mounted) return;

    if (capabilities == null) {
      _showErrorSnackbar('Could not retrieve capabilities for this printer.');
      return;
    }

    showDialog(
      context: context,
      builder: (context) => _CapabilitiesDialog(
        printerName: _selectedPrinter!.name,
        capabilities: capabilities,
      ),
    );
  }

  void _subscribeToJobs() {
    if (_selectedPrinter == null) return;
    _jobsSubscription?.cancel();
    setState(() => _isLoadingJobs = true);
    _jobsSubscription = PrintingFfi.instance
        .listPrintJobsStream(_selectedPrinter!.name)
        .listen(
          (jobs) {
            if (!mounted) return;
            setState(() {
              _jobs = jobs;
              _isLoadingJobs = false;
            });
          },
          onError: (e) {
            if (!mounted) return;
            _showErrorSnackbar('Error fetching jobs: $e');
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
      final options = await PrintingFfi.instance.getSupportedCupsOptions(
        _selectedPrinter!.name,
      );
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
      _showErrorSnackbar('Failed to get CUPS options: $e');
    } finally {
      if (mounted) setState(() => _isLoadingCupsOptions = false);
    }
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

  Future<void> _manageJob(int jobId, String action) async {
    if (_selectedPrinter == null) return;
    bool success = false;
    try {
      switch (action) {
        case 'pause':
          success = await PrintingFfi.instance.pausePrintJob(
            _selectedPrinter!.name,
            jobId,
          );
          break;
        case 'resume':
          success = await PrintingFfi.instance.resumePrintJob(
            _selectedPrinter!.name,
            jobId,
          );
          break;
        case 'cancel':
          success = await PrintingFfi.instance.cancelPrintJob(
            _selectedPrinter!.name,
            jobId,
          );
          break;
      }
      if (!mounted) return;
      _showSuccessSnackbar('Job $action ${success ? 'succeeded' : 'failed'}.');
    } catch (e) {
      _showErrorSnackbar('Error managing job: $e');
    }
  }

  Future<void> _refreshPrinters() async {
    await _initializePrinting();
  }

  Future<void> _openPrinterProperties() async {
    if (_selectedPrinter == null) return;

    try {
      final result = await PrintingFfi.instance.openPrinterProperties(
        _selectedPrinter!.name,
        hwnd: 0,
      );

      if (!mounted) return;

      switch (result) {
        case PrinterPropertiesResult.ok:
          _showSuccessSnackbar('Printer properties updated successfully.');
          _fetchWindowsCapabilities();
          break;
        case PrinterPropertiesResult.cancel:
          _showInfoSnackbar('Printer properties dialog was cancelled.');
          break;
        case PrinterPropertiesResult.error:
          _showErrorSnackbar('Could not open printer properties.');
          break;
      }
    } catch (e) {
      _showErrorSnackbar('Error opening properties: $e');
    }
  }

  void _showErrorSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccessSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showInfoSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_isLoadingPrinters)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_printers.isEmpty)
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            children: [
                              Icon(
                                Icons.print_disabled,
                                size: 48,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withOpacity(0.5),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No printers found',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withOpacity(0.7),
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Please make sure you have printers installed and try again.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurface.withOpacity(0.5),
                                    ),
                              ),
                              const SizedBox(height: 24),
                              ElevatedButton.icon(
                                onPressed: _refreshPrinters,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Retry'),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final bool isWide = constraints.maxWidth >= 720;
                          if (!isWide) {
                            return Column(
                              children: [
                                _buildPrinterSelection(),
                                const SizedBox(height: 16),
                                _buildPrintSettings(),
                                const SizedBox(height: 16),
                                _buildJobsList(),
                              ],
                            );
                          }

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 5,
                                child: Column(
                                  children: [
                                    _buildPrinterSelection(),
                                    const SizedBox(height: 16),
                                    _buildJobsList(),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(flex: 7, child: _buildPrintSettings()),
                            ],
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.print,
              color: Theme.of(context).colorScheme.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Print Document',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.fileName,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withOpacity(0.7),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrinterSelection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Printer Selection',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Printer>(
              value: _selectedPrinter,
              decoration: const InputDecoration(
                labelText: 'Select Printer',
                border: OutlineInputBorder(),
              ),
              items: _printers.map((printer) {
                return DropdownMenuItem(
                  value: printer,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        printer.isDefault ? Icons.star : Icons.print,
                        size: 16,
                        color: printer.isDefault ? Colors.amber : null,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          printer.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: _onPrinterSelected,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _refreshPrinters,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Refresh'),
                  ),
                ),
                const SizedBox(width: 8),
                if (Platform.isWindows) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _openPrinterProperties,
                      icon: const Icon(Icons.settings, size: 16),
                      label: const Text('Properties'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _showPrinterCapabilities,
                      icon: const Icon(Icons.info, size: 16),
                      label: const Text('Capabilities'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrintSettings() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Print Settings',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),

            // PDF File Selection
            if (_selectedPdfPath != null)
              ListTile(
                leading: const Icon(Icons.picture_as_pdf),
                title: const Text('Selected PDF:'),
                subtitle: Text(
                  _selectedPdfPath!.split(Platform.pathSeparator).last,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    setState(() => _selectedPdfPath = null);
                  },
                ),
              ),

            // PDF Scaling Options
            if (Platform.isWindows) ...[
              Text(
                'PDF Scaling',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              SegmentedButton<Object>(
                segments: const <ButtonSegment<Object>>[
                  ButtonSegment(
                    value: PdfPrintScaling.fitToPrintableArea,
                    label: Text('Fit'),
                  ),
                  ButtonSegment(
                    value: PdfPrintScaling.actualSize,
                    label: Text('Actual'),
                  ),
                  ButtonSegment(
                    value: PdfPrintScaling.shrinkToFit,
                    label: Text('Shrink'),
                  ),
                  ButtonSegment(
                    value: PdfPrintScaling.fitToPaper,
                    label: Text('Paper'),
                  ),
                  ButtonSegment(value: CustomScaling(), label: Text('Custom')),
                ],
                selected: {_selectedScaling},
                onSelectionChanged: (newSelection) {
                  setState(() {
                    _selectedScaling = newSelection.first;
                  });
                },
              ),
              if (_selectedScaling is CustomScaling) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _customScaleController,
                  decoration: const InputDecoration(
                    labelText: 'Custom Scale',
                    border: OutlineInputBorder(),
                    hintText: '1.0',
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
              const SizedBox(height: 16),
            ],

            // Page Range
            TextFormField(
              controller: _pageRangeController,
              decoration: const InputDecoration(
                labelText: 'Page Range (e.g. 1-3, 5)',
                border: OutlineInputBorder(),
                hintText: 'Leave empty for all pages',
              ),
            ),
            const SizedBox(height: 16),

            // Copies
            TextFormField(
              controller: _copiesController,
              decoration: const InputDecoration(
                labelText: 'Copies',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),

            // Collate
            CheckboxListTile(
              title: const Text('Collate copies'),
              subtitle: const Text('Print complete copies together'),
              value: _collate,
              onChanged: (value) {
                setState(() => _collate = value ?? true);
              },
              controlAffinity: ListTileControlAffinity.leading,
            ),

            // Windows-specific settings
            if (Platform.isWindows) ...[
              if (_isLoadingCapabilities)
                const Center(child: CircularProgressIndicator())
              else if (_windowsCapabilities != null) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  'Advanced Settings',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),

                // Paper Size
                if (_windowsCapabilities!.paperSizes.isNotEmpty)
                  DropdownButtonFormField<WindowsPaperSize>(
                    value: _selectedPaperSize,
                    decoration: const InputDecoration(
                      labelText: 'Paper Size',
                      border: OutlineInputBorder(),
                    ),
                    items: _windowsCapabilities!.paperSizes.map((paper) {
                      return DropdownMenuItem(
                        value: paper,
                        child: Text(paper.name),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() => _selectedPaperSize = value);
                    },
                  ),

                const SizedBox(height: 12),

                // Paper Source
                if (_windowsCapabilities!.paperSources.isNotEmpty)
                  DropdownButtonFormField<WindowsPaperSource>(
                    value: _selectedPaperSource,
                    decoration: const InputDecoration(
                      labelText: 'Paper Source',
                      border: OutlineInputBorder(),
                    ),
                    items: _windowsCapabilities!.paperSources.map((source) {
                      return DropdownMenuItem(
                        value: source,
                        child: Text(source.name),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() => _selectedPaperSource = value);
                    },
                  ),

                const SizedBox(height: 12),

                // Alignment
                DropdownButtonFormField<PdfPrintAlignment>(
                  value: _selectedAlignment,
                  decoration: const InputDecoration(
                    labelText: 'Alignment',
                    border: OutlineInputBorder(),
                  ),
                  items: PdfPrintAlignment.values.map((alignment) {
                    return DropdownMenuItem(
                      value: alignment,
                      child: Text(
                        alignment.name[0].toUpperCase() +
                            alignment.name.substring(1),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(
                      () => _selectedAlignment =
                          value ?? PdfPrintAlignment.center,
                    );
                  },
                ),

                const SizedBox(height: 12),

                // Orientation
                DropdownButtonFormField<WindowsOrientation>(
                  value: _selectedOrientation,
                  decoration: const InputDecoration(
                    labelText: 'Orientation',
                    border: OutlineInputBorder(),
                  ),
                  items: WindowsOrientation.values.map((orientation) {
                    return DropdownMenuItem(
                      value: orientation,
                      child: Text(orientation.name.toUpperCase()),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(
                      () => _selectedOrientation =
                          value ?? WindowsOrientation.portrait,
                    );
                  },
                ),

                const SizedBox(height: 12),

                // Color Mode
                DropdownButtonFormField<ColorMode>(
                  value: _selectedColorMode,
                  decoration: const InputDecoration(
                    labelText: 'Color Mode',
                    border: OutlineInputBorder(),
                  ),
                  items: ColorMode.values.map((mode) {
                    return DropdownMenuItem(
                      value: mode,
                      child: Text(mode.name.toUpperCase()),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(
                      () => _selectedColorMode = value ?? ColorMode.color,
                    );
                  },
                ),

                const SizedBox(height: 12),

                // Print Quality
                DropdownButtonFormField<PrintQuality>(
                  value: _selectedPrintQuality,
                  decoration: const InputDecoration(
                    labelText: 'Print Quality',
                    border: OutlineInputBorder(),
                  ),
                  items: PrintQuality.values.map((quality) {
                    return DropdownMenuItem(
                      value: quality,
                      child: Text(quality.name.toUpperCase()),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(
                      () =>
                          _selectedPrintQuality = value ?? PrintQuality.normal,
                    );
                  },
                ),

                const SizedBox(height: 12),

                // Duplex Mode
                DropdownButtonFormField<DuplexMode>(
                  value: _selectedDuplexMode,
                  decoration: const InputDecoration(
                    labelText: 'Duplex Mode',
                    border: OutlineInputBorder(),
                  ),
                  items: DuplexMode.values.map((mode) {
                    return DropdownMenuItem(
                      value: mode,
                      child: Text(_getDuplexModeDisplayName(mode)),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(
                      () =>
                          _selectedDuplexMode = value ?? DuplexMode.singleSided,
                    );
                  },
                ),
              ],
            ],

            // CUPS Options for macOS/Linux
            if (Platform.isMacOS || Platform.isLinux) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'CUPS Options',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              if (_isLoadingCupsOptions)
                const Center(child: CircularProgressIndicator())
              else if (_cupsOptions == null || _cupsOptions!.isEmpty)
                const Text('No CUPS options found for this printer.')
              else
                ..._buildCupsOptionWidgets(),
            ],
          ],
        ),
      ),
    );
  }

  String _getDuplexModeDisplayName(DuplexMode mode) {
    switch (mode) {
      case DuplexMode.singleSided:
        return 'Single-sided';
      case DuplexMode.duplexLongEdge:
        return 'Duplex (Long Edge)';
      case DuplexMode.duplexShortEdge:
        return 'Duplex (Short Edge)';
    }
  }

  List<Widget> _buildCupsOptionWidgets() {
    if (_cupsOptions == null) return [];
    return _cupsOptions!.map((option) {
      final currentValue = _selectedCupsOptions[option.name];
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: DropdownButtonFormField<String>(
          value: currentValue,
          decoration: InputDecoration(
            labelText: option.name,
            border: const OutlineInputBorder(),
          ),
          items: option.supportedValues.map((choice) {
            return DropdownMenuItem(
              value: choice.choice,
              child: Text(choice.text),
            );
          }).toList(),
          onChanged: (newValue) {
            if (newValue != null) {
              setState(() {
                _selectedCupsOptions[option.name] = newValue;
              });
            }
          },
        ),
      );
    }).toList();
  }

  Widget _buildJobsList() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Print Queue',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            if (_isLoadingJobs)
              const Center(child: CircularProgressIndicator())
            else if (_jobs.isEmpty)
              const Text('No active print jobs.')
            else
              SizedBox(
                height: 200,
                child: ListView.builder(
                  itemCount: _jobs.length,
                  itemBuilder: (context, index) {
                    final job = _jobs[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(job.title),
                        subtitle: Text(
                          'ID: ${job.id} - Status: ${job.statusDescription}',
                        ),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.pause, size: 16),
                              onPressed: () => _manageJob(job.id, 'pause'),
                            ),
                            IconButton(
                              icon: const Icon(Icons.play_arrow, size: 16),
                              onPressed: () => _manageJob(job.id, 'resume'),
                            ),
                            IconButton(
                              icon: const Icon(Icons.cancel, size: 16),
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
        ),
      ),
    );
  }

  Widget _buildActions() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: _selectedPrinter != null ? _printPdf : null,
            icon: const Icon(Icons.print),
            label: const Text('Print'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class PrintStatusDialog extends StatefulWidget {
  final String printerName;
  final Stream<PrintJob> jobStream;

  const PrintStatusDialog({
    super.key,
    required this.printerName,
    required this.jobStream,
  });

  @override
  State<PrintStatusDialog> createState() => _PrintStatusDialogState();
}

class _PrintStatusDialogState extends State<PrintStatusDialog> {
  StreamSubscription<PrintJob>? _subscription;
  PrintJob? _job;
  Object? _error;
  bool _isDone = false;
  bool _isCancelling = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration.zero, () {
      if (!mounted) return;
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
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _cancelJob() async {
    if (_job == null || !mounted) return;

    setState(() => _isCancelling = true);

    try {
      final success = await PrintingFfi.instance.cancelPrintJob(
        widget.printerName,
        _job!.id,
      );

      if (!mounted) return;

      if (success) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Print job cancelled successfully')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to cancel print job')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCancelling = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error cancelling job: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isJobTerminal =
        _job != null &&
        (_job!.status == PrintJobStatus.completed ||
            _job!.status == PrintJobStatus.canceled ||
            _job!.status == PrintJobStatus.aborted ||
            _job!.status == PrintJobStatus.error);

    final isImplicitlyComplete = _isDone && _job == null && _error == null;
    final canCancel = !_isCancelling && !isJobTerminal && !_isDone;

    Widget content;
    if (_error != null) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 48,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 16),
          Text('Print Error', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(_error.toString(), textAlign: TextAlign.center),
        ],
      );
    } else if (isImplicitlyComplete) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 48, color: Colors.green),
          const SizedBox(height: 16),
          Text(
            'Print Job Completed',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ],
      );
    } else if (_job == null) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Starting print job...',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      );
    } else {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Job #${_job!.id}: ${_job!.statusDescription}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Text('Print Status'),
      content: SizedBox(width: 300, height: 200, child: Center(child: content)),
      actions: [
        if (isJobTerminal || _error != null || isImplicitlyComplete)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          )
        else
          TextButton(
            onPressed: canCancel ? _cancelJob : null,
            child: _isCancelling
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Cancel Job'),
          ),
      ],
    );
  }
}

class _CapabilitiesDialog extends StatelessWidget {
  final String printerName;
  final WindowsPrinterCapabilitiesModel capabilities;

  const _CapabilitiesDialog({
    required this.printerName,
    required this.capabilities,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Printer Capabilities',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCapabilitySection(
                    context,
                    'Paper Sizes (${capabilities.paperSizes.length})',
                    capabilities.paperSizes
                        .map(
                          (paper) =>
                              '${paper.name} - ${paper.widthMillimeters.toStringAsFixed(1)} x ${paper.heightMillimeters.toStringAsFixed(1)} mm',
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 24),
                  _buildCapabilitySection(
                    context,
                    'Paper Sources (${capabilities.paperSources.length})',
                    capabilities.paperSources
                        .map((source) => source.name)
                        .toList(),
                  ),
                  const SizedBox(height: 24),
                  _buildCapabilitySection(
                    context,
                    'Media Types (${capabilities.mediaTypes.length})',
                    capabilities.mediaTypes.map((media) => media.name).toList(),
                  ),
                  const SizedBox(height: 24),
                  _buildCapabilitySection(
                    context,
                    'Supported Resolutions (${capabilities.resolutions.length})',
                    capabilities.resolutions
                        .map((res) => res.toString())
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Container(
            padding: const EdgeInsets.all(24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCapabilitySection(
    BuildContext context,
    String title,
    List<String> items,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 12),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.6),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    item,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
