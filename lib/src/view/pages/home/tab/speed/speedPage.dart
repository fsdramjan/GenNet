import 'package:apptrack/src/service/configs/appColors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:apptrack/src/controller/allController.dart';
import 'dart:math' as math;
import 'package:apptrack/src/service/network/networkService.dart';
import 'package:apptrack/src/service/network/wifiInfoModel.dart';
import 'package:apptrack/src/service/wifi/wifiService.dart';
import 'package:apptrack/src/view/pages/home/tab/speed/widgets/diagnosticReportButton.dart';
import 'package:apptrack/src/view/pages/home/tab/speed/widgets/diagnosticReportSheet.dart';
import 'package:get/get.dart';

class SpeedPage extends StatefulWidget {
  const SpeedPage({Key? key}) : super(key: key);

  @override
  State<SpeedPage> createState() => _SpeedPageState();
}

class _SpeedPageState extends State<SpeedPage> {
  final _svc = NetworkService.instance;
  final _nameCtrl = TextEditingController();
  final _hostCtrl = TextEditingController();
  bool _editMode = false;

  @override
  void initState() {
    super.initState();
    _svc.init();
  }

  @override
  void dispose() {
    _svc.dispose();
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    super.dispose();
  }

  bool _done = false;
  double _progress = 0;
  String _step = 'Build a report you can send to your ISP';
  bool isLoading = false;

  // 'Scanning active traffic' স্টেপ ইচ্ছাকৃতভাবে এখানে নেই — ওই কাজটা
  // ভারী (২৫৪-IP scan হতে পারে), তাই এটা বাটনের progress loop থেকে
  // সরিয়ে DiagnosticReportSheet ওপেন হওয়ার পরে ব্যাকগ্রাউন্ডে চালানো হয়।
  // ফলে বাটন দ্রুত/smooth থাকে আর শিট সাথে সাথে খোলে।
  static const _steps = [
    'Pinging gateway',
    'Resolving DNS',
    'Testing reachability',
    'Scanning channels',
  ];

  Future<void> _run() async {
    if (!mounted) return;
    setState(() => isLoading = true);

    final svc = NetworkService.instance;
    for (var i = 0; i < _steps.length; i++) {
      if (!mounted) return;
      setState(() {
        _step = _steps[i];
        _progress = i / _steps.length;
      });

      if (i == 0) await svc.pingAllTargets();
      if (i == 1) await svc.refreshWifiInfo();
      if (i == 3) await wifiC.scanRealChannelOverlap();
    }

    if (!mounted) return;
    setState(() {
      _progress = 1;
      _done = true;
      isLoading = false;
    });

    // Diagnostic Report শিট এখন খুলবে — active traffic scan এই শিটের
    // ভেতরেই initState()-এ ব্যাকগ্রাউন্ডে চলবে (loadTrafficOnce())।
    if (_done && mounted) {
      DiagnosticReportSheet.show(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F1013),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: _buildMockAppBar(),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _svc.refreshWifiInfo();
          await _svc.pingAllTargets();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            child: ValueListenableBuilder<WifiInfoModel?>(
              valueListenable: _svc.wifiInfo,
              builder: (context, info, _) {
                if (info == null) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 80),
                    child: Center(
                        child:
                            CircularProgressIndicator(color: Colors.white38)),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildNetworkFlowDiagram(info),
                    const SizedBox(height: 24),
                    _buildSignalStatusCard(info),
                    const SizedBox(height: 16),
                    DiagnosticReportButton(
                      onTap: () async {
                        await _run();
                      },
                      step: _step,
                      progress: _progress,
                      isDone: _done,
                      isLoading: isLoading,
                    ),
                    const SizedBox(height: 16),
                    _buildDistanceCard(info),
                    const SizedBox(height: 24),
                    _buildSectionHeader(
                        'Live Ping', true, _editMode ? 'Done' : 'Edit', () {
                      setState(() => _editMode = !_editMode);
                    }),
                    const SizedBox(height: 12),
                    _buildLivePingGrid(),
                    const SizedBox(height: 12),
                    _buildPingInputs(),
                    const SizedBox(height: 24),
                    _buildSectionHeader('Network Details', false, 'Copy',
                        () => _copyDetails(info)),
                    const SizedBox(height: 12),
                    _buildNetworkDetailsCard(info),
                    const SizedBox(height: 32),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // --- App Bar ---
  Widget _buildMockAppBar() {
    return ValueListenableBuilder<WifiInfoModel?>(
      valueListenable: _svc.wifiInfo,
      builder: (context, info, _) {
        return AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: (info?.ssid != null)
                      ? const Color(0xFF4CAF50)
                      : const Color(0xFFF2A900),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                info?.ssid ?? 'Not connected',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
            ],
          ),
          actions: [
            ElevatedButton.icon(
              onPressed: () async {
                final result = await WifiService.toggleWifi();

                debugPrint('WiFi result: $result');
              },
              style: ButtonStyle(
                backgroundColor:
                    MaterialStateProperty.all(AppColors.white.withOpacity(.14)),
              ),
              icon: const Icon(Icons.wifi, color: Colors.white),
              label: const Text('WiFi ON / OFF',
                  style: TextStyle(color: Colors.white)),
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined, color: Colors.grey),
              onPressed: () {
                _svc.refreshWifiInfo();
                _svc.pingAllTargets();
              },
            )
          ],
        );
      },
    );
  }

  // --- 1. Network Flow Diagram ---
  Widget _buildNetworkFlowDiagram(WifiInfoModel info) {
    final available = _svc.gatewayReachable.value;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildFlowItem(
          Icons.public,
          info.ispName ?? 'Network',
          info.publicIp ?? '--',
          available == null
              ? 'Checking…'
              : (available ? 'Available' : 'Unreachable'),
          available == false
              ? const Color(0xFFE53935)
              : const Color(0xFF4CAF50),
        ),
        const Icon(Icons.chevron_right, color: Color(0xFF4CAF50), size: 20),
        _buildFlowItem(
            Icons.router, 'Access Point', info.bssid ?? '--', null, null),
        const Icon(Icons.chevron_right, color: Color(0xFF4CAF50), size: 20),
        _buildFlowItem(Icons.smartphone, info.deviceName ?? 'This phone',
            info.ipAddress ?? '--', null, null),
      ],
    );
  }

  Widget _buildFlowItem(IconData icon, String title, String subtitle,
      String? status, Color? statusColor) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 36),
          const SizedBox(height: 8),
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
          const SizedBox(height: 2),
          Text(subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 11)),
          if (status != null) ...[
            const SizedBox(height: 2),
            Text(status, style: TextStyle(color: statusColor, fontSize: 11)),
          ]
        ],
      ),
    );
  }

  // --- 2. Signal Status Card ---
  Widget _buildSignalStatusCard(WifiInfoModel info) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B1D),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4A3A23), width: 1),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B2D1D),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.priority_high,
                    color: Color(0xFFE69A3A), size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_svc.diagnosisTitle(info),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(_svc.diagnosisSubtitle(),
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 12)),
                  ],
                ),
              )
            ],
          ),
          const SizedBox(height: 16),
          const Divider(color: Color(0xFF333333), height: 1),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildSignalStat(
                  'Signal', info.rssi != null ? '${info.rssi} dBm' : '--'),
              _buildSignalStat(
                  'Link speed',
                  info.linkSpeedMbps != null
                      ? '${info.linkSpeedMbps} Mbps'
                      : '--'),
              _buildSignalStat(
                  'Channel',
                  info.channel != null
                      ? '${info.channel}${info.channelWidthMhz != null ? ' · ${info.channelWidthMhz} MHz' : ''}'
                      : '--'),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildSignalStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(color: Color(0xFF888888), fontSize: 11)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14)),
      ],
    );
  }

  // --- 4. Distance Card ---
  Widget _buildDistanceCard(WifiInfoModel info) {
    final gwHistory = _svc.targets.value
        .firstWhere((t) => t.label == 'Router gateway',
            orElse: () => PingTarget(label: '', host: ''))
        .history;
    final lastGw = gwHistory.isNotEmpty ? gwHistory.last : null;
    final gwMs = lastGw != null && lastGw['success'] == true
        ? (lastGw['avgMs'] as num?)?.round()
        : null;
    final dist = info.estimatedDistanceMeters;

    // Map distance (m) to a pixel radius using the same anchor points the
    // radar rings are drawn at in RadarPainter (5m=45px, 15m=90px, 30m=140px
    // from the center, which itself sits 20px above the stack's bottom edge).
    double lerp(double x0, double x1, double y0, double y1, double x) =>
        y0 + (y1 - y0) * (x - x0) / (x1 - x0);
    double radiusForDistance(double? meters) {
      if (meters == null) return 50; // neutral resting spot while data loads
      final m = meters.clamp(0, 500).toDouble();
      if (m <= 5) return lerp(0, 5, 0, 45, m);
      if (m <= 15) return lerp(5, 15, 45, 90, m);
      if (m <= 30) return lerp(15, 30, 90, 140, m);
      return 145; // cap just past the outer 30m ring so the icon stays on screen
    }

    final radius = radiusForDistance(dist);
    final lineBottom = 44.0;
    // Lower bound must stay above lineBottom, or the dotBottom clamp below
    // (lineBottom, phoneBottom) would get an inverted range and throw.
    final phoneBottom = (20 + radius).clamp(lineBottom + 6, 165.0);
    final lineHeight = (phoneBottom - lineBottom).clamp(6.0, 200.0);
    final dotBottom = (phoneBottom - 20).clamp(lineBottom, phoneBottom);

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B1D),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Distance from router',
                    style: TextStyle(color: Colors.grey, fontSize: 13)),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF223555),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                      gwMs != null ? 'Round trip $gwMs ms' : 'Round trip --',
                      style: const TextStyle(
                          color: Color(0xFF6B9CFA), fontSize: 11)),
                )
              ],
            ),
          ),
          SizedBox(
            height: 180,
            width: double.infinity,
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                CustomPaint(
                    size: const Size(double.infinity, 180),
                    painter: RadarPainter()),
                Positioned(
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: const Color(0xFF2C2C2E),
                        borderRadius: BorderRadius.circular(12)),
                    child:
                        const Icon(Icons.router, color: Colors.white, size: 20),
                  ),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOut,
                  bottom: phoneBottom,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B1B1D),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: const Color(0xFFE69A3A), width: 2),
                    ),
                    child: const Icon(Icons.smartphone,
                        color: Colors.purpleAccent, size: 20),
                  ),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOut,
                  bottom: lineBottom,
                  child: Container(
                      width: 2,
                      height: lineHeight,
                      color: const Color(0xFFE69A3A)),
                ),
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOut,
                  bottom: dotBottom,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                        color: Color(0xFFE69A3A), shape: BoxShape.circle),
                  ),
                )
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(dist != null ? '${dist.toStringAsFixed(0)} m' : '--',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6.0),
                      child: Text(
                          info.rssi != null ? '·  ${info.rssi} dBm' : '',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 13)),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: const Color(0xFF3B2D1D),
                          borderRadius: BorderRadius.circular(4)),
                      child: Text(info.signalQualityLabel,
                          style: const TextStyle(
                              color: Color(0xFFE69A3A),
                              fontSize: 11,
                              fontWeight: FontWeight.bold)),
                    )
                  ],
                ),
                const SizedBox(height: 4),
                Text(info.signalQualityDesc,
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _svc.gatewayReachable.value == false
                            ? const Color(0xFFE53935)
                            : const Color(0xFF4CAF50),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Gateway',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 13)),
                      ],
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${info.gatewayIp ?? '--'} · ${_svc.gatewayReachable.value == false ? 'unreachable' : 'responding'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            const TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                    ),
                    Text(gwMs != null ? '$gwMs ms' : '--',
                        style: const TextStyle(
                            color: Color(0xFF4CAF50),
                            fontWeight: FontWeight.bold,
                            fontSize: 13)),
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  // --- Headers ---
  Widget _buildSectionHeader(
      String title, bool showDot, String actionText, VoidCallback onTap) {
    return Row(
      children: [
        Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
        if (showDot) ...[
          const SizedBox(width: 8),
          ValueListenableBuilder<bool>(
            valueListenable: _svc.isPinging,
            builder: (context, busy, _) {
              return TweenAnimationBuilder<double>(
                // পিং চললে স্কেল বড়-ছোট হবে (Live feel), না চললে স্থির থাকবে
                tween: Tween(begin: 0.6, end: busy ? 1.2 : 0.8),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeInOut,
                builder: (context, value, child) {
                  return Container(
                    width: busy ? 6 : 7,
                    height: busy ? 6 : 7,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4CAF50),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          // পিং চলার সময় চারপাশে সবুজ রঙের গ্লো বা লাইভ ইফেক্ট ছড়াবে
                          color: const Color(0xFF4CAF50)
                              .withOpacity(busy ? 0.7 : 0.3),
                          blurRadius: busy ? 6 * value : 2,
                          spreadRadius: busy ? 2 * value : 0,
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          )
        ],
        const Spacer(),
        GestureDetector(
          onTap: onTap,
          child: Text(actionText,
              style: const TextStyle(
                  color: Color(0xFF4F81F7),
                  fontWeight: FontWeight.bold,
                  fontSize: 14)),
        ),
      ],
    );
  }

  // --- 5. Live Ping Section (real data) ---
  Widget _buildLivePingGrid() {
    return ValueListenableBuilder<List<PingTarget>>(
      valueListenable: _svc.targets,
      builder: (context, targets, _) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = (constraints.maxWidth - 12) / 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (int i = 0; i < targets.length; i++)
                  _buildPingCard(cardWidth, targets[i], i),
                _buildAddTargetCard(cardWidth),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildPingCard(double width, PingTarget t, int index) {
    final last = t.history.isNotEmpty ? t.history.last : null;
    final ok = last?['success'] == true;
    final ms = ok ? (last!['avgMs'] as num?)?.round() : null;
    final statusColor = last == null
        ? Colors.grey
        : (ok ? const Color(0xFF4CAF50) : const Color(0xFFE53935));

    return GestureDetector(
      onTap: _editMode && t.removable ? () => _svc.removeTarget(index) : null,
      child: Container(
        width: width,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1B1B1D),
          borderRadius: BorderRadius.circular(12),
          border: _editMode && t.removable
              ? Border.all(color: const Color(0xFFE53935), width: 1)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(t.label,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                ),
                if (_editMode && t.removable)
                  const Icon(Icons.close, size: 14, color: Color(0xFFE53935))
                else
                  Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                          color: statusColor, shape: BoxShape.circle)),
              ],
            ),
            const SizedBox(height: 2),
            Text(t.host,
                style: const TextStyle(color: Colors.grey, fontSize: 11),
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(ms != null ? '$ms' : '--',
                    style: TextStyle(
                        color: statusColor,
                        fontSize: 24,
                        fontWeight: FontWeight.bold)),
                const Padding(
                  padding: EdgeInsets.only(bottom: 4.0, left: 2.0),
                  child: Text('ms',
                      style: TextStyle(color: Colors.grey, fontSize: 11)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _historyBars(t.history),
          ],
        ),
      ),
    );
  }

  Widget _historyBars(List<Map<String, dynamic>> history) {
    return Row(
      children: List.generate(15, (i) {
        final idx = i - (15 - history.length);
        Color c = const Color(0xFF333333);
        if (idx >= 0 && idx < history.length) {
          final h = history[idx];
          if (h['success'] != true) {
            c = const Color(0xFFE53935);
          } else {
            final ms = (h['avgMs'] as num?) ?? 0;
            c = ms < 50
                ? const Color(0xFF4CAF50)
                : (ms < 150
                    ? const Color(0xFFF2A900)
                    : const Color(0xFFE53935));
          }
        }
        return Expanded(
          child: Container(
            height: 4,
            margin: const EdgeInsets.only(right: 2),
            decoration:
                BoxDecoration(color: c, borderRadius: BorderRadius.circular(2)),
          ),
        );
      }),
    );
  }

  Widget _buildAddTargetCard(double width) {
    return Container(
      width: width,
      height: 105,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: const Color(0xFF333333), style: BorderStyle.solid, width: 2),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add, color: Color(0xFF4F81F7)),
          SizedBox(height: 8),
          Text('Add target',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildPingInputs() {
    return Row(
      children: [
        Expanded(flex: 2, child: _buildTextField(_nameCtrl, 'Name')),
        const SizedBox(width: 12),
        Expanded(flex: 3, child: _buildTextField(_hostCtrl, 'IP or domain')),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: () {
            if (_hostCtrl.text.trim().isEmpty) return;
            _svc.addTarget(_nameCtrl.text.trim(), _hostCtrl.text.trim());
            _nameCtrl.clear();
            _hostCtrl.clear();
            setState(() {});
          },
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
                color: const Color(0xFF223555),
                borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.add, color: Color(0xFF6B9CFA)),
          ),
        )
      ],
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String hint) {
    return SizedBox(
      height: 48,
      child: TextField(
        controller: ctrl,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF555555)),
          filled: true,
          fillColor: const Color(0xFF1B1B1D),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF333333))),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF333333))),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF4F81F7))),
        ),
      ),
    );
  }

  // --- 6. Network Details ---
  Widget _buildNetworkDetailsCard(WifiInfoModel info) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: const Color(0xFF1B1B1D),
          borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailItem('ISP', info.ispName ?? '--'),
                _buildDetailItem('Gateway', info.gatewayIp ?? '--'),
                _buildDetailItem('DNS 1', info.dns1 ?? '--'),
                _buildDetailItem('Access point', info.bssid ?? '--'),
                _buildDetailItem(
                    'Band',
                    info.band != null
                        ? '${info.band} · ch ${info.channel ?? '--'}'
                        : '--'),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailItem('Public IP', info.publicIp ?? '--'),
                _buildDetailItem('This phone', info.ipAddress ?? '--'),
                _buildDetailItem('DNS 2', info.dns2 ?? '--'),
                _buildDetailItem('Subnet', info.subnetMask ?? '--'),
                _buildDetailItem(
                    'DHCP lease',
                    info.dhcpLeaseSeconds != null
                        ? '${info.dhcpLeaseSeconds} s'
                        : '--'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Color(0xFF666666), fontSize: 11)),
          const SizedBox(height: 2),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
        ],
      ),
    );
  }

  void _copyDetails(WifiInfoModel info) {
    final text = [
      'ISP: ${info.ispName ?? '--'}',
      'Public IP: ${info.publicIp ?? '--'}',
      'Gateway: ${info.gatewayIp ?? '--'}',
      'This phone: ${info.ipAddress ?? '--'}',
      'DNS 1: ${info.dns1 ?? '--'}',
      'DNS 2: ${info.dns2 ?? '--'}',
      'Access point: ${info.bssid ?? '--'}',
      'Subnet: ${info.subnetMask ?? '--'}',
      'Band: ${info.band ?? '--'} · ch ${info.channel ?? '--'}',
      'DHCP lease: ${info.dhcpLeaseSeconds ?? '--'} s',
    ].join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Network details copied'),
          duration: Duration(seconds: 2)),
    );
  }
}

// Custom Painter — unchanged
class RadarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paintDark = Paint()
      ..color = const Color(0xFF333333).withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final paintLight = Paint()
      ..color = const Color(0xFF4CAF50).withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    final center = Offset(size.width / 2, size.height - 20);

    for (int i = -2; i <= 2; i++) {
      double angle = -math.pi / 2 + (i * math.pi / 6);
      canvas.drawLine(
          center,
          Offset(center.dx + math.cos(angle) * 200,
              center.dy + math.sin(angle) * 200),
          paintDark);
    }
    canvas.drawArc(Rect.fromCircle(center: center, radius: 140), math.pi,
        math.pi, false, paintDark);
    canvas.drawArc(Rect.fromCircle(center: center, radius: 90), math.pi,
        math.pi, false, paintDark);
    canvas.drawArc(Rect.fromCircle(center: center, radius: 45), math.pi,
        math.pi, false, paintLight);

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    _drawText(canvas, textPainter, '30 m', Offset(center.dx, center.dy - 145));
    _drawText(canvas, textPainter, '15 m', Offset(center.dx, center.dy - 95));
    _drawText(canvas, textPainter, '5 m', Offset(center.dx, center.dy - 50));
  }

  void _drawText(
      Canvas canvas, TextPainter painter, String text, Offset position) {
    painter.text = TextSpan(
        text: text,
        style: const TextStyle(color: Color(0xFF666666), fontSize: 10));
    painter.layout();
    painter.paint(canvas, Offset(position.dx - painter.width / 2, position.dy));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
