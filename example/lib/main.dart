import 'dart:io';
import 'dart:async';
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
  StreamSubscription<List<PrintJob>>? _jobsSubscription;
  List<CupsOption>? _cupsOptions;
  Map<String, String> _selectedCupsOptions = {};

  bool _isLoadingPrinters = false;
  bool _isLoadingJobs = false;
  bool _isLoadingCupsOptions = false;
  final TextEditingController _rawDataController = TextEditingController(
    text: 'Hello, FFI!',
  );
  PdfPrintScaling _selectedScaling = PdfPrintScaling.fitPage;

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
      _jobsSubscription?.cancel();
      _jobs = [];
      _selectedPrinter = printer;
      _subscribeToJobs();
      _fetchCupsOptions();
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
      } else {
        _showSnackbar('Failed to print PDF.', isError: true);
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
      final path = result.files.single.path!;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _PrintStatusDialog(
          printerName: _selectedPrinter!.name,
          jobStream: printPdfAndStreamStatus(
            _selectedPrinter!.name,
            path,
            scaling: _selectedScaling,
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

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _PrintStatusDialog(
        printerName: _selectedPrinter!.name,
        jobStream: rawDataToPrinterAndStreamStatus(
          _selectedPrinter!.name,
          data,
          docName: 'My Tracked ZPL Label',
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

    _showSnackbar('Sending raw ZPL data...');
    final success = await rawDataToPrinter(
      _selectedPrinter!.name,
      data,
      docName: 'My ZPL Label',
    );
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

    final capabilities =
        await getWindowsPrinterCapabilities(_selectedPrinter!.name);

    if (!mounted) return;

    if (capabilities == null) {
      _showSnackbar('Could not retrieve capabilities for this printer.',
          isError: true);
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
              Text('Supported Paper Sizes',
                  style: Theme.of(context).textTheme.titleMedium),
              for (final paper in capabilities.paperSizes)
                ListTile(
                  title: Text(paper.name),
                  subtitle: Text(paper.toString()),
                ),
              const Divider(),
              Text('Supported Resolutions',
                  style: Theme.of(context).textTheme.titleMedium),
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
                    onPressed: () => _printPdf(scaling: _selectedScaling),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
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
                        onPressed: _showWindowsCapabilities),
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
    );
  }

  Future<void> _cancelJob() async {
    if (_job == null || !mounted) return;
    setState(() => _isCancelling = true);
    try {
      final success = await cancelPrintJob(widget.printerName, _job!.id);

      // After the await, the widget might have been disposed.
      if (!mounted) return;

      if (success) {
        // If successful, pop the dialog and show a confirmation snackbar.
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cancel command sent successfully.'),
            backgroundColor: Colors.blue,
          ),
        );
      } else {
        // If failed, stay on the dialog and show an error.
        setState(() => _isCancelling = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send cancel command.'),
            backgroundColor: Colors.orange,
          ),
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

    final canCancel = _job != null && !_isCancelling && !isJobTerminal;

    return AlertDialog(
      title: const Text('Tracking Print Job...'),
      content: SizedBox(
        width: 250,
        height: 100,
        child: Center(
          child: _error != null
              ? Text(
                  'Error: $_error',
                  style: const TextStyle(color: Colors.red),
                )
              : _job == null
              ? const CircularProgressIndicator()
              : Text(
                  'Job #${_job!.id}: ${_job!.statusDescription}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
        ),
      ),
      actions: <Widget>[
        if (isJobTerminal || _error != null)
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
