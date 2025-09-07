#include "printing_ffi.h"
#include <string.h>

#ifdef _WIN32
#include <winspool.h>
#include <stdio.h>
#include <shellapi.h>
#include <wingdi.h>
#define strdup _strdup
#else
#include <cups/cups.h>
#include <cups/ppd.h>
#include <stdio.h>
#include <stdlib.h>
#include <limits.h>
#endif

#ifdef _WIN32
// Include the main Pdfium header. Ensure this is in your src/ directory.
#include "fpdfview.h"
#endif

// Logging macro - enabled when DEBUG_LOGGING is defined (e.g., in debug builds)
#ifdef DEBUG_LOGGING
#define LOG(format, ...) fprintf(stderr, "[printing_ffi] " format "\n", ##__VA_ARGS__)
#else
#define LOG(...)
#endif

FFI_PLUGIN_EXPORT int sum(int a, int b) {
    return a + b;
}

FFI_PLUGIN_EXPORT int sum_long_running(int a, int b) {
#ifdef _WIN32
    Sleep(5000);
#else
    usleep(5000 * 1000);
#endif
    return a + b;
}

FFI_PLUGIN_EXPORT PrinterList* get_printers(void) {
    LOG("get_printers called");
    PrinterList* list = (PrinterList*)malloc(sizeof(PrinterList));
    if (!list) return NULL;
    list->count = 0;
    list->printers = NULL;

#ifdef _WIN32
    DWORD needed, returned;
    EnumPrintersA(PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS, NULL, 2, NULL, 0, &needed, &returned);
    LOG("EnumPrintersA needed %lu bytes for printer list", needed);
    if (needed == 0) {
        return list; // Return empty list
    }
    BYTE* buffer = (BYTE*)malloc(needed);
    if (!buffer) {
        free(list);
        return NULL;
    }

    if (EnumPrintersA(PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS, NULL, 2, buffer, needed, &needed, &returned)) {
        LOG("Found %lu printers on Windows", returned);
        list->count = returned;
        list->printers = (PrinterInfo*)malloc(returned * sizeof(PrinterInfo));
        if (!list->printers) {
            free(buffer);
            free(list);
            return NULL;
        }
        PRINTER_INFO_2A* printers = (PRINTER_INFO_2A*)buffer;
        for (DWORD i = 0; i < returned; i++) {
            list->printers[i].name = strdup(printers[i].pPrinterName ? printers[i].pPrinterName : "");
            list->printers[i].state = printers[i].Status;
            list->printers[i].url = strdup(printers[i].pPrinterName ? printers[i].pPrinterName : "");
            list->printers[i].model = strdup(printers[i].pDriverName ? printers[i].pDriverName : "");
            list->printers[i].location = strdup(printers[i].pLocation ? printers[i].pLocation : "");
            list->printers[i].comment = strdup(printers[i].pComment ? printers[i].pComment : "");
            list->printers[i].is_default = (printers[i].Attributes & PRINTER_ATTRIBUTE_DEFAULT) != 0;
            list->printers[i].is_available = (printers[i].Status & PRINTER_STATUS_OFFLINE) == 0;
        }
    } else {
        LOG("EnumPrintersA failed with error %lu", GetLastError());
    }
    free(buffer);
    return list;
#else // macOS
    cups_dest_t* dests = NULL;
    LOG("Calling cupsGetDests to find printers");
    int num_dests = cupsGetDests(&dests);
    if (num_dests <= 0) {
        cupsFreeDests(num_dests, dests);
        return list; // Return empty list
    }

    LOG("Found %d printers on macOS/Linux", num_dests);
    list->count = num_dests;
    list->printers = (PrinterInfo*)malloc(num_dests * sizeof(PrinterInfo));
    if (!list->printers) {
        cupsFreeDests(num_dests, dests);
        free(list);
        return NULL;
    }

    for (int i = 0; i < num_dests; i++) {
        list->printers[i].name = strdup(dests[i].name);
        list->printers[i].is_default = dests[i].is_default;

        const char* state_str = cupsGetOption("printer-state", dests[i].num_options, dests[i].options);
        list->printers[i].state = state_str ? atoi(state_str) : 3; // Default to IPP_PRINTER_IDLE (3)
        list->printers[i].is_available = list->printers[i].state != 5; // 5 is IPP_PRINTER_STOPPED

        const char* uri_str = cupsGetOption("device-uri", dests[i].num_options, dests[i].options);
        list->printers[i].url = strdup(uri_str ? uri_str : "");

        const char* model_str = cupsGetOption("printer-make-and-model", dests[i].num_options, dests[i].options);
        list->printers[i].model = strdup(model_str ? model_str : "");

        const char* location_str = cupsGetOption("printer-location", dests[i].num_options, dests[i].options);
        list->printers[i].location = strdup(location_str ? location_str : "");

        const char* comment_str = cupsGetOption("printer-info", dests[i].num_options, dests[i].options);
        list->printers[i].comment = strdup(comment_str ? comment_str : "");
    }
    cupsFreeDests(num_dests, dests);
    return list;
#endif
}

FFI_PLUGIN_EXPORT void free_printer_list(PrinterList* printer_list) {
    if (!printer_list) return;
    if (printer_list->printers) {
        for (int i = 0; i < printer_list->count; i++) {
            free(printer_list->printers[i].name);
            free(printer_list->printers[i].url);
            free(printer_list->printers[i].model);
            free(printer_list->printers[i].location);
            free(printer_list->printers[i].comment);
        }
        free(printer_list->printers);
    }
    free(printer_list);
}

FFI_PLUGIN_EXPORT PrinterInfo* get_default_printer(void) {
    LOG("get_default_printer called");
#ifdef _WIN32
    DWORD len = 0;
    GetDefaultPrinterA(NULL, &len);
    if (len == 0) {
        return NULL; // No default printer or an error occurred
    }

    char* default_printer_name = (char*)malloc(len);
    if (!default_printer_name) return NULL;

    if (!GetDefaultPrinterA(default_printer_name, &len)) {
        LOG("GetDefaultPrinterA failed with error %lu", GetLastError());
        free(default_printer_name);
        return NULL;
    }

    HANDLE hPrinter;
    if (!OpenPrinterA(default_printer_name, &hPrinter, NULL)) {
        LOG("OpenPrinterA for default printer failed with error %lu", GetLastError());
        free(default_printer_name);
        return NULL;
    }
    free(default_printer_name);

    DWORD needed = 0;
    GetPrinterA(hPrinter, 2, NULL, 0, &needed);
    if (needed == 0) {
        LOG("GetPrinterA (to get size) failed with error %lu", GetLastError());
        ClosePrinter(hPrinter);
        return NULL;
    }

    PRINTER_INFO_2A* pinfo2 = (PRINTER_INFO_2A*)malloc(needed);
    if (!pinfo2) {
        ClosePrinter(hPrinter);
        return NULL;
    }

    if (!GetPrinterA(hPrinter, 2, (LPBYTE)pinfo2, needed, &needed)) {
        LOG("GetPrinterA (to get data) failed with error %lu", GetLastError());
        free(pinfo2);
        ClosePrinter(hPrinter);
        return NULL;
    }
    ClosePrinter(hPrinter);

    PrinterInfo* printer_info = (PrinterInfo*)malloc(sizeof(PrinterInfo));
    if (!printer_info) {
        free(pinfo2);
        return NULL;
    }

    printer_info->name = strdup(pinfo2->pPrinterName ? pinfo2->pPrinterName : "");
    printer_info->state = pinfo2->Status;
    printer_info->url = strdup(pinfo2->pPrinterName ? pinfo2->pPrinterName : "");
    printer_info->model = strdup(pinfo2->pDriverName ? pinfo2->pDriverName : "");
    printer_info->location = strdup(pinfo2->pLocation ? pinfo2->pLocation : "");
    printer_info->comment = strdup(pinfo2->pComment ? pinfo2->pComment : "");
    printer_info->is_default = (pinfo2->Attributes & PRINTER_ATTRIBUTE_DEFAULT) != 0;
    printer_info->is_available = (pinfo2->Status & PRINTER_STATUS_OFFLINE) == 0;

    free(pinfo2);
    return printer_info;
#else // macOS
    const char* default_printer_name = cupsGetDefault();
    if (!default_printer_name) {
        LOG("cupsGetDefault returned null, no default printer found.");
        return NULL;
    }
    LOG("macOS/Linux default printer name: %s", default_printer_name);

    cups_dest_t* dests = NULL;
    int num_dests = cupsGetDests(&dests);
    cups_dest_t* default_dest = cupsGetDest(default_printer_name, NULL, num_dests, dests);

    if (!default_dest) {
        cupsFreeDests(num_dests, dests);
        return NULL;
    }

    PrinterInfo* printer_info = (PrinterInfo*)malloc(sizeof(PrinterInfo));
    if (!printer_info) {
        cupsFreeDests(num_dests, dests);
        return NULL;
    }

    printer_info->name = strdup(default_dest->name);
    printer_info->is_default = default_dest->is_default;
    const char* state_str = cupsGetOption("printer-state", default_dest->num_options, default_dest->options);
    printer_info->state = state_str ? atoi(state_str) : 3;
    printer_info->is_available = printer_info->state != 5;
    const char* uri_str = cupsGetOption("device-uri", default_dest->num_options, default_dest->options);
    printer_info->url = strdup(uri_str ? uri_str : "");
    const char* model_str = cupsGetOption("printer-make-and-model", default_dest->num_options, default_dest->options);
    printer_info->model = strdup(model_str ? model_str : "");
    const char* location_str = cupsGetOption("printer-location", default_dest->num_options, default_dest->options);
    printer_info->location = strdup(location_str ? location_str : "");
    const char* comment_str = cupsGetOption("printer-info", default_dest->num_options, default_dest->options);
    printer_info->comment = strdup(comment_str ? comment_str : "");

    cupsFreeDests(num_dests, dests);
    return printer_info;
#endif
}

FFI_PLUGIN_EXPORT void free_printer_info(PrinterInfo* printer_info) {
    if (!printer_info) return;
    free(printer_info->name);
    free(printer_info->url);
    free(printer_info->model);
    free(printer_info->location);
    free(printer_info->comment);
    free(printer_info);
}

FFI_PLUGIN_EXPORT bool raw_data_to_printer(const char* printer_name, const uint8_t* data, int length, const char* doc_name) {
    LOG("raw_data_to_printer called for printer: '%s', doc: '%s', length: %d", printer_name, doc_name, length);
#ifdef _WIN32
    HANDLE hPrinter;
    DOC_INFO_1A docInfo;
    DWORD written;

    if (!OpenPrinterA((LPSTR)printer_name, &hPrinter, NULL)) {
        LOG("OpenPrinterA failed with error %lu", GetLastError());
        return false;
    }

    docInfo.pDocName = (LPSTR)doc_name;
    docInfo.pOutputFile = NULL;
    docInfo.pDatatype = "RAW";

    if (StartDocPrinterA(hPrinter, 1, (LPBYTE)&docInfo) == 0) {
        ClosePrinter(hPrinter);
        LOG("StartDocPrinterA failed with error %lu", GetLastError());
        return false;
    }

    if (!StartPagePrinter(hPrinter)) {
        EndDocPrinter(hPrinter);
        LOG("StartPagePrinter failed with error %lu", GetLastError());
        ClosePrinter(hPrinter);
        return false;
    }

    bool result = WritePrinter(hPrinter, (LPVOID)data, length, &written);
    EndPagePrinter(hPrinter);
    EndDocPrinter(hPrinter);
    ClosePrinter(hPrinter);
    bool success = result && written == length;
    if (!success) {
        LOG("WritePrinter failed. Result: %d, Bytes written: %lu, Expected: %d", result, written, length);
    }
    return success;
#else
    // Use getenv("TMPDIR") to get the correct temporary directory,
    // especially important for sandboxed macOS apps where /tmp is not writable.
    const char* tmpdir = getenv("TMPDIR");
    if (!tmpdir) {
        tmpdir = "/tmp"; // Fallback for Linux or non-sandboxed environments
    }

    char temp_file[PATH_MAX];
    snprintf(temp_file, sizeof(temp_file), "%s/printing_ffi_XXXXXX", tmpdir);
    LOG("Creating temporary file at: %s", temp_file);

    int fd = mkstemp(temp_file);
    if (fd == -1) {
        LOG("mkstemp failed to create temporary file");
        return false;
    }

    FILE* fp = fdopen(fd, "wb");
    if (!fp) {
        close(fd);
        unlink(temp_file);
        return false;
    }

    size_t written = fwrite(data, 1, length, fp);
    fclose(fp);

    if (written != length) {
        unlink(temp_file);
        return false;
    }

    // Add the "raw" option to tell CUPS not to filter the data.
    cups_option_t* options = NULL;
    int num_options = 0;
    num_options = cupsAddOption("raw", "true", num_options, &options);

    int job_id = cupsPrintFile(printer_name, temp_file, doc_name, num_options, options);
    if (job_id <= 0) {
        LOG("cupsPrintFile failed, error: %s", cupsLastErrorString());
    }
    cupsFreeOptions(num_options, options);
    unlink(temp_file);
    LOG("raw_data_to_printer finished with job_id: %d", job_id);
    return job_id > 0;
#endif
}

FFI_PLUGIN_EXPORT bool print_pdf(const char* printer_name, const char* pdf_file_path, const char* doc_name, int scaling_mode, int num_options, const char** option_keys, const char** option_values) {
    LOG("print_pdf called for printer: '%s', path: '%s', doc: '%s'", printer_name, pdf_file_path, doc_name);
#ifdef _WIN32
    // One-time initialization of the Pdfium library.
    static bool s_pdfium_initialized = false;
    if (!s_pdfium_initialized) {
        FPDF_LIBRARY_CONFIG config;
        memset(&config, 0, sizeof(config));
        config.version = 2;
        FPDF_InitLibraryWithConfig(&config);
        s_pdfium_initialized = true;
        LOG("Pdfium library initialized for the first time.");
    }

    // Ignore CUPS options on Windows.
    (void)num_options;
    (void)option_keys;
    (void)option_values;

    FPDF_DOCUMENT doc = FPDF_LoadDocument(pdf_file_path, NULL);
    if (!doc) {
        LOG("FPDF_LoadDocument failed for path: %s. Error: %ld", pdf_file_path, FPDF_GetLastError());
        return false;
    }

    HDC hdc = CreateDCA("WINSPOOL", printer_name, NULL, NULL);
    if (!hdc) {
        LOG("CreateDCA failed for printer '%s' with error %lu", printer_name, GetLastError());
        FPDF_CloseDocument(doc);
        return false;
    }

    DOCINFOA di = { sizeof(DOCINFOA), doc_name, NULL, NULL, 0 };
    if (StartDocA(hdc, &di) <= 0) {
        LOG("StartDocA failed with error %lu", GetLastError());
        DeleteDC(hdc);
        FPDF_CloseDocument(doc);
        return false;
    }

    int page_count = FPDF_GetPageCount(doc);
    bool success = true;
    for (int i = 0; i < page_count; ++i) {
        if (StartPage(hdc) <= 0) {
            LOG("StartPage failed for page %d with error %lu", i, GetLastError());
            success = false;
            break;
        }

        FPDF_PAGE page = FPDF_LoadPage(doc, i);
        if (!page) {
            LOG("FPDF_LoadPage failed for page %d", i);
            EndPage(hdc);
            success = false;
            break;
        }

        // Get printer DPI for scaling
        int dpi_x = GetDeviceCaps(hdc, LOGPIXELSX);
        int dpi_y = GetDeviceCaps(hdc, LOGPIXELSY);

        // Render page to a bitmap at printer's resolution
        int width = (int)(FPDF_GetPageWidthF(page) / 72.0 * dpi_x);
        int height = (int)(FPDF_GetPageHeightF(page) / 72.0 * dpi_y);

        BITMAPINFO bmi;
        memset(&bmi, 0, sizeof(bmi));
        bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        bmi.bmiHeader.biWidth = width;
        bmi.bmiHeader.biHeight = height; // Positive for bottom-up DIB
        bmi.bmiHeader.biPlanes = 1;
        bmi.bmiHeader.biBitCount = 32; // BGRA format
        bmi.bmiHeader.biCompression = BI_RGB;

        void* pBitmapData = NULL;
        HBITMAP hBitmap = CreateDIBSection(NULL, &bmi, DIB_RGB_COLORS, &pBitmapData, NULL, 0);
        if (!hBitmap || !pBitmapData) {
            LOG("CreateDIBSection failed for page %d", i);
            FPDF_ClosePage(page);
            EndPage(hdc);
            success = false;
            break;
        }

        // Fill with white background (Pdfium renders with transparency)
        memset(pBitmapData, 0xFF, width * height * 4);

        // Render the page
        FPDF_RenderPageBitmap(hBitmap, page, 0, 0, width, height, 0, FPDF_ANNOT);

        // Get printable area of the printer
        int printable_width = GetDeviceCaps(hdc, HORZRES);
        int printable_height = GetDeviceCaps(hdc, VERTRES);

        // Calculate destination rectangle based on scaling mode
        int dest_x = 0;
        int dest_y = 0;
        int dest_width = width;
        int dest_height = height;

        if (scaling_mode == 0) { // 0 = Fit Page
            float page_aspect = (float)width / (float)height;
            float printable_aspect = (float)printable_width / (float)printable_height;

            if (page_aspect > printable_aspect) {
                dest_width = printable_width;
                dest_height = (int)(printable_width / page_aspect);
            } else {
                dest_height = printable_height;
                dest_width = (int)(printable_height * page_aspect);
            }
            dest_x = (printable_width - dest_width) / 2;
            dest_y = (printable_height - dest_height) / 2;
        } else { // 1 = Actual Size
            dest_x = (printable_width - dest_width) / 2;
            dest_y = (printable_height - dest_height) / 2;
        }

        int result = StretchDIBits(hdc, dest_x, dest_y, dest_width, dest_height, 0, 0, width, height, pBitmapData, &bmi, DIB_RGB_COLORS, SRCCOPY);
        if (result == GDI_ERROR) {
            LOG("StretchDIBits failed for page %d with error %lu", i, GetLastError());
            success = false;
        }

        DeleteObject(hBitmap);
        FPDF_ClosePage(page);

        if (EndPage(hdc) <= 0) {
            LOG("EndPage failed for page %d with error %lu", i, GetLastError());
            success = false;
        }

        if (!success) break;
    }

    if (success) {
        EndDoc(hdc);
    } else {
        AbortDoc(hdc);
    }

    DeleteDC(hdc);
    FPDF_CloseDocument(doc);

    LOG("print_pdf (Pdfium/GDI) finished with result: %d", success);
    return success;
#else // macOS / Linux
    cups_option_t* options = NULL;
    int num_cups_options = 0;

    for (int i = 0; i < num_options; i++) {
        LOG("Adding CUPS option: %s=%s", option_keys[i], option_values[i]);
        num_cups_options = cupsAddOption(option_keys[i], option_values[i], num_cups_options, &options);
    }

    int job_id = cupsPrintFile(printer_name, pdf_file_path, doc_name, num_cups_options, options);
    if (job_id <= 0) {
        LOG("cupsPrintFile failed, error: %s", cupsLastErrorString());
    }
    cupsFreeOptions(num_cups_options, options);
    LOG("print_pdf finished with job_id: %d", job_id);
    return job_id > 0;
#endif
}

FFI_PLUGIN_EXPORT JobList* get_print_jobs(const char* printer_name) {
    JobList* list = (JobList*)malloc(sizeof(JobList));
    if (!list) return NULL;
    list->count = 0;
    list->jobs = NULL;

    LOG("get_print_jobs called for printer: '%s'", printer_name);
#ifdef _WIN32
    HANDLE hPrinter;
    DWORD needed, returned;

    if (!OpenPrinterA((LPSTR)printer_name, &hPrinter, NULL)) {
        free(list);
        LOG("OpenPrinterA failed with error %lu", GetLastError());
        return NULL;
    }

    EnumJobsA(hPrinter, 0, 0xFFFFFFFF, 2, NULL, 0, &needed, &returned);
    if (needed == 0) {
        ClosePrinter(hPrinter);
        return list;
    }
    BYTE* buffer = (BYTE*)malloc(needed);
    if (!buffer) {
        ClosePrinter(hPrinter);
        free(list);
        return NULL;
    }

    if (EnumJobsA(hPrinter, 0, 0xFFFFFFFF, 2, buffer, needed, &needed, &returned)) {
        LOG("Found %lu jobs on Windows", returned);
        list->count = returned;
        list->jobs = (JobInfo*)malloc(returned * sizeof(JobInfo));
        if (!list->jobs) {
            free(buffer);
            ClosePrinter(hPrinter);
            free(list);
            return NULL;
        }
        JOB_INFO_2A* jobs = (JOB_INFO_2A*)buffer;
        for (DWORD i = 0; i < returned; i++) {
            list->jobs[i].id = jobs[i].JobId;
            list->jobs[i].title = strdup(jobs[i].pDocument ? jobs[i].pDocument : "Unknown");
            list->jobs[i].status = jobs[i].Status;
        }
    } else {
        LOG("EnumJobsA failed with error %lu", GetLastError());
    }
    free(buffer);
    ClosePrinter(hPrinter);
    return list;
#else // macOS
    cups_job_t* jobs;
    LOG("Calling cupsGetJobs for active jobs");
    int num_jobs = cupsGetJobs(&jobs, printer_name, 1, CUPS_WHICHJOBS_ACTIVE);
    if (num_jobs <= 0) {
        cupsFreeJobs(num_jobs, jobs);
        return list;
    }

    LOG("Found %d active jobs on macOS/Linux", num_jobs);
    list->count = num_jobs;
    list->jobs = (JobInfo*)malloc(num_jobs * sizeof(JobInfo));
    if (!list->jobs) {
        cupsFreeJobs(num_jobs, jobs);
        free(list);
        return NULL;
    }

    for (int i = 0; i < num_jobs; i++) {
        list->jobs[i].id = jobs[i].id;
        list->jobs[i].title = strdup(jobs[i].title ? jobs[i].title : "Unknown");
        list->jobs[i].status = jobs[i].state;
    }
    cupsFreeJobs(num_jobs, jobs);
    return list;
#endif
}

FFI_PLUGIN_EXPORT void free_job_list(JobList* job_list) {
    if (!job_list) return;
    if (job_list->jobs) {
        for (int i = 0; i < job_list->count; i++) {
            free(job_list->jobs[i].title);
        }
        free(job_list->jobs);
    }
    free(job_list);
}

FFI_PLUGIN_EXPORT bool pause_print_job(const char* printer_name, uint32_t job_id) {
    LOG("pause_print_job called for printer: '%s', job_id: %u", printer_name, job_id);
#ifdef _WIN32
    HANDLE hPrinter;
    if (!OpenPrinterA((LPSTR)printer_name, &hPrinter, NULL)) return false;
    bool result = SetJobA(hPrinter, job_id, 0, NULL, JOB_CONTROL_PAUSE);
    if (!result) LOG("SetJobA(PAUSE) failed with error %lu", GetLastError());
    ClosePrinter(hPrinter);
    return result;
#else
    bool result = cupsCancelJob2(CUPS_HTTP_DEFAULT, printer_name, job_id, IPP_HOLD_JOB) == 1;
    if (!result) LOG("cupsCancelJob2(IPP_HOLD_JOB) failed, error: %s", cupsLastErrorString());
    return result;
#endif
}

FFI_PLUGIN_EXPORT bool resume_print_job(const char* printer_name, uint32_t job_id) {
    LOG("resume_print_job called for printer: '%s', job_id: %u", printer_name, job_id);
#ifdef _WIN32
    HANDLE hPrinter;
    if (!OpenPrinterA((LPSTR)printer_name, &hPrinter, NULL)) return false;
    bool result = SetJobA(hPrinter, job_id, 0, NULL, JOB_CONTROL_RESUME);
    if (!result) LOG("SetJobA(RESUME) failed with error %lu", GetLastError());
    ClosePrinter(hPrinter);
    return result;
#else
    bool result = cupsCancelJob2(CUPS_HTTP_DEFAULT, printer_name, job_id, IPP_RELEASE_JOB) == 1;
    if (!result) LOG("cupsCancelJob2(IPP_RELEASE_JOB) failed, error: %s", cupsLastErrorString());
    return result;
#endif
}

FFI_PLUGIN_EXPORT bool cancel_print_job(const char* printer_name, uint32_t job_id) {
    LOG("cancel_print_job called for printer: '%s', job_id: %u", printer_name, job_id);
#ifdef _WIN32
    HANDLE hPrinter;
    if (!OpenPrinterA((LPSTR)printer_name, &hPrinter, NULL)) return false;
    bool result = SetJobA(hPrinter, job_id, 0, NULL, JOB_CONTROL_CANCEL);
    if (!result) LOG("SetJobA(CANCEL) failed with error %lu", GetLastError());
    ClosePrinter(hPrinter);
    return result;
#else
    bool result = cupsCancelJob(printer_name, job_id) == 1;
    if (!result) LOG("cupsCancelJob failed, error: %s", cupsLastErrorString());
    return result;
#endif
}

FFI_PLUGIN_EXPORT CupsOptionList* get_supported_cups_options(const char* printer_name) {
    LOG("get_supported_cups_options called for printer: '%s'", printer_name);
    CupsOptionList* list = (CupsOptionList*)malloc(sizeof(CupsOptionList));
    if (!list) return NULL;
    list->count = 0;
    list->options = NULL;

#ifdef _WIN32
    // Not supported on Windows
    (void)printer_name;
    return list;
#else // macOS / Linux
    const char* ppd_filename = cupsGetPPD(printer_name);
    if (!ppd_filename) {
        LOG("cupsGetPPD failed for '%s', error: %s", printer_name, cupsLastErrorString());
        return list;
    }
    LOG("Found PPD file: %s", ppd_filename);

    ppd_file_t* ppd = ppdOpenFile(ppd_filename);
    if (!ppd) {
        LOG("ppdOpenFile failed for '%s'", ppd_filename);
        return list;
    }

    ppdMarkDefaults(ppd);

    int num_ui_options = 0;
    for (int i = 0; i < ppd->num_groups; i++) {
        num_ui_options += ppd->groups[i].num_options;
    }

    if (num_ui_options == 0) {
        ppdClose(ppd);
        LOG("No UI options found in PPD");
        return list;
    }

    list->count = num_ui_options;
    LOG("Found %d UI options in PPD", num_ui_options);
    list->options = (CupsOption*)malloc(num_ui_options * sizeof(CupsOption));
    if (!list->options) {
        ppdClose(ppd);
        free(list);
        return NULL;
    }

    int current_option_index = 0;
    ppd_option_t* option;
    for (int i = 0; i < ppd->num_groups; i++) {
        ppd_group_t* group = ppd->groups + i;
        for (int j = 0; j < group->num_options; j++) {
            option = group->options + j;

            list->options[current_option_index].name = strdup(option->keyword);
            list->options[current_option_index].default_value = strdup(option->defchoice);

            list->options[current_option_index].supported_values.count = option->num_choices;
            list->options[current_option_index].supported_values.choices = (CupsOptionChoice*)malloc(option->num_choices * sizeof(CupsOptionChoice));
            for (int k = 0; k < option->num_choices; k++) {
                list->options[current_option_index].supported_values.choices[k].choice = strdup(option->choices[k].choice);
                list->options[current_option_index].supported_values.choices[k].text = strdup(option->choices[k].text);
            }
            current_option_index++;
        }
    }

    ppdClose(ppd);
    LOG("get_supported_cups_options finished");
    return list;
#endif
}

FFI_PLUGIN_EXPORT void free_cups_option_list(CupsOptionList* option_list) {
    if (!option_list) return;
    if (option_list->options) {
        for (int i = 0; i < option_list->count; i++) {
            free(option_list->options[i].name);
            free(option_list->options[i].default_value);
            if (option_list->options[i].supported_values.choices) {
                for (int j = 0; j < option_list->options[i].supported_values.count; j++) {
                    free(option_list->options[i].supported_values.choices[j].choice);
                    free(option_list->options[i].supported_values.choices[j].text);
                }
                free(option_list->options[i].supported_values.choices);
            }
        }
        free(option_list->options);
    }
    free(option_list);
}