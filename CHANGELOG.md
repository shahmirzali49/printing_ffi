## 0.0.2

* **FEAT**: Added `PdfPrintScaling` option to the `printPdf` function on Windows to control scaling ('Fit to Page' vs 'Actual Size').
* **FIX**: Replaced unreliable `ShellExecute` PDF printing on Windows with a robust, self-contained solution using the `pdfium` library for rendering. This removes the dependency on external PDF applications.
* **FIX**: Correctly specified "raw" printing option for CUPS on macOS/Linux to ensure raw data is sent to the printer without modification.
* **FEAT**: Added extensive logging to the native C code, enabled in debug builds, to simplify troubleshooting.
* **FEAT**: Added `printPdf` function to print PDF files directly to a specified printer.

## 0.0.1

* **Initial Release**
* Added support for listing printers on macOS (via CUPS) and Windows (via winspool), including offline printers.
* Implemented raw data printing for sending formats like ZPL and ESC/POS directly to printers.
* Included print job management features: list, pause, resume, and cancel jobs.
* Utilizes FFI for direct native API communication, ensuring high performance.
