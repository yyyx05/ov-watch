import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../history/presentation/health_history_panel.dart';
import '../../settings/presentation/step_goal_dialog.dart';
import '../../stopwatch/application/watch_stopwatch_controller.dart';
import '../../stopwatch/presentation/stopwatch_page.dart';
import '../../watch/application/watch_controller.dart';
import '../../watch/domain/watch_snapshot.dart';
import '../../watch/domain/watch_transport.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.controller,
    this.stopwatchController,
  });

  final WatchController controller;
  final WatchStopwatchController? stopwatchController;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.controller.setAppActive(state == AppLifecycleState.resumed);
    widget.stopwatchController?.setAppActive(
      state == AppLifecycleState.resumed,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _selectPage(int value) {
    setState(() => _index = value);
    widget.stopwatchController?.setVisible(value == 1);
    if (value == 2) {
      widget.controller.refreshHistory();
      widget.stopwatchController?.syncHistory();
    }
    if (value == 3 &&
        widget.controller.devices.isEmpty &&
        !widget.controller.busy) {
      unawaited(widget.controller.refreshDevices());
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.controller,
        if (widget.stopwatchController != null) widget.stopwatchController!,
      ]),
      builder: (context, child) {
        final pages = [
          _HealthPage(
            controller: widget.controller,
            stopwatchController: widget.stopwatchController,
            onViewStopwatch: () => _selectPage(1),
          ),
          if (widget.stopwatchController != null)
            StopwatchPage(controller: widget.stopwatchController!)
          else
            const _EmptyState(icon: Icons.timer_outlined, text: '计时模块未初始化'),
          _HistoryPage(
            controller: widget.controller,
            stopwatchController: widget.stopwatchController,
          ),
          _DevicePage(controller: widget.controller),
          _SettingsPage(
            controller: widget.controller,
            stopwatchController: widget.stopwatchController,
          ),
        ];
        return Scaffold(
          body: SafeArea(
            child: IndexedStack(index: _index, children: pages),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _selectPage,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.favorite_border_rounded),
                selectedIcon: Icon(Icons.favorite_rounded),
                label: '健康',
              ),
              NavigationDestination(
                icon: Icon(Icons.timer_outlined),
                selectedIcon: Icon(Icons.timer_rounded),
                label: '计时',
              ),
              NavigationDestination(
                icon: Icon(Icons.insights_outlined),
                selectedIcon: Icon(Icons.insights_rounded),
                label: '历史',
              ),
              NavigationDestination(
                icon: Icon(Icons.watch_outlined),
                selectedIcon: Icon(Icons.watch_rounded),
                label: '设备',
              ),
              NavigationDestination(
                icon: Icon(Icons.tune_outlined),
                selectedIcon: Icon(Icons.tune_rounded),
                label: '我的',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HealthPage extends StatelessWidget {
  const _HealthPage({
    required this.controller,
    this.stopwatchController,
    required this.onViewStopwatch,
  });

  final WatchController controller;
  final WatchStopwatchController? stopwatchController;
  final VoidCallback onViewStopwatch;

  @override
  Widget build(BuildContext context) {
    final snapshot = controller.latest;
    return RefreshIndicator(
      onRefresh: controller.requestNow,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            sliver: SliverToBoxAdapter(child: _Header(controller: controller)),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            sliver: SliverToBoxAdapter(
              child: _DailyHero(
                snapshot: snapshot,
                stepGoal: controller.stepGoal,
                connected:
                    controller.connectionStatus ==
                    WatchConnectionStatus.connected,
              ),
            ),
          ),
          if (snapshot != null &&
              controller.connectionStatus != WatchConnectionStatus.connected)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Text(
                  '离线查看 · 以下为 ${_dateTime(snapshot.capturedAt)} 保存的数据，非当前测量',
                  style: const TextStyle(color: Color(0xFF7C879B)),
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            sliver: SliverGrid(
              delegate: SliverChildListDelegate.fixed([
                _MetricCard(
                  icon: Icons.favorite_rounded,
                  color: AppTheme.heart,
                  label: '心率',
                  value: snapshot == null || snapshot.heartRate == 0
                      ? '--'
                      : '${snapshot.heartRate}',
                  unit: '次/分',
                  footnote: '仅在手表测量心率时更新',
                ),
                _MetricCard(
                  icon: Icons.timer_rounded,
                  color: const Color(0xFF8A63FF),
                  label: '计时记录',
                  value: '${stopwatchController?.records.length ?? 0}',
                  unit: '段',
                  footnote: '点击查看已保存的计时',
                  onTap: onViewStopwatch,
                ),
                _MetricCard(
                  icon: Icons.thermostat_rounded,
                  color: const Color(0xFFFF9B50),
                  label: '环境温度',
                  value: snapshot == null ? '--' : '${snapshot.temperature}',
                  unit: '°C',
                  footnote: 'AHT21 环境传感器',
                ),
                _MetricCard(
                  icon: Icons.water_drop_outlined,
                  color: AppTheme.environment,
                  label: '环境湿度',
                  value: snapshot == null ? '--' : '${snapshot.humidity}',
                  unit: '%',
                  footnote: 'AHT21 环境传感器',
                ),
              ]),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount:
                    MediaQuery.sizeOf(context).width < 350 ||
                        MediaQuery.textScalerOf(context).scale(14) > 20
                    ? 1
                    : 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                mainAxisExtent:
                    220 *
                    (MediaQuery.textScalerOf(context).scale(14) / 14).clamp(
                      1.0,
                      2.5,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final WatchController controller;

  @override
  Widget build(BuildContext context) {
    final status = controller.connectionStatus;
    final connected = status == WatchConnectionStatus.connected;
    final statusColor = switch (status) {
      WatchConnectionStatus.connected => AppTheme.environment,
      WatchConnectionStatus.connecting ||
      WatchConnectionStatus.reconnecting => const Color(0xFFFF9B50),
      WatchConnectionStatus.failed => AppTheme.heart,
      WatchConnectionStatus.disconnected => const Color(0xFF9AA3B2),
    };
    final statusLabel = switch (status) {
      WatchConnectionStatus.connected => '已连接',
      WatchConnectionStatus.connecting => '连接中',
      WatchConnectionStatus.reconnecting => '重连中',
      WatchConnectionStatus.failed => '连接失败',
      WatchConnectionStatus.disconnected => '未连接',
    };
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'OV Health',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 2),
              Text('今天也要保持活力', style: TextStyle(color: Color(0xFF7C879B))),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: connected
                ? const Color(0xFFE8F8F1)
                : const Color(0xFFF0F2F6),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                statusLabel,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DailyHero extends StatelessWidget {
  const _DailyHero({
    required this.snapshot,
    required this.connected,
    required this.stepGoal,
  });

  final WatchSnapshot? snapshot;
  final bool connected;
  final int stepGoal;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final captured = snapshot?.capturedAt;
    final today =
        captured != null &&
        captured.year == now.year &&
        captured.month == now.month &&
        captured.day == now.day;
    final steps = today ? snapshot!.steps : 0;
    final progress = (steps / stepGoal).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2D6BFF), Color(0xFF6B8CFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x332D6BFF),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.spaceBetween,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.directions_walk_rounded, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    '今日步数',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Text(
                snapshot == null
                    ? (connected ? '等待数据' : '连接手表后同步')
                    : _clock(snapshot!.capturedAt),
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            today ? '$steps' : '--',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 46,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '目标 $stepGoal 步 · ${today ? (progress * 100).round() : 0}%',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 9,
              color: Colors.white,
              backgroundColor: Colors.white24,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.unit,
    required this.footnote,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String unit;
  final String footnote;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: color),
              ),
              const Spacer(),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF707B8F),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      unit,
                      style: const TextStyle(
                        color: Color(0xFF7C879B),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                footnote,
                maxLines: 2,
                style: const TextStyle(color: Color(0xFF9AA3B2), fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryPage extends StatelessWidget {
  const _HistoryPage({required this.controller, this.stopwatchController});

  final WatchController controller;
  final WatchStopwatchController? stopwatchController;

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Column(
      children: [
        const TabBar(
          tabs: [
            Tab(text: '健康数据'),
            Tab(text: '计时记录'),
          ],
        ),
        Expanded(
          child: TabBarView(
            children: [
              HealthHistoryPanel(
                controller: controller,
                stepGoal: controller.stepGoal,
              ),
              if (stopwatchController != null)
                SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: StopwatchHistoryPanel(
                    controller: stopwatchController!,
                  ),
                )
              else
                const _EmptyState(icon: Icons.timer_outlined, text: '暂无计时记录'),
            ],
          ),
        ),
      ],
    ),
  );
}

class _DevicePage extends StatefulWidget {
  const _DevicePage({required this.controller});

  final WatchController controller;

  @override
  State<_DevicePage> createState() => _DevicePageState();
}

class _DevicePageState extends State<_DevicePage> {
  bool _showAll = false;
  WatchController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final devices = controller.devices.where((device) {
      final name = device.name.toLowerCase();
      return _showAll ||
          name.contains('kt6368') ||
          name.contains('ov-watch') ||
          device.address == controller.preferredDevice?.address ||
          device.address == controller.connectedDevice?.address;
    }).toList();
    devices.sort((a, b) {
      final address = controller.preferredDevice?.address;
      if (a.address == b.address) return 0;
      if (a.address == address) return -1;
      if (b.address == address) return 1;
      return a.name.compareTo(b.name);
    });
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '我的设备',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
              ),
            ),
            IconButton(
              onPressed: controller.busy ? null : controller.refreshDevices,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          '请先在 Android 系统设置中配对 KT6368',
          style: TextStyle(color: Color(0xFF7C879B)),
        ),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('显示其他已配对设备'),
          subtitle: const Text('默认只展示手表，避免误连耳机等设备'),
          value: _showAll,
          onChanged: (value) => setState(() => _showAll = value),
        ),
        if (controller.preferredDevice != null)
          Text(
            '常用手表 · ${controller.preferredDevice!.name}\n${controller.preferredDevice!.address}',
            style: const TextStyle(color: Color(0xFF7C879B)),
          ),
        const SizedBox(height: 20),
        if (controller.errorMessage != null)
          _ErrorBanner(
            message: controller.errorMessage!,
            actionLabel: controller.errorCanOpenSettings ? '打开设置' : null,
            onAction: controller.errorCanOpenSettings
                ? controller.openAppSettings
                : null,
          ),
        if (controller.busy)
          const LinearProgressIndicator(
            borderRadius: BorderRadius.all(Radius.circular(999)),
          ),
        const SizedBox(height: 12),
        if (devices.isEmpty && !controller.busy)
          const Card(
            child: SizedBox(
              height: 180,
              child: _EmptyState(
                icon: Icons.bluetooth_searching_rounded,
                text: '未发现匹配的已配对手表\n可开启“显示其他已配对设备”',
              ),
            ),
          ),
        for (final device in devices) ...[
          _DeviceCard(device: device, controller: controller),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device, required this.controller});

  final WatchDevice device;
  final WatchController controller;

  @override
  Widget build(BuildContext context) {
    final selected = controller.connectedDevice?.address == device.address;
    final connected =
        selected &&
        controller.connectionStatus == WatchConnectionStatus.connected;
    final transitioning =
        selected &&
        (controller.connectionStatus == WatchConnectionStatus.connecting ||
            controller.connectionStatus == WatchConnectionStatus.reconnecting);
    final failed =
        selected && controller.connectionStatus == WatchConnectionStatus.failed;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppTheme.brand.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.watch_rounded, color: AppTheme.brand),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name.isEmpty ? '未命名蓝牙设备' : device.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    device.address,
                    style: const TextStyle(
                      color: Color(0xFF8B95A7),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.tonal(
              onPressed: controller.busy
                  ? null
                  : connected || transitioning
                  ? controller.disconnect
                  : () => controller.connect(device),
              child: Text(
                connected
                    ? '断开'
                    : transitioning
                    ? '停止'
                    : failed
                    ? '重试'
                    : '连接',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({required this.controller, this.stopwatchController});

  final WatchController controller;
  final WatchStopwatchController? stopwatchController;

  @override
  Widget build(BuildContext context) {
    final connected =
        controller.connectionStatus == WatchConnectionStatus.connected;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        const Text(
          '我的与设置',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 20),
        Card(
          child: ListTile(
            leading: const Icon(Icons.flag_outlined),
            title: const Text('每日步数目标'),
            subtitle: Text('${controller.stepGoal} 步 · 根据自己的日常安排设置'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => showDialog<void>(
              context: context,
              builder: (_) => StepGoalDialog(
                initialGoal: controller.stepGoal,
                onSave: controller.updateStepGoal,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Column(
            children: [
              SwitchListTile(
                value: controller.autoRefresh,
                onChanged: controller.setAutoRefresh,
                secondary: const Icon(Icons.sync_rounded),
                title: const Text('自动刷新'),
                subtitle: const Text('连接期间每 2 秒读取一次当前数据'),
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                enabled:
                    connected &&
                    controller.clockSyncStatus != ClockSyncStatus.syncing,
                leading: const Icon(Icons.schedule_rounded),
                title: Text(
                  controller.clockSyncStatus == ClockSyncStatus.syncing
                      ? '正在同步时间…'
                      : '同步手机时间',
                ),
                subtitle: Semantics(
                  liveRegion: true,
                  child: Text(
                    controller.clockSyncMessage ?? '请先在手表“日期时间”中开启“同步APP”',
                  ),
                ),
                trailing: switch (controller.clockSyncStatus) {
                  ClockSyncStatus.syncing => const SizedBox.square(
                    dimension: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      semanticsLabel: '等待手表确认校时',
                    ),
                  ),
                  ClockSyncStatus.succeeded => const Icon(
                    Icons.check_circle_outline_rounded,
                  ),
                  ClockSyncStatus.failed => const Icon(
                    Icons.error_outline_rounded,
                  ),
                  ClockSyncStatus.idle => const Icon(
                    Icons.chevron_right_rounded,
                  ),
                },
                onTap:
                    connected &&
                        controller.clockSyncStatus != ClockSyncStatus.syncing
                    ? controller.syncClock
                    : null,
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              if (stopwatchController != null) ...[
                ListTile(
                  leading: const Icon(Icons.fact_check_outlined),
                  title: const Text('手表校时开关'),
                  subtitle: Text(
                    !connected
                        ? '连接手表后可查询；旧固件可能不支持'
                        : stopwatchController!.capabilities == null
                        ? '当前固件未返回开关状态，请在手表上检查“同步APP”'
                        : '上次查询：${stopwatchController!.capabilities!.clockSyncEnabled ? "已开启" : "未开启，请先在手表上开启"}',
                  ),
                  trailing: IconButton(
                    tooltip: '重新查询手表功能与校时开关',
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: connected && !stopwatchController!.busy
                        ? stopwatchController!.refreshCapabilities
                        : null,
                  ),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
              ],
              const ListTile(
                leading: Icon(Icons.bluetooth_connected_rounded),
                title: Text('自动重连'),
                subtitle: Text('连接中断后指数退避重试，最多 5 次'),
                trailing: Chip(label: Text('已开启')),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _DiagnosticsCard(controller: controller),
        const SizedBox(height: 16),
        const Card(
          child: ListTile(
            leading: Icon(Icons.system_update_alt_rounded),
            title: Text('固件升级'),
            subtitle: Text('计划功能：完成连接稳定性验证后接入 YModem OTA'),
            trailing: Chip(label: Text('后续')),
          ),
        ),
      ],
    );
  }
}

class _DiagnosticsCard extends StatelessWidget {
  const _DiagnosticsCard({required this.controller});
  final WatchController controller;

  @override
  Widget build(BuildContext context) {
    final snapshot = controller.latest;
    final device = controller.connectedDevice ?? controller.preferredDevice;
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.troubleshoot_rounded),
        title: const Text('连接诊断与日志'),
        subtitle: Text(
          snapshot == null
              ? '尚未收到测量数据'
              : '最近采样 ${_dateTime(snapshot.capturedAt)}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              [
                if (device != null) '设备：${device.name} · ${device.address}',
                '连接采样间隔：${controller.pollInterval.inSeconds} 秒',
                '历史保存间隔：${controller.historyPersistInterval.inSeconds} 秒',
                if (snapshot != null)
                  '回包中的手表时间：${_dateTime(snapshot.watchTime)}',
                if (snapshot != null)
                  '接收时手机时间：${_dateTime(snapshot.capturedAt)}',
                '断开期间不补采健康数据；离线缓存不是实时值。',
                '血氧测量尚未实现，固件默认值 99 不作为真实数据展示。',
                '若校时无变化，先检查手表“日期时间 → 同步APP”。',
              ].join('\n'),
            ),
          ),
          const SizedBox(height: 12),
          if (controller.errorMessage != null)
            _ErrorBanner(message: controller.errorMessage!),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.copy_rounded),
              label: const Text('复制诊断日志'),
              onPressed: controller.logs.isEmpty
                  ? null
                  : () async {
                      await Clipboard.setData(
                        ClipboardData(text: controller.logs.join('\n')),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('日志已复制；分享前请检查设备地址等信息')),
                        );
                      }
                    },
            ),
          ),
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF151922),
              borderRadius: BorderRadius.circular(16),
            ),
            child: SingleChildScrollView(
              reverse: true,
              child: SelectableText(
                controller.logs.isEmpty
                    ? '连接后显示 TX / RX 记录'
                    : controller.logs.join('\n'),
                style: const TextStyle(
                  color: Color(0xFFB9F6CA),
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: const Color(0xFFB0B8C6)),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF8B95A7)),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, this.actionLabel, this.onAction});

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0F1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppTheme.heart),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFF9F2438)),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: 8),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

String _clock(DateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '更新于 $hour:$minute';
}

String _dateTime(DateTime time) =>
    '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} '
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
