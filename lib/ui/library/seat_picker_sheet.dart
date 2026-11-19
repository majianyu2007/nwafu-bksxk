/// Native seat picker: interactive zoomable floorplan map + searchable grid,
/// date & time-slot selection, and one-tap native booking.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../data/library_service.dart';
import '../widgets.dart';
import '../widgets/glass.dart';
import 'library_common.dart';
import 'library_media.dart';

class SeatPickerSheet extends ConsumerStatefulWidget {
  const SeatPickerSheet({super.key, required this.area});
  final LibraryArea area;

  @override
  ConsumerState<SeatPickerSheet> createState() => _SeatPickerSheetState();
}

class _SeatPickerSheetState extends ConsumerState<SeatPickerSheet> {
  List<LibraryBookDate>? _dates;
  LibrarySeatMap? _seatMap;
  String? _mapError;
  String? _datesError;
  String? _seatsError;
  int _dateIndex = 0;
  int _slotIndex = 0;
  List<LibrarySeat>? _seats;
  LibrarySeat? _selectedSeat;
  bool _loadingSeats = false;
  bool _mapMode = true;
  bool _freeOnly = true;
  bool _booking = false;
  final _searchCtrl = TextEditingController();
  String _query = '';
  final _transform = TransformationController();
  int _seatLoadSeq = 0;

  @override
  void initState() {
    super.initState();
    _loadDatesAndMap();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _transform.dispose();
    super.dispose();
  }

  Future<void> _loadDatesAndMap() async {
    setState(() {
      _dates = null;
      _datesError = null;
      _seatsError = null;
      _mapError = null;
      _seats = null;
      _selectedSeat = null;
    });
    final lib = ref.read(libraryServiceProvider);
    // Fetch floorplan map in parallel; record error rather than swallowing silently.
    String? mapErr;
    final mapFuture = lib.seatMap(widget.area.id).catchError((Object e) {
      mapErr = e is AppError ? e.message : '楼层参考图暂不可用';
      return null;
    });
    try {
      final dates = await lib.seatDates(widget.area.id);
      final map = await mapFuture;
      if (!mounted) return;
      setState(() {
        _dates = dates;
        _seatMap = map;
        _mapError = mapErr;
        _mapMode = map != null && map.hasImage;
        _dateIndex = 0;
        _slotIndex = 0;
      });
      if (dates.isNotEmpty && dates.first.times.isNotEmpty) {
        await _loadSeats();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _datesError = e is AppError ? e.message : '无法加载可预约时段';
      });
    }
  }

  Future<void> _loadSeats() async {
    final dates = _dates;
    if (dates == null || dates.isEmpty) return;
    final day = dates[_dateIndex.clamp(0, dates.length - 1)];
    if (day.times.isEmpty) {
      setState(() {
        _seats = const [];
        _seatsError = null;
        _selectedSeat = null;
      });
      return;
    }
    final slot = day.times[_slotIndex.clamp(0, day.times.length - 1)];
    final seq = ++_seatLoadSeq;
    setState(() {
      _loadingSeats = true;
      _seatsError = null;
      _selectedSeat = null;
    });
    try {
      final list = await ref
          .read(libraryServiceProvider)
          .seats(widget.area.id, day: day.day, slot: slot);
      if (!mounted || seq != _seatLoadSeq) return;
      setState(() {
        _seats = list;
        _loadingSeats = false;
      });
    } catch (e) {
      if (!mounted || seq != _seatLoadSeq) return;
      setState(() {
        _loadingSeats = false;
        _seatsError = e is AppError ? e.message : '无法加载座位列表';
      });
    }
  }

  Future<void> _confirmBook(LibrarySeat seat) async {
    final dates = _dates;
    if (dates == null || dates.isEmpty || _booking) return;
    final day = dates[_dateIndex.clamp(0, dates.length - 1)];
    if (day.times.isEmpty) return;
    final slot = day.times[_slotIndex.clamp(0, day.times.length - 1)];
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认预约座位'),
        content: Text(
          '${widget.area.name} · ${seat.no} 号座\n'
          '${day.day} ${slot.label}'
          '${seat.donorLabel.isNotEmpty ? '\n\n${seat.donorLabel}' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('预约'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _booking = true);
    try {
      final msg = await ref
          .read(libraryServiceProvider)
          .bookSeat(seatId: seat.id, segmentId: slot.id);
      if (!mounted) return;
      showToast(context, msg, success: true);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showToast(context, e is AppError ? e.message : '预约失败', success: false);
      setState(() => _booking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dates = _dates;
    final currentDay = dates != null && dates.isNotEmpty
        ? dates[_dateIndex.clamp(0, dates.length - 1)]
        : null;
    final currentSlot = currentDay != null && currentDay.times.isNotEmpty
        ? currentDay.times[_slotIndex.clamp(0, currentDay.times.length - 1)]
        : null;
    final allSeats = _seats ?? const <LibrarySeat>[];
    final canShowMap = _seatMap != null && _seatMap!.hasImage;
    final needle = _query.toLowerCase();
    final filtered = allSeats.where((s) {
      if (_freeOnly && !s.isFree) return false;
      if (needle.isNotEmpty &&
          !s.no.toLowerCase().contains(needle) &&
          !s.name.toLowerCase().contains(needle)) {
        return false;
      }
      return true;
    }).toList();
    final freeCount = allSeats.where((s) => s.isFree).length;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.84,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 12 + bottomInset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.area.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          [
                            widget.area.campus,
                            widget.area.floor,
                            if (_seats != null)
                              '空座 $freeCount / ${allSeats.length}',
                          ].where((s) => s.isNotEmpty).join(' · '),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  if (canShowMap)
                    SegmentedButton<bool>(
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                      ),
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: true,
                          icon: Icon(Icons.map_outlined, size: 16),
                          label: Text('平面图'),
                        ),
                        ButtonSegment(
                          value: false,
                          icon: Icon(Icons.grid_view_outlined, size: 16),
                          label: Text('列表'),
                        ),
                      ],
                      selected: {_mapMode},
                      onSelectionChanged: (v) =>
                          setState(() => _mapMode = v.first),
                    ),
                  IconButton(
                    tooltip: '关闭',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (dates == null && _datesError == null)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_datesError != null)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_datesError!),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _loadDatesAndMap,
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                )
              else if (dates!.isEmpty)
                const Expanded(child: Center(child: Text('当前没有可预约的日期')))
              else ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < dates.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(dates[i].day),
                            selected: i == _dateIndex,
                            onSelected: _booking
                                ? null
                                : (_) {
                                    setState(() {
                                      _dateIndex = i;
                                      _slotIndex = 0;
                                    });
                                    _loadSeats();
                                  },
                          ),
                        ),
                    ],
                  ),
                ),
                if (currentDay != null && currentDay.times.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < currentDay.times.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(currentDay.times[i].label),
                              selected: i == _slotIndex,
                              onSelected: _booking
                                  ? null
                                  : (_) {
                                      setState(() => _slotIndex = i);
                                      _loadSeats();
                                    },
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                if (_mapError != null && !canShowMap) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '平面图未加载：$_mapError（已切换为列表选座）',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
                if (!(_mapMode && canShowMap))
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            isDense: true,
                            prefixIcon: const Icon(Icons.search, size: 18),
                            hintText: '搜索座位号',
                            border: const OutlineInputBorder(),
                            suffixIcon: _query.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: '清空',
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      setState(() => _query = '');
                                    },
                                  ),
                          ),
                          onChanged: (v) => setState(() => _query = v.trim()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilterChip(
                        label: const Text('仅空座'),
                        selected: _freeOnly,
                        onSelected: (v) => setState(() => _freeOnly = v),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      const Expanded(child: _SeatMapLegend()),
                      IconButton(
                        tooltip: '重置缩放',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.center_focus_strong, size: 20),
                        onPressed: () =>
                            _transform.value = Matrix4.identity(),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                Expanded(
                  child: _seatsError != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_seatsError!),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: _loadSeats,
                                child: const Text('重试'),
                              ),
                            ],
                          ),
                        )
                      : (_mapMode && canShowMap)
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            _FloorplanSeatMap(
                              imageUrl: _seatMap!.freeUrl,
                              seats: allSeats,
                              selectedSeatId: _selectedSeat?.id,
                              controller: _transform,
                              onSelect: (seat) =>
                                  setState(() => _selectedSeat = seat),
                            ),
                            if (_loadingSeats)
                              ColoredBox(
                                color: scheme.surface.withValues(alpha: 0.45),
                                child: const Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                          ],
                        )
                      : _loadingSeats
                      ? const Center(child: CircularProgressIndicator())
                      : filtered.isEmpty
                      ? const Center(child: Text('该时段没有符合条件的座位'))
                      : LayoutBuilder(
                          builder: (context, c) {
                            final cols = (c.maxWidth / 84).floor().clamp(3, 8);
                            return GridView.builder(
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: cols,
                                    mainAxisSpacing: 8,
                                    crossAxisSpacing: 8,
                                    childAspectRatio: 1.5,
                                  ),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final s = filtered[index];
                                final picked = _selectedSeat?.id == s.id;
                                return Material(
                                  color: picked
                                      ? scheme.primary
                                      : s.isFree
                                      ? scheme.primaryContainer
                                      : scheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(10),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: s.isFree && !_booking
                                        ? () => _confirmBook(s)
                                        : null,
                                    child: Center(
                                      child: Text(
                                        s.no,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.labelLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: picked
                                                  ? scheme.onPrimary
                                                  : s.isFree
                                                  ? scheme.onPrimaryContainer
                                                  : scheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
                if (_selectedSeat != null &&
                    currentDay != null &&
                    currentSlot != null) ...[
                  const SizedBox(height: 8),
                  GlassCard(
                    padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                    tint: scheme.primary,
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '已选 ${_selectedSeat!.no} 号座',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${currentDay.day} ${currentSlot.label}',
                                style: theme.textTheme.bodySmall,
                              ),
                              if (_selectedSeat!.donorLabel.isNotEmpty)
                                Text(
                                  _selectedSeat!.donorLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.primary,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        FilledButton(
                          onPressed: _booking
                              ? null
                              : () => _confirmBook(_selectedSeat!),
                          child: Text(_booking ? '预约中…' : '立即预约'),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SeatMapLegend extends StatelessWidget {
  const _SeatMapLegend();

  @override
  Widget build(BuildContext context) {
    Widget dot(Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 10,
      runSpacing: 4,
      children: [
        dot(Colors.green.withValues(alpha: 0.75), '空闲'),
        dot(scheme.primary, '已选'),
        dot(Colors.orange.withValues(alpha: 0.75), '暂离'),
        dot(Colors.blueGrey.withValues(alpha: 0.65), '已约/使用'),
        dot(Colors.grey.withValues(alpha: 0.45), '不可用'),
      ],
    );
  }
}

/// Interactive zoomable/pannable floorplan with percentage-positioned seats.
/// Fetches the reference image through [LibraryService.fetchImageBytes] so Web
/// CanvasKit avoids CORS failures and native works through CampusProxy VPN.
class _FloorplanSeatMap extends ConsumerStatefulWidget {
  const _FloorplanSeatMap({
    required this.imageUrl,
    required this.seats,
    required this.selectedSeatId,
    required this.controller,
    required this.onSelect,
  });

  final String imageUrl;
  final List<LibrarySeat> seats;
  final String? selectedSeatId;
  final TransformationController controller;
  final ValueChanged<LibrarySeat> onSelect;

  @override
  ConsumerState<_FloorplanSeatMap> createState() => _FloorplanSeatMapState();
}

class _FloorplanSeatMapState extends ConsumerState<_FloorplanSeatMap> {
  Uint8List? _bytes;
  double? _aspectRatio;
  bool _loading = true;
  bool _failed = false;
  int _imageSeq = 0;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(covariant _FloorplanSeatMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    final url = widget.imageUrl;
    final seq = ++_imageSeq;
    final cached = peekLibraryImageCache(url);
    if (cached != null) {
      setState(() {
        _bytes = cached.bytes;
        _aspectRatio = cached.aspectRatio;
        _loading = false;
        _failed = false;
      });
      if (cached.aspectRatio == null) {
        _decodeAspectRatio(url, cached.bytes, seq);
      }
      return;
    }
    setState(() {
      _bytes = null;
      _aspectRatio = null;
      _loading = true;
      _failed = false;
    });
    try {
      final entry = await fetchCachedLibraryImage(
        ref.read(libraryServiceProvider),
        url,
      );
      if (!mounted || seq != _imageSeq) return;
      setState(() {
        _bytes = entry.bytes;
        _aspectRatio = entry.aspectRatio;
        _loading = false;
      });
      if (entry.aspectRatio == null) {
        _decodeAspectRatio(url, entry.bytes, seq);
      }
    } catch (_) {
      if (!mounted || seq != _imageSeq) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _decodeAspectRatio(String url, Uint8List bytes, int seq) {
    ui.decodeImageFromList(bytes, (img) {
      final ratio =
          img.width > 0 && img.height > 0 ? img.width / img.height : null;
      // Always release the GPU texture even if the widget already unmounted.
      img.dispose();
      if (ratio != null) {
        peekLibraryImageCache(url)?.aspectRatio = ratio;
      }
      if (!mounted || seq != _imageSeq || ratio == null) return;
      setState(() => _aspectRatio = ratio);
    });
  }

  Color _seatColor(LibrarySeat seat, bool selected, ColorScheme scheme) {
    if (selected) return scheme.primary.withValues(alpha: 0.9);
    return switch (seat.visualStatus) {
      LibrarySeatStatus.free => Colors.green.withValues(alpha: 0.34),
      LibrarySeatStatus.leave => Colors.orange.withValues(alpha: 0.55),
      LibrarySeatStatus.booked => Colors.blueGrey.withValues(alpha: 0.5),
      LibrarySeatStatus.inUse => Colors.blueGrey.withValues(alpha: 0.65),
      LibrarySeatStatus.closed => Colors.grey.withValues(alpha: 0.45),
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ratio = _aspectRatio ?? (16 / 10);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLowest,
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: InteractiveViewer(
          transformationController: widget.controller,
          minScale: 1.0,
          maxScale: 5.0,
          boundaryMargin: const EdgeInsets.all(24),
          child: Center(
            child: AspectRatio(
              aspectRatio: ratio,
              child: LayoutBuilder(
                builder: (context, c) {
                  final w = c.maxWidth;
                  final h = c.maxHeight;
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_bytes != null)
                        Image.memory(
                          _bytes!,
                          fit: BoxFit.fill,
                          gaplessPlayback: true,
                        )
                      else if (_loading)
                        const Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else if (_failed)
                        Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Text(
                              '底图未加载（座位仍可直接点选）',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ),
                      for (final seat in widget.seats)
                        if (seat.hasCoords)
                          Positioned(
                            left: (seat.pointX! / 100) * w,
                            top: (seat.pointY! / 100) * h,
                            width: (seat.width! / 100) * w,
                            height: (seat.height! / 100) * h,
                            child: Tooltip(
                              message:
                                  '${seat.no} 号座 · ${seat.isFree ? '空闲' : seat.statusName}',
                              child: GestureDetector(
                                onTap: seat.isFree
                                    ? () => widget.onSelect(seat)
                                    : null,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: _seatColor(
                                      seat,
                                      seat.id == widget.selectedSeatId,
                                      scheme,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: seat.id == widget.selectedSeatId
                                          ? scheme.onPrimary
                                          : seat.isFree
                                          ? Colors.green.shade700
                                          : Colors.transparent,
                                      width: seat.id == widget.selectedSeatId
                                          ? 1.8
                                          : 0.8,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
