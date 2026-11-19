/// Appearance settings: theme mode, UI scale mode, text scale, glass toggle,
/// dynamic color, and seed color picker.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../app/ui_prefs.dart';

class AppearanceSettings extends ConsumerWidget {
  const AppearanceSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeControllerProvider);
    final ctrl = ref.read(themeControllerProvider.notifier);
    final scaleMode = ref.watch(uiScaleModeProvider);
    final textScale = ref.watch(textScaleProvider);
    final glassEnabled = ref.watch(glassEnabledProvider);
    final scheme = Theme.of(context).colorScheme;
    final custom =
        !theme.useDynamic &&
        !kSeedPresets.any((p) => p.$2.toARGB32() == theme.seed.toARGB32());
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const ListTile(
          leading: Icon(Icons.brightness_6_outlined),
          title: Text('显示模式'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (mode, label) in const [
                (ThemeMode.system, '系统'),
                (ThemeMode.light, '浅色'),
                (ThemeMode.dark, '深色'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: theme.mode == mode,
                  onSelected: (_) => ctrl.setMode(mode),
                ),
            ],
          ),
        ),
        ListTile(
          leading: const Icon(Icons.aspect_ratio_outlined),
          title: Text('界面缩放 · ${scaleMode.label}'),
          subtitle: const Text('自动模式会在小屏手机、横屏与高分大屏上智能调整密度与比例'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final mode in UiScaleMode.values)
                ChoiceChip(
                  label: Text(mode.label),
                  selected: scaleMode == mode,
                  onSelected: (_) =>
                      ref.read(uiPrefsProvider.notifier).setScaleMode(mode),
                ),
            ],
          ),
        ),
        ListTile(
          leading: const Icon(Icons.text_fields),
          title: Text('文字大小 ${(textScale * 100).round()}%'),
          subtitle: const Text('叠加系统字体大小；4K 屏可适当调大。'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final scale in const [0.85, 1.0, 1.15, 1.3, 1.45, 1.6])
                ChoiceChip(
                  label: Text('${(scale * 100).round()}%'),
                  selected: (textScale - scale).abs() < 0.01,
                  onSelected: (_) =>
                      ref.read(textScaleProvider.notifier).set(scale),
                ),
            ],
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.blur_on),
          title: const Text('玻璃效果'),
          subtitle: const Text('半透明导航与卡片；关闭后使用纯色表面，更省电'),
          value: glassEnabled,
          onChanged: ref.read(uiPrefsProvider.notifier).setGlass,
        ),
        SwitchListTile(
          secondary: const Icon(Icons.palette_outlined),
          title: const Text('跟随系统强调色'),
          value: theme.useDynamic,
          onChanged: ctrl.setUseDynamic,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Opacity(
            opacity: theme.useDynamic ? 0.4 : 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('主题色', style: TextStyle(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final (name, c) in kSeedPresets)
                      _Swatch(
                        color: c,
                        tooltip: name,
                        selected:
                            !theme.useDynamic &&
                            theme.seed.toARGB32() == c.toARGB32(),
                        onTap: () => ctrl.setSeed(c),
                      ),
                    _Swatch(
                      color: custom ? theme.seed : null,
                      tooltip: '自定义',
                      selected: custom,
                      onTap: () => _pickCustom(context, ref, theme.seed),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickCustom(
    BuildContext context,
    WidgetRef ref,
    Color initial,
  ) async {
    final picked = await showDialog<Color>(
      context: context,
      builder: (_) => _HuePickerDialog(initial: initial),
    );
    if (picked != null && context.mounted) {
      await ref.read(themeControllerProvider.notifier).setSeed(picked);
    }
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });
  final Color? color;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 36,
          width: 36,
          decoration: BoxDecoration(
            color: color,
            gradient: color == null
                ? const SweepGradient(
                    colors: [
                      Colors.red,
                      Colors.yellow,
                      Colors.green,
                      Colors.cyan,
                      Colors.blue,
                      Colors.purple,
                      Colors.red,
                    ],
                  )
                : null,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? scheme.onSurface : Colors.transparent,
              width: 3,
            ),
          ),
          child: selected
              ? const Icon(Icons.check, color: Colors.white, size: 18)
              : color == null
              ? const Icon(Icons.add, color: Colors.white, size: 18)
              : null,
        ),
      ),
    );
  }
}

/// Hue / saturation / lightness sliders with a live preview.
class _HuePickerDialog extends StatefulWidget {
  const _HuePickerDialog({required this.initial});
  final Color initial;

  @override
  State<_HuePickerDialog> createState() => _HuePickerDialogState();
}

class _HuePickerDialogState extends State<_HuePickerDialog> {
  late HSLColor _hsl = HSLColor.fromColor(widget.initial);

  @override
  Widget build(BuildContext context) {
    final color = _hsl.toColor();
    final scheme = ColorScheme.fromSeed(
      seedColor: color,
      brightness: Theme.of(context).brightness,
    );
    Widget slider(
      String label,
      double value,
      double max,
      ValueChanged<double> onChanged,
    ) {
      return Row(
        children: [
          SizedBox(width: 40, child: Text(label)),
          Expanded(
            child: Slider(value: value, max: max, onChanged: onChanged),
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Text('自定义主题色'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 56,
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                style: TextStyle(
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 12),
            slider(
              '色相',
              _hsl.hue,
              360,
              (v) => setState(() => _hsl = _hsl.withHue(v)),
            ),
            slider(
              '饱和度',
              _hsl.saturation,
              1,
              (v) => setState(() => _hsl = _hsl.withSaturation(v)),
            ),
            slider(
              '明度',
              _hsl.lightness,
              1,
              (v) => setState(() => _hsl = _hsl.withLightness(v)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, color),
          child: const Text('使用'),
        ),
      ],
    );
  }
}
