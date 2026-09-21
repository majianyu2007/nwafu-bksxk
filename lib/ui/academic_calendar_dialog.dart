import 'package:flutter/material.dart';

import '../data/academic_calendar.dart';

class AcademicCalendarDialog extends StatefulWidget {
  const AcademicCalendarDialog({
    super.key,
    required this.term,
    required this.today,
    required this.calendar,
  });

  final AcademicTerm term;
  final DateTime today;
  final AcademicCalendar? calendar;

  @override
  State<AcademicCalendarDialog> createState() => _AcademicCalendarDialogState();
}

class _AcademicCalendarDialogState extends State<AcademicCalendarDialog> {
  late final TextEditingController _week;
  late final TextEditingController _count;
  late DateTime _firstMonday;
  final _form = GlobalKey<FormState>();
  bool _byWeek = true;

  @override
  void initState() {
    super.initState();
    _week = TextEditingController(
      text: widget.calendar?.weekOn(widget.today)?.toString() ?? '',
    );
    _count = TextEditingController(
      text: (widget.calendar?.weekCount ?? 20).toString(),
    );
    _firstMonday = widget.calendar?.firstMonday ?? teachingMonday(widget.today);
  }

  @override
  void dispose() {
    _week.dispose();
    _count.dispose();
    super.dispose();
  }

  Future<void> _pickMonday() async {
    final selected = await showDatePicker(
      context: context,
      initialDate:
          DateTime(_firstMonday.year, _firstMonday.month, _firstMonday.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: '选择第一教学周的周一',
      selectableDayPredicate: (date) => date.weekday == DateTime.monday,
    );
    if (selected != null && mounted) {
      setState(() => _firstMonday = calendarDate(selected));
    }
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    final count = int.parse(_count.text.trim());
    final calendar = _byWeek
        ? AcademicCalendar.fromWeek(
            date: widget.today,
            week: int.parse(_week.text.trim()),
            weekCount: count,
          )
        : AcademicCalendar(
            firstMonday: _firstMonday,
            weekCount: count,
            source: CalendarSource.manual,
          );
    Navigator.pop(context, calendar);
  }

  @override
  Widget build(BuildContext context) {
    final today = widget.today;
    return AlertDialog(
      title: const Text('校准教学周'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(widget.term.label,
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                const Text('选课接口未提供开学日期。设置仅保存在本机，按北京时间每周一自动推进，不影响选课结果。'),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('设置当前周'),
                      selected: _byWeek,
                      onSelected: (_) => setState(() => _byWeek = true),
                    ),
                    ChoiceChip(
                      label: const Text('设置开学日期'),
                      selected: !_byWeek,
                      onSelected: (_) => setState(() => _byWeek = false),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_byWeek)
                  TextFormField(
                    controller: _week,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '当前教学周',
                      helperText:
                          '${today.year}-${today.month}-${today.day}（北京时间）是第几周？',
                      helperMaxLines: 2,
                      suffixText: '周',
                    ),
                    validator: (value) {
                      final week = int.tryParse(value?.trim() ?? '');
                      final count = int.tryParse(_count.text.trim()) ?? 0;
                      return week == null || week < 1 || week > count
                          ? '请输入 1 至学期总周数之间的周次'
                          : null;
                    },
                  )
                else
                  OutlinedButton.icon(
                    onPressed: _pickMonday,
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(
                        '第一周周一：${_firstMonday.year}-${_firstMonday.month}-${_firstMonday.day}'),
                  ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _count,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '学期总周数',
                    helperText: '含考试周；默认 20 周并非官方校历，可按实际调整。',
                    helperMaxLines: 2,
                    suffixText: '周',
                  ),
                  validator: (value) {
                    final count = int.tryParse(value?.trim() ?? '');
                    return count == null || count < 1 || count > 53
                        ? '请输入 1–53 周'
                        : null;
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存校准')),
      ],
    );
  }
}
