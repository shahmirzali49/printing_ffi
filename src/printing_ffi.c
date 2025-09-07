#include "printing_ffi.h"
#include <string.h>

#ifdef _WIN32
#include <winspool.h>
#include <shellapi.h>
#define strdup _strdup
#else
#include <cups/cups.h>
#include <cups/ppd.h>
#include <stdio.h>
#include <stdlib.h>
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
    PrinterList* list = (PrinterList*)malloc(sizeof(PrinterList));
    if (!list) return NULL;
    list->count = 0;
    list->printers = NULL;

#ifdef _WIN32
    DWORD needed, returned;
    EnumPrintersA(PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS, NULL, 2, NULL, 0, &needed, &returned);
    if (needed == 0) {
        return list; // Return empty list
    }
    BYTE* buffer = (BYTE*)malloc(needed);
    if (!buffer) {
        free(list);
        return NULL;
    }

    if (EnumPrintersA(PRINTER_ENUM_LOCAL | PRINTER_ENUM_CONNECTIONS, NULL, 2, buffer, needed, &needed, &returned)) {
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
    }
    free(buffer);
    return list;
#else // macOS
    cups_dest_t* dests = NULL;
    int num_dests = cupsGetDests(&dests);
    if (num_dests <= 0) {
        cupsFreeDests(num_dests, dests);
        return list; // Return empty list
    }

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
#ifdef _WIN32
    DWORD len = 0;
    GetDefaultPrinterA(NULL, &len);
    if (len == 0) {
        return NULL; // No default printer or an error occurred
    }

    char* default_printer_name = (char*)malloc(len);
    if (!default_printer_name) return NULL;

    if (!GetDefaultPrinterA(default_printer_name, &len)) {
        free(default_printer_name);
        return NULL;
    }

    HANDLE hPrinter;
    if (!OpenPrinterA(default_printer_name, &hPrinter, NULL)) {
        free(default_printer_name);
        return NULL;
    }
    free(default_printer_name);

    DWORD needed = 0;
    GetPrinterA(hPrinter, 2, NULL, 0, &needed);
    if (needed == 0) {
        ClosePrinter(hPrinter);
        return NULL;
    }

    PRINTER_INFO_2A* pinfo2 = (PRINTER_INFO_2A*)malloc(needed);
    if (!pinfo2) {
        ClosePrinter(hPrinter);
        return NULL;
    }

    if (!GetPrinterA(hPrinter, 2, (LPBYTE)pinfo2, needed, &needed)) {
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
    if (!default_printer_name) return NULL;

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
#ifdef _WIN32
    HANDLE hPrinter;
    DOC_INFO_1A docInfo;
    DWORD written;

    if (!OpenPrinterA((LPSTR)printer_name, &hPrinter, NULL)) return false;

    docInfo.pDocName = (LPSTR)doc_name;
    docInfo.pOutputFile = NULL;
    docInfo.pDatatype = "RAW";

    if (StartDocPrinterA(hPrinter, 1, (LPBYTE)&docInfo) == 0) {
        ClosePrinter(hPrinter);
        return false;
    }

    if (!StartPagePrinter(hPrinter)) {
        EndDocPrinter(hPrinter);
        ClosePrinter(hPrinter);
        return false;
    }

    bool result = WritePrinter(hPrinter, (LPVOID)data, length, &written);
    EndPagePrinter(hPrinter);
    EndDocPrinter(hPrinter);
    ClosePrinter(hPrinter);
    return result && written == length;
#else
    char temp_file[] = "/tmp/printing_ffi_XXXXXX";
    int fd = mkstemp(temp_file);
    if (fd == -1) return false;

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
    cupsFreeOptions(num_options, options);
    unlink(temp_file);
    return job_id > 0;
#endif
}

FFI_PLUGIN_EXPORT bool print_pdf(const char* printer_name, const char* pdf_file_path, const char* doc_name, int num_options, const char** option_keys, const char** option_values) {
#ifdef _WIN32
    // On Windows, we use ShellExecute with the "printto" verb.
    // This requires a PDF reader to be installed and associated with .pdf files
    // that handles the "printto" verb. The doc_name and options are not used in this case.
    (void)doc_name;
    (void)num_options;
    (void)option_keys;
    (void)option_values;

    HINSTANCE result = ShellExecuteA(
        NULL,          // No parent window
        "printto",     // Verb
        pdf_file_path, // File to print
        printer_name,  // Printer name
        NULL,          // No working directory
        SW_HIDE        // Don't show the application window
    );

    // According to MSDN, if the function succeeds, it returns a value greater than 32.
    return ((intptr_t)result > 32);
#else // macOS / Linux
    cups_option_t* options = NULL;
    int num_cups_options = 0;

    for (int i = 0; i < num_options; i++) {
        num_cups_options = cupsAddOption(option_keys[i], option_values[i], num_cups_options, &options);
    }

    int job_id = cupsPrintFile(printer_name, pdf_file_path, doc_name, num_cups_options, options);
    cupsFreeOptions(num_cups_options, options);
    return job_id > 0;
#endif
}

FFI_PLUGIN_EXPORT JobList* get_print_jobs(const char* printer_name) {
    JobList* list = (JobList*)malloc(sizeof(JobList));
    if (!list) return NULL;
    list->count = 0;
    list->jobs = NULL;

#ifdef _WIN32
    HANDLE hPrinter;
    DWORD needed, returned;

    if (!OpenPrinterA((LPSTR)printer_name, &hPrinter, NULL)) {
        free(list);
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
    }
    free(buffer);
    ClosePrinter(hPrinter);
    return list;
#else // macOS
    cups_job_t* jobs;
    int num_jobs = cupsGetJobs(&jobs, printer_name, 1, CUPS_WHICHJOBS_ACTIVE);
    if (num_jobs <= 0) {
        cupsFreeJobs(num_jobs, jobs);
        return list;
    }

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
#ifdef _WIN32
    HANDLE hPrinter;
    if (!OpenPrinterA((LPSTR)printer_name, &hPrinter, NULL)) return false;
    bool result = SetJobA(hPrinter, job_id, 0, NULL, JOB_CONTROL_PAUSE);
    ClosePrinter(hPrinter);
    return result;
#else
    return cupsCancelJob2(CUPS_HTTP_DEFAULT, printer_name, job_id, IPP_HOLD_JOB) == 1;
#endif
}

FFI_PLUGIN_EXPORT bool resume_print_job(const char* printer_name, uint32_t job_id) {
#ifdef _WIN32
    HANDLE hPrinter;
    if (!OpenPrinterA((LPSTR)printer_name, &hPrinter, NULL)) return false;
    bool result = SetJobA(hPrinter, job_id, 0, NULL, JOB_CONTROL_RESUME);
    ClosePrinter(hPrinter);
    return result;
#else
    return cupsCancelJob2(CUPS_HTTP_DEFAULT, printer_name, job_id, IPP_RELEASE_JOB) == 1;
#endif
}

FFI_PLUGIN_EXPORT bool cancel_print_job(const char* printer_name, uint32_t job_id) {
#ifdef _WIN32
    HANDLE hPrinter;
    if (!OpenPrinterA((LPSTR)printer_name, &hPrinter, NULL)) return false;
    bool result = SetJobA(hPrinter, job_id, 0, NULL, JOB_CONTROL_CANCEL);
    ClosePrinter(hPrinter);
    return result;
#else
    return cupsCancelJob(printer_name, job_id) == 1;
#endif
}

FFI_PLUGIN_EXPORT CupsOptionList* get_supported_cups_options(const char* printer_name) {
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
        return list;
    }

    ppd_file_t* ppd = ppdOpenFile(ppd_filename);
    if (!ppd) {
        return list;
    }

    ppdMarkDefaults(ppd);

    int num_ui_options = 0;
    for (int i = 0; i < ppd->num_groups; i++) {
        num_ui_options += ppd->groups[i].num_options;
    }

    if (num_ui_options == 0) {
        ppdClose(ppd);
        return list;
    }

    list->count = num_ui_options;
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