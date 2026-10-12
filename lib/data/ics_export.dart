/// Saves or shares a built `.ics` document: share sheet on Android/iOS,
/// a save dialog on desktop, a browser download on the web.
library;

import 'ics_export_stub.dart'
    if (dart.library.io) 'ics_export_io.dart'
    if (dart.library.js_interop) 'ics_export_web.dart'
    as impl;

enum IcsExportOutcome { shared, saved, downloaded, cancelled }

/// What kind of text file is being exported.
class ExportKind {
  const ExportKind(this.label, this.extension, this.mime, this.uti);
  final String label;
  final String extension;
  final String mime;
  final String uti;

  static const ics = ExportKind(
    'iCalendar',
    'ics',
    'text/calendar',
    'com.apple.ical.ics',
  );
  static const csv = ExportKind(
    'CSV',
    'csv',
    'text/csv',
    'public.comma-separated-values-text',
  );
}

/// [fileName] should end in `.ics`. Throws on I/O failure.
Future<IcsExportOutcome> exportIcsFile(String content, String fileName) =>
    impl.exportText(content, fileName, ExportKind.ics);

/// Saves or shares any UTF-8 text file the same way.
Future<IcsExportOutcome> exportTextFile(
  String content,
  String fileName,
  ExportKind kind,
) => impl.exportText(content, fileName, kind);

/// `课表-2026-2027-1.ics`, safe for every file system.
String icsFileName(String termCode) =>
    '课表-${termCode.replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_')}.ics';
