import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'modern_print_dialog.dart';

class PdfViewerDialog extends StatefulWidget {
  final String pdfPath;
  final String fileName;

  const PdfViewerDialog({
    super.key,
    required this.pdfPath,
    required this.fileName,
  });

  @override
  State<PdfViewerDialog> createState() => _PdfViewerDialogState();
}

class _PdfViewerDialogState extends State<PdfViewerDialog> {
  final _controller = PdfViewerController();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 800,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          children: [
            // Header with title and action buttons
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceVariant,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.picture_as_pdf, color: Colors.red, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.fileName,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton(
                    icon: const Icon(Icons.print),
                    tooltip: 'Print PDF',
                    onPressed: () {
                      // Navigator.of(context).pop(); // Close viewer first
                      showDialog(
                        context: context,
                        builder: (context) => ModernPrintDialog(
                          pdfPath: widget.pdfPath,
                          fileName: widget.fileName,
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // PDF Viewer
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                  child: PdfViewer(
                    PdfDocumentRefFile(widget.pdfPath),
                    controller: _controller,
                    params: PdfViewerParams(
                      margin: 16,
                      pageAnchor: PdfPageAnchor.top,
                      pageAnchorEnd: PdfPageAnchor.bottom,
                      maxScale: 5.0,
                      scaleEnabled: true,
                      scrollHorizontallyByMouseWheel: false,
                      loadingBannerBuilder:
                          (context, bytesDownloaded, totalBytes) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(
                                    value: totalBytes != null
                                        ? bytesDownloaded / totalBytes
                                        : null,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Loading PDF...',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyLarge,
                                  ),
                                ],
                              ),
                            );
                          },
                      errorBannerBuilder: (context,  error, stackTrace, documentRef) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 48,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Error loading PDF',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                error.toString(),
                                style: Theme.of(context).textTheme.bodyMedium,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        );
                      },
                      viewerOverlayBuilder: (context, size, _) => [
                        // Page number indicator
                        PdfViewerScrollThumb(
                          controller: _controller,
                          orientation: ScrollbarOrientation.right,
                          thumbSize: const Size(40, 25),
                          thumbBuilder:
                              (context, thumbSize, pageNumber, controller) =>
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.7),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Center(
                                      child: Text(
                                        pageNumber.toString(),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
