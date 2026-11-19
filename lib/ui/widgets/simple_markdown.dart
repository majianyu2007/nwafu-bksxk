/// A small Markdown renderer for release notes: headings, bullet and numbered
/// lists, paragraphs, **bold**, `code` and [links](url). Release notes use
/// nothing else, and a full Markdown package is not worth the bundle size.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class SimpleMarkdown extends StatefulWidget {
  const SimpleMarkdown(this.source, {super.key, this.onLink});
  final String source;
  final void Function(Uri uri)? onLink;

  @override
  State<SimpleMarkdown> createState() => _SimpleMarkdownState();
}

class _SimpleMarkdownState extends State<SimpleMarkdown> {
  final _recognizers = <TapGestureRecognizer>[];

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final theme = Theme.of(context);
    final blocks = <Widget>[];
    final para = <String>[];

    void flush() {
      if (para.isEmpty) return;
      blocks.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _inline(context, para.join(' '), theme.textTheme.bodyMedium),
        ),
      );
      para.clear();
    }

    for (final raw in widget.source.replaceAll('\r\n', '\n').split('\n')) {
      final line = raw.trimRight();
      final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
      final bullet = RegExp(r'^(\s*)[-*+]\s+(.*)$').firstMatch(line);
      final number = RegExp(r'^(\s*)(\d+)[.)]\s+(.*)$').firstMatch(line);
      if (line.trim().isEmpty) {
        flush();
      } else if (heading != null) {
        flush();
        final level = heading[1]!.length;
        blocks.add(
          Padding(
            padding: EdgeInsets.only(top: blocks.isEmpty ? 0 : 10, bottom: 6),
            child: _inline(
              context,
              heading[2]!,
              (level <= 2
                      ? theme.textTheme.titleMedium
                      : theme.textTheme.titleSmall)
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        );
      } else if (bullet != null || number != null) {
        flush();
        final indent = (bullet?[1] ?? number![1]!).length ~/ 2;
        final mark = bullet != null ? '•' : '${number![2]}.';
        final text = bullet?[2] ?? number![3]!;
        blocks.add(
          Padding(
            padding: EdgeInsets.only(left: 4.0 + indent * 16, bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 20),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Text(mark, style: theme.textTheme.bodyMedium),
                  ),
                ),
                Expanded(
                  child: _inline(context, text, theme.textTheme.bodyMedium),
                ),
              ],
            ),
          ),
        );
      } else {
        para.add(line.trim());
      }
    }
    flush();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
  }

  Widget _inline(BuildContext context, String text, TextStyle? style) {
    final scheme = Theme.of(context).colorScheme;
    final spans = <InlineSpan>[];
    final token = RegExp(r'\*\*(.+?)\*\*|`([^`]+)`|\[([^\]]+)\]\(([^)\s]+)\)');
    var at = 0;
    for (final m in token.allMatches(text)) {
      if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
      if (m[1] != null) {
        spans.add(
          TextSpan(
            text: m[1],
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        );
      } else if (m[2] != null) {
        spans.add(
          TextSpan(
            text: m[2],
            style: TextStyle(
              fontFamily: 'monospace',
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        );
      } else {
        final uri = Uri.tryParse(m[4]!);
        TapGestureRecognizer? rec;
        if (uri != null && widget.onLink != null) {
          rec = TapGestureRecognizer()..onTap = () => widget.onLink!(uri);
          _recognizers.add(rec);
        }
        spans.add(
          TextSpan(
            text: m[3],
            style: TextStyle(
              color: scheme.primary,
              decoration: TextDecoration.underline,
            ),
            recognizer: rec,
          ),
        );
      }
      at = m.end;
    }
    if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
    return SelectableText.rich(TextSpan(style: style, children: spans));
  }
}
