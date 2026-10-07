import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../watch/application/watch_controller.dart';
import '../../watch/domain/watch_snapshot.dart';
import '../domain/health_summary.dart';

/// Standalone scrollable history page. No live connection is required to read
/// records already stored on this phone.
class HealthHistoryPanel extends StatefulWidget {
  const HealthHistoryPanel({
    super.key,
    required this.controller,
    this.stepGoal = 8000,
  });

  final WatchController controller;
  final int stepGoal;

  @override
  State<HealthHistoryPanel> createState() => _HealthHistoryPanelState();
}

class _HealthHistoryPanelState extends State<HealthHistoryPanel> {
  HealthMetric _metric = HealthMetric.heartRate;
  bool _loading = false;
  bool _copying = false;
  int _visibleRecords = 10;

  Future<void> _load(HistoryRange? range) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      if (range == null) {
        await widget.controller.refreshHistory();
      } else {
        await widget.controller.selectHistoryRange(range);
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _visibleRecords = 10;
        });
      }
    }
  }

  Future<void> _copyCsv(HealthSummary summary) async {
    if (_copying || summary.samples.isEmpty) return;
    setState(() => _copying = true);
    try {
      await Clipboard.setData(ClipboardData(text: summary.toCsv()));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已复制 ${summary.samples.length} 条记录，可粘贴到表格中')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('复制失败，请重试')));
    } finally {
      if (mounted) setState(() => _copying = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final controller = widget.controller;
      final end = DateTime.now();
      final summary = HealthSummary.calculate(
        samples: controller.history,
        metric: _metric,
        start: controller.historyRange.startAt(end),
        end: end,
        stepGoal: widget.stepGoal,
      );
      final recent = summary.samples.reversed.take(_visibleRecords).toList();
      return ListView(
        key: const PageStorageKey('health-history'),
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '健康历史',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              IconButton(
                tooltip: '重新读取本机记录',
                onPressed: _loading || controller.busy
                    ? null
                    : () => _load(null),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const Text('每次连接，都留下一点看得见的变化'),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final range in HistoryRange.values)
                ChoiceChip(
                  key: ValueKey('history-range-${range.name}'),
                  label: Text(range.label),
                  selected: controller.historyRange == range,
                  onSelected: _loading ? null : (_) => _load(range),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final metric in HealthMetric.values)
                ChoiceChip(
                  key: ValueKey('history-metric-${metric.name}'),
                  label: Text(metric.label),
                  avatar: Icon(_icon(metric), size: 18),
                  selected: _metric == metric,
                  onSelected: (_) => setState(() => _metric = metric),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading) ...[
            const LinearProgressIndicator(semanticsLabel: '读取历史记录'),
            const SizedBox(height: 12),
          ],
          _SummaryCards(summary: summary, stepGoal: widget.stepGoal),
          const SizedBox(height: 16),
          _TrendCard(summary: summary),
          const SizedBox(height: 16),
          const _CollectionNote(),
          const SizedBox(height: 24),
          Text('采样明细', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            '${controller.historyRange.label} · ${summary.samples.length} 条本机记录',
          ),
          const SizedBox(height: 12),
          if (recent.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('这个时间范围还没有记录。连接手表后，采样会自动保存到本机。'),
              ),
            ),
          for (final sample in recent) ...[
            _RecordCard(sample: sample, metric: _metric),
            const SizedBox(height: 8),
          ],
          if (summary.samples.length > _visibleRecords)
            TextButton.icon(
              onPressed: () => setState(() => _visibleRecords += 20),
              icon: const Icon(Icons.expand_more_rounded),
              label: const Text('查看更多记录'),
            ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            key: const ValueKey('copy-health-csv'),
            onPressed: _loading || _copying || summary.samples.isEmpty
                ? null
                : () => _copyCsv(summary),
            icon: const Icon(Icons.copy_all_rounded),
            label: Text(_copying ? '正在复制…' : '复制当前范围 CSV'),
          ),
          const SizedBox(height: 8),
          Text(
            '仅点击后复制到系统剪贴板，包含采样时间与健康数据，不含未实现的血氧值。分享前请确认接收对象。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    },
  );
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.summary, required this.stepGoal});

  final HealthSummary summary;
  final int stepGoal;

  @override
  Widget build(BuildContext context) {
    final metric = summary.metric;
    final items = metric == HealthMetric.steps
        ? [
            ('记录步数合计', '${summary.totalRecordedSteps}', '每天最高值相加 · 步'),
            ('达到当前目标', '${summary.goalDays} 天', '当前目标 $stepGoal 步/天'),
            ('有步数记录', '${summary.dailyStepMaxima.length} 天', '无记录的日期不当作 0'),
          ]
        : [
            ('采样平均', _number(summary.average), metric.unit),
            (
              '采样范围',
              summary.minimum == null
                  ? '—'
                  : '${summary.minimum}–${summary.maximum}',
              metric.unit,
            ),
            (
              '有效记录',
              '${summary.validCount}',
              metric == HealthMetric.heartRate ? '0 值不计入心率' : '固件未提供测量有效标记',
            ),
          ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final largeText = MediaQuery.textScalerOf(context).scale(14) > 20;
        final columns = largeText
            ? 1
            : constraints.maxWidth >= 600
            ? 3
            : constraints.maxWidth >= 300
            ? 2
            : 1;
        final width = (constraints.maxWidth - 8 * (columns - 1)) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.$1,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item.$2,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(color: _color(metric)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.$3,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.summary});

  final HealthSummary summary;

  @override
  Widget build(BuildContext context) {
    final points = summary.points;
    final metric = summary.metric;
    final isSteps = metric == HealthMetric.steps;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${metric.label}趋势',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(isSteps ? '按手机日期，展示当天已记录的最高步数' : '只展示采样点；密集记录按时段取均值，不填补断连空白'),
            const SizedBox(height: 20),
            if (points.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Text(
                  metric == HealthMetric.heartRate
                      ? '暂无有效心率。请在手表上开启心率测量，并保持 App 连接。'
                      : '暂无可展示的${metric.label}记录',
                ),
              )
            else if (points.length == 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_number(points.single.value)} ${metric.unit}',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text('仅有 1 个${isSteps ? '日期' : '采样点'}，尚不足以展示变化趋势'),
                  ],
                ),
              )
            else
              _PointChart(points: points, metric: metric),
            if (points.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '记录跨度：${_time(points.first.time)} — ${_time(points.last.time)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PointChart extends StatelessWidget {
  const _PointChart({required this.points, required this.metric});

  final List<HealthTrendPoint> points;
  final HealthMetric metric;

  @override
  Widget build(BuildContext context) {
    final values = points.map((point) => point.value).toList()..sort();
    final margin = ((values.last - values.first) * .2).clamp(
      1.0,
      double.infinity,
    );
    final start = points.first.time;
    final span = points.last.time.difference(start).inMilliseconds.toDouble();
    final color = _color(metric);
    return Semantics(
      label:
          '${metric.label}趋势，共 ${points.length} 个采样点，最低 ${_number(values.first)}，最高 ${_number(values.last)} ${metric.unit}。下方可阅读采样明细。',
      child: ExcludeSemantics(
        child: SizedBox(
          height: 200,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: span > 0 ? span : 1,
              minY: values.first - margin,
              maxY: values.last + margin,
              gridData: const FlGridData(drawVerticalLine: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                bottomTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 42,
                    getTitlesWidget: (value, meta) => Text(
                      _number(value),
                      style: const TextStyle(fontSize: 10),
                      textScaler: const TextScaler.linear(1),
                    ),
                  ),
                ),
              ),
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: [
                LineChartBarData(
                  color: Colors.transparent,
                  // Dots, not a continuous line: disconnected periods are
                  // missing observations rather than inferred measurements.
                  barWidth: 0,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, bar, index) =>
                        FlDotCirclePainter(
                          radius: 4,
                          color: color,
                          strokeWidth: 0,
                        ),
                  ),
                  spots: [
                    for (final point in points)
                      FlSpot(
                        point.time.difference(start).inMilliseconds.toDouble(),
                        point.value,
                      ),
                  ],
                ),
              ],
            ),
            duration: Duration.zero,
          ),
        ),
      ),
    );
  }
}

class _CollectionNote extends StatelessWidget {
  const _CollectionNote();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(
        context,
      ).colorScheme.secondaryContainer.withValues(alpha: .5),
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Text(
      '记录说明\n仅反映 App 连接并采样时的数据，不代表全天持续监测。步数每个手机日期取最高值，未连接时的变化或手表重启可能造成遗漏；达标天数按当前目标计算。温湿度是环境数据，不是体温。仅供项目观察，不能用于医疗判断。',
    ),
  );
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.sample, required this.metric});

  final WatchSnapshot sample;
  final HealthMetric metric;

  @override
  Widget build(BuildContext context) {
    final value = metric.valueOf(sample);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _time(sample.capturedAt),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '${metric.label}  ${value == null ? '未测得' : '$value ${metric.unit}'}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '手机采样时间 · 手表报告 ${_time(sample.watchTime)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

Color _color(HealthMetric metric) => switch (metric) {
  HealthMetric.heartRate => AppTheme.heart,
  HealthMetric.steps => AppTheme.steps,
  HealthMetric.temperature => const Color(0xFFAC650B),
  HealthMetric.humidity => AppTheme.environment,
};

IconData _icon(HealthMetric metric) => switch (metric) {
  HealthMetric.heartRate => Icons.favorite_outline_rounded,
  HealthMetric.steps => Icons.directions_walk_rounded,
  HealthMetric.temperature => Icons.thermostat_rounded,
  HealthMetric.humidity => Icons.water_drop_outlined,
};

String _number(double? value) => value == null
    ? '—'
    : value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);

String _time(DateTime time) {
  final local = time.toLocal();
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${pad(local.month)}/${pad(local.day)} ${pad(local.hour)}:${pad(local.minute)}';
}
