/// Bounded in-memory image cache, authenticated library image widget, and
/// entrance QR bottom sheet.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../data/library_service.dart';
import 'library_common.dart';

const _kMaxCachedImages = 32;

class LibraryImageCacheEntry {
  LibraryImageCacheEntry(this.bytes, {this.aspectRatio});
  final Uint8List bytes;
  double? aspectRatio;
}

/// Bounded LRU cache for library photos and floorplans fetched through
/// [LibraryService.fetchImageBytes] (Dart map literals preserve insertion order).
final _imageCache = <String, LibraryImageCacheEntry>{};

LibraryImageCacheEntry? peekLibraryImageCache(String url) {
  final hit = _imageCache.remove(url);
  if (hit != null) {
    _imageCache[url] = hit;
  }
  return hit;
}

LibraryImageCacheEntry putLibraryImageCache(
  String url,
  Uint8List bytes, {
  double? aspectRatio,
}) {
  final existing = _imageCache.remove(url);
  final entry = LibraryImageCacheEntry(
    bytes,
    aspectRatio: aspectRatio ?? existing?.aspectRatio,
  );
  _imageCache[url] = entry;
  while (_imageCache.length > _kMaxCachedImages) {
    _imageCache.remove(_imageCache.keys.first);
  }
  return entry;
}

Future<LibraryImageCacheEntry> fetchCachedLibraryImage(
  LibraryService lib,
  String url,
) async {
  final hit = peekLibraryImageCache(url);
  if (hit != null) return hit;
  final bytes = await lib.fetchImageBytes(url);
  return putLibraryImageCache(url, bytes);
}

class LibraryImage extends ConsumerStatefulWidget {
  const LibraryImage({super.key, required this.url, this.fit = BoxFit.cover});
  final String url;
  final BoxFit fit;

  @override
  ConsumerState<LibraryImage> createState() => _LibraryImageState();
}

class _LibraryImageState extends ConsumerState<LibraryImage> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant LibraryImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _load();
  }

  Future<void> _load() async {
    final url = widget.url;
    final cached = peekLibraryImageCache(url);
    if (cached != null) {
      setState(() {
        _bytes = cached.bytes;
        _failed = false;
      });
      return;
    }
    setState(() {
      _bytes = null;
      _failed = false;
    });
    try {
      final entry = await fetchCachedLibraryImage(
        ref.read(libraryServiceProvider),
        url,
      );
      if (!mounted || widget.url != url) return;
      setState(() {
        _bytes = entry.bytes;
        _failed = false;
      });
    } catch (_) {
      if (!mounted || widget.url != url) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_bytes != null) {
      return Image.memory(_bytes!, fit: widget.fit, gaplessPlayback: true);
    }
    return ColoredBox(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      child: Center(
        child: Icon(
          _failed ? Icons.meeting_room_outlined : Icons.image_outlined,
          size: 22,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Opens the Library entrance QR sheet from anywhere in the app (e.g. MePage).
void showLibraryQrSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => const SafeArea(child: LibraryQrSheet()),
  );
}

class LibraryQrSheet extends ConsumerStatefulWidget {
  const LibraryQrSheet({super.key});

  @override
  ConsumerState<LibraryQrSheet> createState() => _LibraryQrSheetState();
}

class _LibraryQrSheetState extends ConsumerState<LibraryQrSheet> {
  String? _decodedSource;
  Uint8List? _decodedBytes;

  Uint8List? _decodeQr(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw == _decodedSource) return _decodedBytes;
    _decodedSource = raw;
    try {
      final payload = raw.substring(raw.indexOf(',') + 1).trim();
      _decodedBytes = payload.isEmpty ? null : base64Decode(payload);
    } catch (_) {
      _decodedBytes = null;
    }
    return _decodedBytes;
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(libraryMemberProvider);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: async.when(
        loading: () => const SizedBox(
          height: 240,
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => SizedBox(
          height: 180,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(e is AppError ? e.message : '入馆码暂时取不到'),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => ref.invalidate(libraryMemberProvider),
                  child: const Text('重试'),
                ),
              ],
            ),
          ),
        ),
        data: (m) {
          final bytes = _decodeQr(m.qrImage);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('入馆码', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                [m.name, m.roleName].where((s) => s.isNotEmpty).join(' · '),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              if (bytes == null)
                const Text('图书馆没有返回有效的入馆码')
              else
                Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.white,
                  child: Image.memory(
                    bytes,
                    width: 220,
                    height: 220,
                    filterQuality: FilterQuality.none,
                    gaplessPlayback: true,
                  ),
                ),
              const SizedBox(height: 12),
              Text('在闸机扫码入馆', style: theme.textTheme.bodySmall),
            ],
          );
        },
      ),
    );
  }
}
