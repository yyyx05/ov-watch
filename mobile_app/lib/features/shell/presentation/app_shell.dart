import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../watch/application/watch_controller.dart';
import '../../watch/domain/watch_snapshot.dart';
import '../../watch/domain/watch_transport.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.controller});

  final WatchController controller;

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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, child) {
        final pages = [
          _HealthPage(controller: widget.controller),
          _HistoryPage(controller: widget.controller),
          _DevicePage(controller: widget.controller),
          _SettingsPage(controller: widget.controller),
        ];
        return Scaffold(
          body: SafeArea(
            child: IndexedStack(index: _index, children: pages),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (value) => setState(() => _index = value),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.favorite_border_rounded),
                selectedIcon: Icon(Icons.favorite_rounded),
                label: '健康',
              ),
              NavigationDestination(
                icon: Icon(Icons.insights_outlined),
                selectedIcon: Icon(Icons.insights_rounded),
                label: '趋势',
              ),
              NavigationDestination(
                icon: Icon(Icons.watch_outlined),
                selectedIcon: Icon(Icons.watch_rounded),
                label: '设备',
              ),
              NavigationDestination(
                icon: Icon(Icons.tune_outlined),
                selectedIcon: Icon(Icons.tune_rounded),
                label: '设置',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HealthPage extends StatelessWidget {
  const _HealthPage({required this.controller});

  final WatchController controller;

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
                connected:
                    controller.connectionStatus ==
                    WatchConnectionStatus.connected,
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
                const _MetricCard(
                  icon: Icons.water_drop_rounded,
                  color: Color(0xFF8A63FF),
                  label: '血氧',
                  value: '--',
                  unit: '%',
                  footnote: '当前固件暂未实现',
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
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.92,
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
  const _DailyHero({required this.snapshot, required this.connected});

  final WatchSnapshot? snapshot;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    final steps = snapshot?.steps ?? 0;
    final progress = (steps / 8000).clamp(0.0, 1.0);
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
          Row(
            children: [
              const Icon(Icons.directions_walk_rounded, color: Colors.white),
              const SizedBox(width: 8),
              const Text(
                '今日步数',
                style: TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
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
            '$steps',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 46,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          const SizedBox(height: 8),
          const Text('目标 8,000 步', style: TextStyle(color: Colors.white70)),
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
  });

  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String unit;
  final String footnote;

  @override
  Widget build(BuildContext context) {
    return Card(
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
    );
  }
}

class _HistoryPage extends StatelessWidget {
  const _HistoryPage({required this.controller});

  final WatchController controller;

  @override
  Widget build(BuildContext context) {
    final samples = controller.history
        .where((item) => item.heartRate > 0)
        .toList();
    final chartSamples = samples.length > 30
        ? samples.sublist(samples.length - 30)
        : samples;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        const Text(
          '健康趋势',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        const Text(
          '数据保存在本机，不需要云端账号',
          style: TextStyle(color: Color(0xFF7C879B)),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '心率记录',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '${samples.length} 条有效记录',
                  style: const TextStyle(color: Color(0xFF8B95A7)),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  height: 220,
                  child: chartSamples.length < 2
                      ? const _EmptyState(
                          icon: Icons.insights_rounded,
                          text: '连接手表并测量心率后显示曲线',
                        )
                      : LineChart(
                          LineChartData(
                            minY: 40,
                            maxY: 140,
                            gridData: const FlGridData(
                              show: true,
                              drawVerticalLine: false,
                            ),
                            borderData: FlBorderData(show: false),
                            titlesData: const FlTitlesData(
                              topTitles: AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              rightTitles: AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 32,
                                ),
                              ),
                            ),
                            lineBarsData: [
                              LineChartBarData(
                                isCurved: true,
                                color: AppTheme.heart,
                                barWidth: 3,
                                dotData: const FlDotData(show: false),
                                belowBarData: BarAreaData(
                                  show: true,
                                  color: AppTheme.heart.withValues(alpha: 0.10),
                                ),
                                spots: [
                                  for (var i = 0; i < chartSamples.length; i++)
                                    FlSpot(
                                      i.toDouble(),
                                      chartSamples[i].heartRate.toDouble(),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                const Icon(Icons.storage_rounded, color: AppTheme.brand),
                const SizedBox(width: 14),
                Expanded(
                  child: Text('本地已保存 ${controller.history.length} 条采样记录'),
                ),
                IconButton(
                  onPressed: controller.refreshHistory,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DevicePage extends StatelessWidget {
  const _DevicePage({required this.controller});

  final WatchController controller;

  @override
  Widget build(BuildContext context) {
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
        if (controller.devices.isEmpty && !controller.busy)
          const Card(
            child: SizedBox(
              height: 180,
              child: _EmptyState(
                icon: Icons.bluetooth_searching_rounded,
                text: '未发现已配对设备',
              ),
            ),
          ),
        for (final device in controller.devices) ...[
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
  const _SettingsPage({required this.controller});

  final WatchController controller;

  @override
  Widget build(BuildContext context) {
    final connected =
        controller.connectionStatus == WatchConnectionStatus.connected;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        const Text(
          '设备设置',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 20),
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
                enabled: connected,
                leading: const Icon(Icons.schedule_rounded),
                title: const Text('同步手机时间'),
                subtitle: const Text('发送到手表 RTC'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: controller.syncClock,
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
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
        const Text(
          '开发者日志',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Container(
          height: 270,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF151922),
            borderRadius: BorderRadius.circular(20),
          ),
          child: controller.logs.isEmpty
              ? const Center(
                  child: Text(
                    '连接后显示 TX / RX 记录',
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              : ListView.builder(
                  reverse: true,
                  itemCount: controller.logs.length,
                  itemBuilder: (context, index) {
                    final line =
                        controller.logs[controller.logs.length - 1 - index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text(
                        line,
                        style: const TextStyle(
                          color: Color(0xFFB9F6CA),
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    );
                  },
                ),
        ),
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
