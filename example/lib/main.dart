import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'pdf_viewer_dialog.dart';
import 'modern_print_dialog.dart';
import 'package:printing_ffi/printing_ffi.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // PrintingFfi.instance.initialize(
  //   logHandler: (message) {
  //     debugPrint('CUSTOM LOG HANDLER: $message');
  //   },
  // );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PDF Viewer & Printer MRE',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  String? _cachedPdfPath;
  bool _isDownloading = false;
  String _status = 'Ready to download PDF';

  // Sample PDF URL - you can replace this with any PDF URL
  static const String _pdfUrl =
      'https://ontheline.trincoll.edu/images/bookdown/sample-local-pdf.pdf';

  Future<void> _downloadPdf() async {
    setState(() {
      _isDownloading = true;
      _status = 'Downloading PDF...';
    });

    try {
      // Get cache directory
      final cacheDir = await getTemporaryDirectory();
      final fileName = 'sample_document.pdf';
      final filePath = path.join(cacheDir.path, fileName);

      // Download PDF
      final response = await http.get(Uri.parse(_pdfUrl));

      if (response.statusCode == 200) {
        // Save to cache
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);

        setState(() {
          _cachedPdfPath = filePath;
          _status = 'PDF downloaded and cached successfully!';
        });
      } else {
        setState(() {
          _status = 'Failed to download PDF: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _status = 'Error downloading PDF: $e';
      });
    } finally {
      setState(() {
        _isDownloading = false;
      });
    }
  }

  void _viewPdf() {
    if (_cachedPdfPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please download PDF first')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => PdfViewerDialog(
        pdfPath: _cachedPdfPath!,
        fileName: 'Sample Document.pdf',
      ),
    );
  }

  void _printPdf() {
    if (_cachedPdfPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please download PDF first')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => ModernPrintDialog(
        pdfPath: _cachedPdfPath!,
        fileName: 'Sample Document.pdf',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('PDF Viewer & Printer MRE'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PDF Cache Status',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(_status),
                    if (_cachedPdfPath != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Cached at: $_cachedPdfPath',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isDownloading ? null : _downloadPdf,
              icon: _isDownloading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download),
              label: Text(
                _isDownloading ? 'Downloading...' : 'Download Sample PDF',
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _cachedPdfPath != null ? _viewPdf : null,
                    icon: const Icon(Icons.visibility),
                    label: const Text('View PDF'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _cachedPdfPath != null ? _printPdf : null,
                    icon: const Icon(Icons.print),
                    label: const Text('Print PDF'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'How to use:',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '1. Click "Download Sample PDF" to cache a PDF file',
                    ),
                    const Text(
                      '2. Click "View PDF" to open the PDF viewer dialog',
                    ),
                    const Text('3. Click "Print PDF" to open the print dialog'),
                    const Text(
                      '4. In the PDF viewer, you can also click the print button',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
