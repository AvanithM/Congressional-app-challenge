// (USER+AI)
import 'package:flutter/material.dart';
import 'package:congress_app/services/api.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key, this.api, this.refreshTrigger = 0});

  final Api? api;
  final int refreshTrigger;

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  List<Map<String, dynamic>> _records = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void didUpdateWidget(covariant ProgressScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTrigger != widget.refreshTrigger) {
      _refreshHistory();
    }
  }

  void _refreshHistory() {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final records = await (widget.api ?? Api.forCurrentPlatform())
          .getProgressHistory();
      if (!mounted) return;
      setState(() {
        _records = records;
        _error = null;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  Map<String, int> _emotionCounts() {
    final counts = <String, int>{};
    for (final record in _records) {
      final emotions = record['emotions'];
      if (emotions is! List) continue;
      for (final emotion in emotions.whereType<String>()) {
        final label = emotion.trim();
        if (label.isNotEmpty) {
          counts[label] = (counts[label] ?? 0) + 1;
        }
      }
    }
    return counts;
  }

  Map<String, int> _dangerCounts() {
    final counts = <String, int>{'none': 0, 'concerning': 0, 'urgent': 0};
    for (final record in _records) {
      final level = record['danger_level'];
      if (level is String && counts.containsKey(level)) {
        counts[level] = counts[level]! + 1;
      }
    }
    return counts;
  }

  DateTime _weekStart(DateTime timestamp, int offsetMinutes) {
    final localDate = timestamp.toUtc().add(Duration(minutes: offsetMinutes));
    final date = DateTime.utc(localDate.year, localDate.month, localDate.day);
    return date.subtract(Duration(days: date.weekday % 7));
  }

  DateTime _currentWeekStart() {
    final now = DateTime.now();
    return _weekStart(now, now.timeZoneOffset.inMinutes);
  }

  List<_TrendSeries> _emotionTrends() {
    final currentWeek = _currentWeekStart();
    final weeks = List<DateTime>.generate(
      4,
      (index) => currentWeek.subtract(Duration(days: (3 - index) * 7)),
    );
    final countsByWeek = <DateTime, Map<String, int>>{
      for (final week in weeks) week: <String, int>{},
    };

    for (final record in _records) {
      final timestampValue = record['timestamp'];
      final timestamp = timestampValue is String
          ? DateTime.tryParse(timestampValue)
          : null;
      if (timestamp == null) continue;

      final offset = record['timezone_offset_minutes'];
      final offsetMinutes = offset is int ? offset : 0;
      final week = _weekStart(timestamp, offsetMinutes);
      final weekCounts = countsByWeek[week];
      final emotions = record['emotions'];
      if (weekCounts == null || emotions is! List) continue;

      for (final emotion in emotions.whereType<String>()) {
        final label = emotion.trim();
        if (label.isNotEmpty) {
          weekCounts[label] = (weekCounts[label] ?? 0) + 1;
        }
      }
    }

    final emotionNames =
        countsByWeek.values.expand((counts) => counts.keys).toSet().toList()
          ..sort();

    return [
      for (var index = 0; index < emotionNames.length; index++)
        _TrendSeries(
          label: emotionNames[index],
          color: _chartColors[index % _chartColors.length],
          values: [
            for (final week in weeks)
              countsByWeek[week]![emotionNames[index]] ?? 0,
          ],
        ),
    ];
  }

  String _weekLabel(DateTime weekStart) {
    final month = const [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ][weekStart.month - 1];
    return '$month ${weekStart.day}';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Could not load progress: $_error'),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _refreshHistory,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final emotions = _emotionCounts();
    final dangerLevels = _dangerCounts();
    final trends = _emotionTrends();
    final currentWeek = _currentWeekStart();

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.summarize_outlined),
            title: const Text('Weekly progress report'),
            subtitle: Text(
              DateTime.now().weekday == DateTime.sunday
                  ? 'Sunday report preview · ${_records.length} check-ins recorded.'
                  : 'Your progress is available anytime · '
                        '${_records.length} check-ins recorded.',
            ),
          ),
        ),
        _CountBars(title: 'Emotion labels', counts: emotions),
        _CountBars(
          title: 'Danger classifications',
          counts: dangerLevels,
          barColors: const [
            Color(0xFF4C8C4A),
            Color(0xFFE3A008),
            Color(0xFFB3261E),
          ],
        ),
        _TrendCard(
          series: trends,
          weekLabels: [
            for (var index = 3; index >= 0; index--)
              _weekLabel(currentWeek.subtract(Duration(days: index * 7))),
          ],
        ),
        if (_records.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'No check-in history yet. Your charts will fill in as you check in.',
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

const _chartColors = [
  Color(0xFF3659A2),
  Color(0xFF2E7D32),
  Color(0xFFB45309),
  Color(0xFF8E44AD),
  Color(0xFF00838F),
  Color(0xFFC2185B),
  Color(0xFF5D4037),
  Color(0xFF455A64),
];

class _CountBars extends StatelessWidget {
  const _CountBars({required this.title, required this.counts, this.barColors});

  final String title;
  final Map<String, int> counts;
  final List<Color>? barColors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maximum = counts.values.fold<int>(
      0,
      (currentMax, count) => count > currentMax ? count : currentMax,
    );
    final entries = counts.entries.toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            if (counts.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('No data yet.'),
              )
            else
              for (var index = 0; index < entries.length; index++)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      SizedBox(width: 90, child: Text(entries[index].key)),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: maximum == 0
                              ? 0
                              : entries[index].value / maximum,
                          minHeight: 12,
                          color: barColors == null || barColors!.isEmpty
                              ? null
                              : barColors![index % barColors!.length],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${entries[index].value}'),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _TrendSeries {
  const _TrendSeries({
    required this.label,
    required this.color,
    required this.values,
  });

  final String label;
  final Color color;
  final List<int> values;
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.series, required this.weekLabels});

  final List<_TrendSeries> series;
  final List<String> weekLabels;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Weekly emotion trends',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text('Each line shows the weekly count for one emotion.'),
            const SizedBox(height: 16),
            if (series.isEmpty)
              const Center(child: Text('No dated emotion data yet.'))
            else ...[
              SizedBox(
                height: 180,
                width: double.infinity,
                child: CustomPaint(
                  painter: _LineChartPainter(series),
                  child: const SizedBox.expand(),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  for (final label in weekLabels)
                    Text(label, style: Theme.of(context).textTheme.labelSmall),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  for (final item in series)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: item.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          item.label,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  const _LineChartPainter(this.series);

  final List<_TrendSeries> series;

  @override
  void paint(Canvas canvas, Size size) {
    const padding = 12.0;
    final chartWidth = size.width - padding * 2;
    final chartHeight = size.height - padding * 2;
    final maxValue = series
        .expand((item) => item.values)
        .fold<int>(1, (maximum, value) => value > maximum ? value : maximum);
    final gridPaint = Paint()
      ..color = const Color(0x33222222)
      ..strokeWidth = 1;

    for (var row = 0; row <= 4; row++) {
      final y = padding + chartHeight * row / 4;
      canvas.drawLine(
        Offset(padding, y),
        Offset(size.width - padding, y),
        gridPaint,
      );
    }

    for (final item in series) {
      if (item.values.isEmpty) continue;
      final points = <Offset>[
        for (var index = 0; index < item.values.length; index++)
          Offset(
            item.values.length == 1
                ? padding + chartWidth / 2
                : padding + chartWidth * index / (item.values.length - 1),
            padding + chartHeight * (1 - item.values[index] / maxValue),
          ),
      ];

      final linePaint = Paint()
        ..color = item.color
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, linePaint);

      final pointPaint = Paint()..color = item.color;
      for (final point in points) {
        canvas.drawCircle(point, 4, pointPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
      oldDelegate.series != series;
}
