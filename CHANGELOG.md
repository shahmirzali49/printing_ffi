## 0.0.7

* **FEAT**: Improved error handling with `get_last_error` for detailed native messages and `register_log_callback` for real-time logging. 🕵️‍♂️
* **FEAT**: Enhanced PDF printing on Windows with `Fit to Paper` and `Custom` scaling options. 📄✨
* **FIX**: Corrected PDF rendering issues on Windows, including stretching on non-square DPIs and improving compatibility with a 32-bit BGRA bitmap format. 🐛
* **FIX**: Improved stability by addressing a memory leak and enhancing resource cleanup during print failures on Windows.
* **REFACTOR**: Removed redundant `DEVMODE` field resets to prevent potential driver conflicts on Windows. ♻️
* **EXAMPLE**: Added PDF file selection and custom scale validation to the example app. 🎨
* **DOCS**: Updated documentation for new features and error handling. 📝

## 0.0.6

* **FEAT**: Added support for opening the native Windows printer properties dialog via `openPrinterProperties`. 🎛️
* **FEAT**: Added support for setting Paper Size, Paper Source, and Orientation on Windows for both PDF and raw data printing. 📄⚙️
* **FEAT**: Added support for passing generic CUPS options to raw data print jobs on macOS and Linux. 🐧🍎
* **REFACTOR**: Refactored the Dart FFI layer to use generated bindings directly, removing manual lookups and improving maintainability. ✨
* **EXAMPLE**: Updated the example app with UI controls for new Windows printing options and a button to show printer properties. 🎨

## 0.0.5

* **FEAT**: Added support for `copies` and `pageRange` when printing PDFs on Windows and CUPS-based systems. 🔢
* **FEAT**: Refactored the `pageRange` parameter to use a type-safe `PageRange` class, improving API clarity and preventing invalid format errors. 🔒
* **DOCS**: Updated documentation for new printing parameters and the `PageRange` class. 📝
* **EXAMPLE**: Added UI controls for setting the number of copies and page range in the example app. 🎨

## 0.0.4

* **DOCS**: Updated `pubspec.yaml` with repository, homepage, issue tracker links,license and relevant topics for better discoverability on pub.dev.

## 0.0.3

* **FEAT**: Added full support for Linux via CUPS. 🚀
* **FEAT**: Added job status tracking streams for PDF and raw data printing. 📊
* **FEAT**: Added `getWindowsPrinterCapabilities` to fetch supported paper sizes and resolutions on Windows. 🖨️
* ✨ **FEAT**: Improved error handling and Windows printer capabilities:
    *   Enhanced isolate communication with robust error responses.
    *   Switched to Unicode (W-series) Windows APIs for full international character support in printer and document names.
    *   Improved memory management and error handling in `get_windows_printer_capabilities`.
    *   Added `NULL` checks for pointers returned by Windows API functions to prevent crashes.
    *   Improved logging for easier debugging.
* **DOCS**: Updated README with Linux setup instructions and new features. 📝

## 0.0.2

* **FIX**: Resolved a crash on Windows when printing by correctly quoting the printer name for the shell API.
* **FIX**: Updated the Windows build script to use the correct URL and latest version of the `pdfium` library, resolving download errors.
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
