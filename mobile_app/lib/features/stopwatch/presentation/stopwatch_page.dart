import 'package:flutter/material.dart';

import '../application/watch_stopwatch_controller.dart';
import '../domain/watch_companion.dart';

class StopwatchPage extends StatelessWidget {
  const StopwatchPage({super.key, required this.controller});
  final WatchStopwatchController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, child) => ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('每一段投入，都值得记录', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text('手表计时 · 手机回看', style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 24),
        _LiveStopwatch(controller: controller),
        const SizedBox(height: 16),
        const _InfoCard(
          icon: Icons.touch_app_outlined,
          text: '在手表上开始、暂停或继续秒表。暂停不会结束记录；暂停后复位，App 才会保存本次计时。为避免漏计时，运行时手表暂不进入深度休眠，耗电会增加。',
        ),
        const SizedBox(height: 24),
        StopwatchHistoryPanel(controller: controller),
      ],
    ),
  );
}

class _LiveStopwatch extends StatelessWidget {
  const _LiveStopwatch({required this.controller});
  final WatchStopwatchController controller;

  @override
  Widget build(BuildContext context) {
    final snapshot = controller.snapshot;
    final ready = controller.support == StopwatchSupport.supported;
    final status = switch (controller.support) {
      StopwatchSupport.disconnected => '手表未连接',
      StopwatchSupport.checking => '正在检测手表功能…',
      StopwatchSupport.unsupported => '当前固件未提供秒表同步',
      StopwatchSupport.failed => '暂时无法读取手表计时能力',
      StopwatchSupport.supported => switch (snapshot?.state) {
        WatchStopwatchState.run => '手表正在计时',
        WatchStopwatchState.pause => '手表已暂停',
        WatchStopwatchState.idle => '等待手表开始计时',
        null => '等待手表回传秒表',
      },
    };
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF18375D), Color(0xFF1D6F83)],
        ),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.watch_outlined, color: Colors.white70),
                const SizedBox(width: 8),
                Expanded(child: Text(controller.deviceName ?? 'OV-Watch')),
                if (controller.support == StopwatchSupport.checking)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 32),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                snapshot == null
                    ? '--:--:--'
                    : formatStopwatchDuration(snapshot.elapsedMs),
                style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              status,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              controller.updatedAt == null
                  ? (ready ? '仅显示手表真实回传，不生成模拟计时。' : '连接后可读取支持此功能的新固件。')
                  : '最近回传 ${_clock(controller.updatedAt!)} · 前台每 2 秒更新',
              style: const TextStyle(color: Colors.white70, height: 1.5),
            ),
            if (controller.support == StopwatchSupport.unsupported) ...[
              const SizedBox(height: 12),
              const Text(
                '需要升级配套手表固件。旧固件仍可同步健康数据；手机里已保存的计时历史不受影响。',
                style: TextStyle(color: Colors.white70, height: 1.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class StopwatchHistoryPanel extends StatefulWidget {
  const StopwatchHistoryPanel({super.key, required this.controller});
  final WatchStopwatchController controller;

  @override
  State<StopwatchHistoryPanel> createState() => _StopwatchHistoryPanelState();
}

class _StopwatchHistoryPanelState extends State<StopwatchHistoryPanel> {
  WatchStopwatchController get controller => widget.controller;
  int _visibleLimit = 20;
  StopwatchTag? _lastFilter;

  @override
  void initState() {
    super.initState();
    _lastFilter = controller.tagFilter;
    controller.addListener(_onFilterChanged);
  }

  @override
  void didUpdateWidget(StopwatchHistoryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == controller) return;
    oldWidget.controller.removeListener(_onFilterChanged);
    controller.addListener(_onFilterChanged);
    _lastFilter = controller.tagFilter;
    _visibleLimit = 20;
  }

  void _onFilterChanged() {
    if (_lastFilter == controller.tagFilter) return;
    setState(() {
      _lastFilter = controller.tagFilter;
      _visibleLimit = 20;
    });
  }

  @override
  void dispose() {
    controller.removeListener(_onFilterChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, child) {
      final records = controller.filteredRecords.toList(growable: false);
      final total = records.fold<int>(
        0,
        (sum, record) => sum + record.durationMs,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('计时历史', style: Theme.of(context).textTheme.titleLarge),
              TextButton.icon(
                onPressed: controller.canSyncHistory && !controller.busy
                    ? controller.syncHistory
                    : null,
                icon: const Icon(Icons.sync_rounded, size: 18),
                label: Text(controller.busy ? '同步中…' : '同步手表记录'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${records.length} 段记录 · 累计 ${formatStopwatchDuration(total)}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('全部'),
                selected: controller.tagFilter == null,
                onSelected: (_) => controller.setTagFilter(null),
              ),
              for (final tag in StopwatchTag.values)
                ChoiceChip(
                  label: Text(tag.label),
                  selected: controller.tagFilter == tag,
                  onSelected: (_) => controller.setTagFilter(tag),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (controller.errorMessage != null) ...[
            _InfoCard(
              icon: Icons.error_outline,
              text: controller.errorMessage!,
            ),
            const SizedBox(height: 12),
          ],
          if (controller.loadingHistory)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (records.isEmpty)
            const _InfoCard(
              icon: Icons.history_rounded,
              text: '这里还没有计时记录。在手表完成一段秒表计时并复位后，连接 App 同步。保存后的记录离线也能查看。',
            )
          else
            for (final record in records.take(_visibleLimit)) ...[
              _RecordTile(
                key: ValueKey(record.key),
                record: record,
                onTap: () => _showRecord(context, record),
              ),
              const SizedBox(height: 10),
            ],
          if (records.length > _visibleLimit)
            Center(
              child: TextButton(
                onPressed: () => setState(() => _visibleLimit += 20),
                child: Text('查看更多（还有 ${records.length - _visibleLimit} 条）'),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            '手表仅在本次开机内暂存最近 ${controller.capabilities?.logCapacity ?? 8} 条，'
            '重启会丢失尚未同步的记录。App 已保存记录长期保留。日期来自手表，可能尚未校准。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF697386),
              height: 1.6,
            ),
          ),
          if (controller.historySyncedAt != null) ...[
            const SizedBox(height: 8),
            Text(
              '最近同步 ${_clock(controller.historySyncedAt!)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      );
    },
  );

  Future<void> _showRecord(BuildContext context, StopwatchRecord record) =>
      showDialog<void>(
        context: context,
        builder: (context) =>
            _RecordDialog(controller: controller, record: record),
      );
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({super.key, required this.record, required this.onTap});
  final StopwatchRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: CircleAvatar(
        backgroundColor: const Color(0xFFE8F3F2),
        child: Icon(switch (record.tag) {
          StopwatchTag.exercise => Icons.directions_run_rounded,
          StopwatchTag.study => Icons.menu_book_rounded,
          StopwatchTag.other => Icons.timer_outlined,
        }, color: const Color(0xFF24756F)),
      ),
      title: Text(
        formatStopwatchDuration(record.durationMs),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      subtitle: Text(
        '${_dateTime(record.endedAt)} · ${record.tag.label}'
        '${record.note.isEmpty ? '' : '\n${record.note}'}',
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    ),
  );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: const Color(0xFF5B718A)),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(height: 1.6))),
        ],
      ),
    ),
  );
}

class _RecordDialog extends StatefulWidget {
  const _RecordDialog({required this.controller, required this.record});
  final WatchStopwatchController controller;
  final StopwatchRecord record;
  @override
  State<_RecordDialog> createState() => _RecordDialogState();
}

class _RecordDialogState extends State<_RecordDialog> {
  late final TextEditingController _note;
  late StopwatchTag _tag;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _note = TextEditingController(text: widget.record.note);
    _tag = widget.record.tag;
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('这段时间，做了什么？'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatStopwatchDuration(widget.record.durationMs),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '结束于 ${_dateTime(widget.record.endedAt)}\n'
            '来源：${widget.record.deviceName}\n${widget.record.deviceAddress}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in StopwatchTag.values)
                ChoiceChip(
                  label: Text(tag.label),
                  selected: _tag == tag,
                  onSelected: _saving
                      ? null
                      : (_) => setState(() => _tag = tag),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _note,
            enabled: !_saving,
            maxLength: 240,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: '备注',
              hintText: '例如：慢跑、阅读、专注练习',
            ),
          ),
          const Text('只编辑分类和备注，不改变手表原始计时时长。', style: TextStyle(fontSize: 12)),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? '保存中…' : '保存'),
      ),
    ],
  );

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final saved = await widget.controller.annotate(
      widget.record,
      _tag,
      _note.text,
    );
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _saving = false;
      _error = '未能保存，请重试';
    });
  }
}

String formatStopwatchDuration(int milliseconds) {
  final seconds = milliseconds ~/ 1000;
  return '${(seconds ~/ 3600).toString().padLeft(2, '0')}:'
      '${((seconds ~/ 60) % 60).toString().padLeft(2, '0')}:'
      '${(seconds % 60).toString().padLeft(2, '0')}';
}

String _clock(DateTime value) =>
    '${_two(value.hour)}:${_two(value.minute)}:${_two(value.second)}';
String _dateTime(DateTime value) =>
    '${value.year}-${_two(value.month)}-${_two(value.day)} ${_clock(value)}';
String _two(int value) => value.toString().padLeft(2, '0');
