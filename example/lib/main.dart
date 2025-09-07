import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing_ffi/printing_ffi.dart';

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
  List<CupsOption>? _cupsOptions;
  Map<String, String> _selectedCupsOptions = {};

  bool _isLoadingPrinters = false;
  bool _isLoadingJobs = false;
  bool _isLoadingCupsOptions = false;
  final TextEditingController _rawDataController = TextEditingController(
    text: 'Hello, FFI!',
  );
  PdfPrintScaling _selectedScaling = PdfPrintScaling.fitPage;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _refreshPrinters();
  }

  @override
  void dispose() {
    _rawDataController.dispose();
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
      _selectedPrinter = printer;
      _refreshJobs();
      _fetchCupsOptions();
    });
  }

  Future<void> _refreshJobs() async {
    if (_selectedPrinter == null) return;
    setState(() => _isLoadingJobs = true);
    try {
      final jobs = await listPrintJobs(_selectedPrinter!.name);
      setState(() => _jobs = jobs);
    } catch (e) {
      _showSnackbar('Failed to get jobs: $e', isError: true);
    } finally {
      setState(() => _isLoadingJobs = false);
    }
  }

  Future<void> _fetchCupsOptions() async {
    if (_selectedPrinter == null) return;
    setState(() {
      _isLoadingCupsOptions = true;
      _cupsOptions = null;
    });

    try {
      final options = await getSupportedCupsOptions(_selectedPrinter!.name);
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
      setState(() => _isLoadingCupsOptions = false);
    }
  }

  Future<void> _printPdf({
    Map<String, String>? cupsOptions,
    required PdfPrintScaling scaling,
  }) async {
    if (_selectedPrinter == null) {
      _showSnackbar('No printer selected!', isError: true);
      return;
    }
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      _showSnackbar('Printing PDF...');
      final success = await printPdf(
        _selectedPrinter!.name,
        path,
        docName: 'My Flutter PDF',
        cupsOptions: cupsOptions,
        scaling: scaling,
      );
      if (success) {
        _showSnackbar('PDF sent to printer successfully!');
        await Future.delayed(const Duration(seconds: 2), _refreshJobs);
      } else {
        _showSnackbar('Failed to print PDF.', isError: true);
      }
    }
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

    _showSnackbar('Sending raw ZPL data...');
    final success = await rawDataToPrinter(
      _selectedPrinter!.name,
      data,
      docName: 'My ZPL Label',
    );
    if (success) {
      _showSnackbar('Raw data sent successfully!');
      await Future.delayed(const Duration(seconds: 2), _refreshJobs);
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
      _showSnackbar(
        'Job $action ${success ? 'succeeded' : 'failed'}.',
        isError: !success,
      );
      await Future.delayed(const Duration(seconds: 2), _refreshJobs);
    } catch (e) {
      _showSnackbar('Error managing job: $e', isError: true);
    }
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
              icon: const Icon(Icons.refresh),
              onPressed: _refreshPrinters,
            ),
          ],
          bottom: _selectedPrinter != null
              ? TabBar(
                  onTap: (index) => setState(() => _tabIndex = index),
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
            const SizedBox(height: 16),
            Center(
              child: Column(children: [
                if (Platform.isWindows) ...[
                  SegmentedButton<PdfPrintScaling>(
                    segments: const [
                      ButtonSegment(value: PdfPrintScaling.fitPage, label: Text('Fit to Page')),
                      ButtonSegment(value: PdfPrintScaling.actualSize, label: Text('Actual Size')),
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
                  onPressed: () => _printPdf(scaling: _selectedScaling),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
              ]),
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
          ],
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
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _refreshJobs,
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
              onPressed: () => _printPdf(cupsOptions: _selectedCupsOptions, scaling: _selectedScaling),
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
