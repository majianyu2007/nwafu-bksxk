import 'ics_export.dart';

Future<IcsExportOutcome> exportText(
  String content,
  String fileName,
  ExportKind kind,
) async =>
    throw UnsupportedError('此平台不支持导出文件');
