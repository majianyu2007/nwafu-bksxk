import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'ics_export.dart';

Future<IcsExportOutcome> exportText(
  String content,
  String fileName,
  ExportKind kind,
) async {
  final bytes = utf8.encode(content);
  if (Platform.isAndroid || Platform.isIOS) {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    final r = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: kind.mime)],
        subject: fileName,
      ),
    );
    return r.status == ShareResultStatus.dismissed
        ? IcsExportOutcome.cancelled
        : IcsExportOutcome.shared;
  }
  final location = await getSaveLocation(
    suggestedName: fileName,
    acceptedTypeGroups: [
      XTypeGroup(
        label: kind.label,
        extensions: [kind.extension],
        mimeTypes: [kind.mime],
        uniformTypeIdentifiers: [kind.uti],
      ),
    ],
  );
  if (location == null) return IcsExportOutcome.cancelled;
  var path = location.path;
  if (!path.toLowerCase().endsWith('.${kind.extension}')) {
    path = '$path.${kind.extension}';
  }
  await File(path).writeAsBytes(bytes, flush: true);
  return IcsExportOutcome.saved;
}
