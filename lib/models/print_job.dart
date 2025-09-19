import 'dart:io';

/// Represents the status of a print job.
enum PrintJobStatus {
  // Common states
  pending('Pending'),
  processing('Processing'),
  completed('Completed'),
  canceled('Canceled'),
  aborted('Aborted'),
  error('Error'),
  unknown('Unknown'),

  // Platform-specific or nuanced states
  held('Held'), // CUPS
  stopped('Stopped'), // CUPS
  paused('Paused'), // Windows
  spooling('Spooling'), // Windows
  deleting('Deleting'), // Windows
  restarting('Restarting'), // Windows
  offline('Offline'), // Windows
  paperOut('Paper Out'), // Windows
  userIntervention('User Intervention'); // Windows

  const PrintJobStatus(this.description);

  /// A user-friendly description of the status.
  final String description;

  /// Creates a [PrintJobStatus] from a raw platform-specific integer value.
  static PrintJobStatus fromRaw(int status) {
    if (Platform.isMacOS || Platform.isLinux) {
      // CUPS IPP Job States
      return switch (status) {
        3 => PrintJobStatus.pending, // IPP_JOB_PENDING
        4 => PrintJobStatus.held, // IPP_JOB_HELD
        5 => PrintJobStatus.processing, // IPP_JOB_PROCESSING
        6 => PrintJobStatus.stopped, // IPP_JOB_STOPPED
        7 => PrintJobStatus.canceled, // IPP_JOB_CANCELED
        8 => PrintJobStatus.aborted, // IPP_JOB_ABORTED
        9 => PrintJobStatus.completed, // IPP_JOB_COMPLETED
        _ => PrintJobStatus.unknown,
      };
    }

    if (Platform.isWindows) {
      // Windows Job Status bit flags. Order determines priority.
      if ((status & 0x00000002) != 0) return PrintJobStatus.error; // JOB_STATUS_ERROR
      if ((status & 0x00000400) != 0) return PrintJobStatus.userIntervention; // JOB_STATUS_USER_INTERVENTION
      if ((status & 0x00000040) != 0) return PrintJobStatus.paperOut; // JOB_STATUS_PAPEROUT
      if ((status & 0x00000020) != 0) return PrintJobStatus.offline; // JOB_STATUS_OFFLINE
      if ((status & 0x00000001) != 0) return PrintJobStatus.paused; // JOB_STATUS_PAUSED
      if ((status & 0x00000100) != 0) return PrintJobStatus.canceled; // JOB_STATUS_DELETED
      if ((status & 0x00000004) != 0) return PrintJobStatus.deleting; // JOB_STATUS_DELETING
      if ((status & 0x00000800) != 0) return PrintJobStatus.restarting; // JOB_STATUS_RESTART
      if ((status & 0x00000010) != 0) return PrintJobStatus.processing; // JOB_STATUS_PRINTING
      if ((status & 0x00000008) != 0) return PrintJobStatus.spooling; // JOB_STATUS_SPOOLING
      if ((status & 0x00001000) != 0) return PrintJobStatus.completed; // JOB_STATUS_COMPLETE
      if ((status & 0x00000080) != 0) return PrintJobStatus.completed; // JOB_STATUS_PRINTED
      if (status == 0) return PrintJobStatus.pending; // No flags, likely queued.

      return PrintJobStatus.unknown;
    }

    return PrintJobStatus.unknown;
  }
}

class PrintJob {
  final int id;
  final String title;

  /// The raw platform-specific status value.
  final int rawStatus;

  /// The parsed, cross-platform status.
  final PrintJobStatus status;

  PrintJob(this.id, this.title, this.rawStatus) : status = PrintJobStatus.fromRaw(rawStatus);

  /// A user-friendly description of the status.
  String get statusDescription => status.description;
}
