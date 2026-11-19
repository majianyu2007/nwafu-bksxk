/// A small Markdown renderer for release notes: headings, bullet and numbered
/// lists, paragraphs, **bold**, `code` and [links](url). Release notes use
/// nothing else, and a full Markdown package is not worth the bundle size.
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

final _mdHeadingRe = RegExp(r'^(#{1,6})\s+(.*)$');
final _mdBulletRe = RegExp(r'^(\s*)[-*+]\s+(.*)$');
final _mdNumberRe = RegExp(r'^(\s*)(\d+)[.)]\s+(.*)$');
final _mdTokenRe = RegExp(r'\*\*(.+?)\*\*|`([^`]+)`|\[([^\]]+)\]\(([^)\s]+)\)');

sealed class _MdBlock {
  const _MdBlock();
}

class _MdHeading extends _MdBlock {
  const _MdHeading(this.level, this.tokens);
  final int level;
  final List<_MdToken> tokens;
}

class _MdListItem extends _MdBlock {
  const _MdListItem(this.indent, this.mark, this.tokens);
  final int indent;
  final String mark;
  final List<_MdToken> tokens;
}

class _MdParagraph extends _MdBlock {
  const _MdParagraph(this.tokens);
  final List<_MdToken> tokens;
}

enum _MdTokenKind { plain, bold, code, link }

class _MdToken {
  const _MdToken(this.kind, this.text, {this.uri});
  final _MdTokenKind kind;
  final String text;
  final Uri? uri;
}

class SimpleMarkdown extends StatefulWidget {
  const SimpleMarkdown(this.source, {super.key, this.onLink});
  final String source;
  final void Function(Uri uri)? onLink;

  @override
  State<SimpleMarkdown> createState() => _SimpleMarkdownState();
}

class _SimpleMarkdownState extends State<SimpleMarkdown> {
  late List<_MdBlock> _blocks;
  final _recognizers = <Uri, TapGestureRecognizer>{};

  @override
  void initState() {
    super.initState();
    _rebuildModel();
  }

  @override
  void didUpdateWidget(SimpleMarkdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        (oldWidget.onLink != null) != (widget.onLink != null)) {
      _rebuildModel();
    }
  }

  void _rebuildModel() {
    _disposeRecognizers();
    _blocks = _parseBlocks(widget.source);
    if (widget.onLink != null) {
      for (final block in _blocks) {
        final tokens = switch (block) {
          _MdHeading(:final tokens) => tokens,
          _MdListItem(:final tokens) => tokens,
          _MdParagraph(:final tokens) => tokens,
        };
        for (final t in tokens) {
          final uri = t.uri;
          if (t.kind == _MdTokenKind.link && uri != null) {
            _recognizers.putIfAbsent(
              uri,
              () => TapGestureRecognizer()..onTap = () => widget.onLink?.call(uri),
            );
          }
        }
      }
    }
  }

  static List<_MdBlock> _parseBlocks(String source) {
    final blocks = <_MdBlock>[];
    final para = <String>[];

    void flush() {
      if (para.isEmpty) return;
      blocks.add(_MdParagraph(_parseInline(para.join(' '))));
      para.clear();
    }

    for (final raw in source.replaceAll('\r\n', '\n').split('\n')) {
      final line = raw.trimRight();
      final heading = _mdHeadingRe.firstMatch(line);
      final bullet = _mdBulletRe.firstMatch(line);
      final number = _mdNumberRe.firstMatch(line);
      if (line.trim().isEmpty) {
        flush();
      } else if (heading != null) {
        flush();
        blocks.add(_MdHeading(heading[1]!.length, _parseInline(heading[2]!)));
      } else if (bullet != null || number != null) {
        flush();
        final indent = (bullet?[1] ?? number![1]!).length ~/ 2;
        final mark = bullet != null ? '•' : '${number![2]}.';
        final text = bullet?[2] ?? number![3]!;
        blocks.add(_MdListItem(indent, mark, _parseInline(text)));
      } else {
        para.add(line.trim());
      }
    }
    flush();
    return blocks;
  }

  static List<_MdToken> _parseInline(String text) {
    final tokens = <_MdToken>[];
    var at = 0;
    for (final m in _mdTokenRe.allMatches(text)) {
      if (m.start > at) {
        tokens.add(_MdToken(_MdTokenKind.plain, text.substring(at, m.start)));
      }
      if (m[1] != null) {
        tokens.add(_MdToken(_MdTokenKind.bold, m[1]!));
      } else if (m[2] != null) {
        tokens.add(_MdToken(_MdTokenKind.code, m[2]!));
      } else {
        tokens.add(
          _MdToken(_MdTokenKind.link, m[3]!, uri: Uri.tryParse(m[4]!)),
        );
      }
      at = m.end;
    }
    if (at < text.length) {
      tokens.add(_MdToken(_MdTokenKind.plain, text.substring(at)));
    }
    return tokens;
  }

  void _disposeRecognizers() {
    for (final r in _recognizers.values) {
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
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < _blocks.length; i++)
          switch (_blocks[i]) {
            _MdHeading(:final level, :final tokens) => Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 10, bottom: 6),
              child: _renderInline(
                context,
                tokens,
                (level <= 2
                        ? theme.textTheme.titleMedium
                        : theme.textTheme.titleSmall)
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            _MdListItem(:final indent, :final mark, :final tokens) => Padding(
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
                    child: _renderInline(
                      context,
                      tokens,
                      theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
            _MdParagraph(:final tokens) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _renderInline(context, tokens, theme.textTheme.bodyMedium),
            ),
          },
      ],
    );
  }

  Widget _renderInline(
    BuildContext context,
    List<_MdToken> tokens,
    TextStyle? style,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final spans = <InlineSpan>[
      for (final t in tokens)
        switch (t.kind) {
          _MdTokenKind.plain => TextSpan(text: t.text),
          _MdTokenKind.bold => TextSpan(
            text: t.text,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          _MdTokenKind.code => TextSpan(
            text: t.text,
            style: TextStyle(
              fontFamily: 'monospace',
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          _MdTokenKind.link => _linkSpan(scheme, t),
        },
    ];
    return SelectableText.rich(TextSpan(style: style, children: spans));
  }

  TextSpan _linkSpan(ColorScheme scheme, _MdToken t) {
    final rec = t.uri == null ? null : _recognizers[t.uri!];
    if (rec == null) return TextSpan(text: t.text);
    return TextSpan(
      text: t.text,
      style: TextStyle(
        color: scheme.primary,
        decoration: TextDecoration.underline,
      ),
      recognizer: rec,
    );
  }
}
