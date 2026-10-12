import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'ics_export.dart';

Future<IcsExportOutcome> exportText(
  String content,
  String fileName,
  ExportKind kind,
) async {
  final bytes = utf8.encode(content);
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: '${kind.mime};charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName;
  web.document.body?.append(a);
  a.click();
  a.remove();
  Future.delayed(
    const Duration(seconds: 30),
    () => web.URL.revokeObjectURL(url),
  );
  return IcsExportOutcome.downloaded;
}
