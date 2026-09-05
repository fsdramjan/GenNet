import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:share_plus/share_plus.dart';
import 'package:apptrack/src/controller/allController.dart';
import 'package:apptrack/src/service/configs/appColors.dart';
import 'package:apptrack/src/service/helpers/bottomshet/appBottomSheet.dart';
import 'package:apptrack/src/service/network/networkService.dart';

class DiagnosticReportSheet extends StatefulWidget {
  const DiagnosticReportSheet({super.key});

  static Future<void> show(BuildContext context) => AppBottomSheet.show(
        context,
        title: 'Diagnostic Report',
        child: const DiagnosticReportSheet(),
      );

  @override
  State<DiagnosticReportSheet> createState() => _DiagnosticReportSheetState();
}

class _DiagnosticReportSheetState extends State<DiagnosticReportSheet> {
  late final List<PingTarget> _serviceSnapshot;
  @override
  void initState() {
    super.initState();
    // শিট প্রথম ফ্রেম আঁকা হওয়ার পরে ব্যাকগ্রাউন্ডে ভারী traffic scan
    // চালানো হবে। বাটনের progress loop এই কাজের জন্য অপেক্ষা করে না,
    // তাই বাটন smooth/fast থাকে। _activeTraffic() widget Obx দিয়ে
    // wrapped, তাই ডেটা এলে নিজে থেকেই রিফ্রেশ হয়ে যাবে।
    _serviceSnapshot = List<PingTarget>.from(
      NetworkService.instance.serviceReachabilityList.value,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      wifiC.loadTrafficOnce();
    });
  }

  int? _lastMs(List targets, String label) {
    final t = targets.firstWhereOrNull((e) => e.label == label);
    if (t == null || t.history.isEmpty) return null;
    final last = t.history.last;
    return last['success'] == true ? (last['avgMs'] as num?)?.round() : null;
  }

  @override
  Widget build(BuildContext context) {
    final svc = NetworkService.instance;
    final info = svc.wifiInfo.value;
    final targets = svc.targets.value;

    if (info == null) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final gwOk = svc.gatewayReachable.value ?? false;
    final netOk = svc.internetReachable.value ?? false;
    final dnsMs = _lastMs(targets, 'ISP DNS');
    final signalOk = (info.rssi ?? -100) > -60;

    final checks = [
      _row('Phone → Router', 'ICMP to gateway', gwOk,
          gwOk ? '${_lastMs(targets, 'Router gateway') ?? '--'} ms' : '--'),
      _row('WiFi Signal', 'below -60 dBm threshold', signalOk,
          '${info.rssi ?? '--'} dBm'),
      _row('Router → Internet', 'ICMP to 8.8.8.8', netOk,
          netOk ? '${_lastMs(targets, 'Google DNS') ?? '--'} ms' : '--'),
      _row('DNS Resolve', 'ISP resolver', dnsMs != null,
          dnsMs != null ? '$dnsMs ms' : '--'),
    ];

    final okCount =
        [gwOk, signalOk, netOk, dnsMs != null].where((e) => e).length;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(info),
          const SizedBox(height: 12),
          _verdict(gwOk, netOk, dnsMs != null, info),
          const SizedBox(height: 12),
          _card(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(
                  'Path Check',
                  '$okCount / ${checks.length} OK',
                  okCount == checks.length
                      ? AppColors.green
                      : AppColors.amberBg),
              const SizedBox(height: 6),
              ...checks,
            ],
          )),
          const SizedBox(height: 12),
          _card(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle(
                  'Ping Targets',
                  '${targets.where((t) => t.history.isNotEmpty && t.history.last['success'] == true).length} / ${targets.length} OK',
                  AppColors.green),
              const SizedBox(height: 6),
              ...targets.map((t) {
                final last = t.history.isNotEmpty ? t.history.last : null;
                final ok = last?['success'] == true;
                final ms = ok ? (last!['avgMs'] as num?)?.round() : null;
                return _row(t.label, t.host, ok, ms != null ? '$ms ms' : '--');
              }),
            ],
          )),
          const SizedBox(height: 12),
          Builder(
            builder: (context) {
              final list = _serviceSnapshot;
              final slowOrFailedCount = list.where((t) {
                if (t.history.isEmpty) return false;
                final last = t.history.last;
                final success = last['success'] ?? false;
                final avgMs = last['avgMs'] as double?;
                return !success || (avgMs != null && avgMs > 150);
              }).length;

              return _card(Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionTitle(
                    'Service Reachability',
                    slowOrFailedCount > 0
                        ? '$slowOrFailedCount issues'
                        : 'All good',
                    slowOrFailedCount > 0
                        ? AppColors.amberBg
                        : Colors.green.withOpacity(0.2),
                  ),
                  const SizedBox(height: 6),
                  if (list.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: Text('Loading services...',
                            style: TextStyle(color: Colors.grey, fontSize: 13)),
                      ),
                    )
                  else
                    ...list.map((t) {
                      final last = t.history.isNotEmpty ? t.history.last : null;
                      final ok = last?['success'] ?? false;
                      final avgMs = last?['avgMs'] as double?;
                      final msText = ok && avgMs != null
                          ? '${avgMs.toStringAsFixed(1)} ms'
                          : 'Unreachable';
                      return _row(t.label, t.host, ok, msText);
                    }),
                ],
              ));
            },
          ),
          const SizedBox(height: 12),
          Obx(() => _channelOverlapCard()),
          const SizedBox(height: 12),
          _card(_activeTraffic()),
          const SizedBox(height: 12),
          _card(_stability()),
          const SizedBox(height: 16),
          _footer(context, info, targets),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ── Channel Overlap (dynamic, GetX) ─────────────────
  Widget _channelOverlapCard() {
    final conflictCount =
        wifiC.nearbyNetworks.where((n) => n.isOverlapping && !n.isSelf).length;
    final channel = wifiC.currentChannel.value;
    final widthMhz = wifiC.channelWidthMhz.value;
    final offset = widthMhz >= 80 ? 8 : (widthMhz >= 40 ? 4 : 2);
    final maxLimit = channel <= 14 ? 14 : 165;
    final startSpan = (channel - offset).clamp(1, maxLimit);
    final endSpan = (channel + offset).clamp(1, maxLimit);
    final networks = wifiC.nearbyNetworks;

    return _card(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(
          'Channel Overlap',
          networks.isEmpty ? 'Scanning...' : '$conflictCount conflicts',
          conflictCount > 0 ? AppColors.red : Colors.green,
        ),
        const SizedBox(height: 8),
        if (networks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text('No nearby networks detected',
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
            ),
          )
        else ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border, width: .3),
            ),
            child: Text.rich(TextSpan(
              style: const TextStyle(color: Colors.white70, fontSize: 13),
              children: [
                const TextSpan(text: 'Your channel '),
                TextSpan(
                    text: '$channel ',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                TextSpan(text: 'at $widthMhz MHz spans '),
                TextSpan(
                    text: '$startSpan – $endSpan',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            )),
          ),
          const SizedBox(height: 10),
          ...networks.map(_networkRow),
        ],
      ],
    ));
  }

  Widget _networkRow(net) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(
                        net.ssid,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: net.isSelf ? Colors.blueAccent : Colors.white,
                          fontWeight:
                              net.isSelf ? FontWeight.bold : FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (net.isSelf) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('YOU',
                            style: TextStyle(
                                color: Colors.blueAccent,
                                fontSize: 9,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ]),
                  Text('Channel ${net.channel}',
                      style: const TextStyle(color: Colors.grey, fontSize: 11)),
                ],
              ),
            ),
            Row(children: [
              Text('${net.signalDbm} dBm',
                  style: TextStyle(
                      color: net.signalDbm > -70 ? Colors.green : Colors.orange,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: net.isSelf
                      ? Colors.blueAccent.withOpacity(0.2)
                      : (net.isOverlapping
                          ? AppColors.red.withOpacity(0.2)
                          : Colors.green.withOpacity(0.2)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  net.isSelf
                      ? 'Connected'
                      : (net.isOverlapping ? 'Overlap' : 'Clear'),
                  style: TextStyle(
                    color: net.isSelf
                        ? Colors.blueAccent
                        : (net.isOverlapping ? AppColors.red : Colors.green),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ]),
          ],
        ),
      );

  // ── Real-data sections ─────────────────────────────
  Widget _header(info) {
    final id = '#GN-${DateTime.now().millisecondsSinceEpoch % 10000}';
    final ts = DateTime.now();
    const m = [
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
      'Dec'
    ];
    final tsStr = '${ts.day} ${m[ts.month - 1]} ${ts.year}, '
        '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';

    return _card(
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('GenNet Report',
              style: TextStyle(
                  color: AppColors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15)),
          _badge(id, AppColors.chipBlueBg, AppColors.chipBlueText),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _kv('Generated', tsStr)),
          Expanded(child: _kv('Network', info.ssid ?? '--')),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _kv('Client IP', info.ipAddress ?? '--')),
          Expanded(child: _kv('Access Point', info.bssid ?? '--')),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
              child: _kv(
                  'Band',
                  info.band != null
                      ? '${info.band} · ch ${info.channel ?? '--'} · ${info.channelWidthMhz ?? '--'}MHz'
                      : '--')),
          Expanded(
              child: _kv(
                  'Signal', info.rssi != null ? '${info.rssi} dBm' : '--',
                  valueColor: AppColors.amberBg)),
        ]),
      ]),
    );
  }

  /// ডাইনামিক ভার্ডিক্ট: gateway/internet/DNS স্ট্যাটাসের পাশাপাশি লাইভ সিগন্যাল
  /// স্ট্রেন্থ, লাইভ চ্যানেল-ওভারল্যাপ কনফ্লিক্ট আর লাইভ সার্ভিস-রিচেবিলিটি ইস্যু
  /// একসাথে বিবেচনা করে সবচেয়ে গুরুত্বপূর্ণ সমস্যাটা দেখায়। Obx + ValueListenableBuilder
  /// দিয়ে র‍্যাপ করা তাই ডেটা বদলালে কার্ডটাও রিয়েল-টাইমে বদলায়।
  Widget _verdict(bool gwOk, bool netOk, bool dnsOk, info) {
    // Obx আর ValueListenableBuilder বাদ দেওয়া হলো — nearbyNetworks এবং
    // serviceReachabilityList দুটোই এখন _serviceSnapshot / wifiC থেকে
    // একবার read করা হচ্ছে, লাইভ লিসেন করা হচ্ছে না। ফলে NetworkService-এর
    // ব্যাকগ্রাউন্ড টাইমার প্রতি সেকেন্ডে আপডেট করলেও এই widget rebuild হবে না।
    final conflictCount =
        wifiC.nearbyNetworks.where((n) => n.isOverlapping && !n.isSelf).length;

    final serviceIssues = _serviceSnapshot.where((t) {
      if (t.history.isEmpty) return false;
      final last = t.history.last;
      final success = last['success'] ?? false;
      final avgMs = last['avgMs'] as double?;
      return !success || (avgMs != null && avgMs > 150);
    }).length;

    final rssi = info.rssi ?? -100;
    final weakSignal = rssi <= -70;

    String title;
    String desc;
    Color accent;

    if (!gwOk) {
      title = 'Cannot reach the router';
      desc = 'Check your WiFi connection to the router.';
      accent = AppColors.red;
    } else if (!netOk) {
      title = 'Router OK, but internet is unreachable';
      desc = 'Contact your ISP if this persists.';
      accent = AppColors.red;
    } else if (!dnsOk) {
      title = 'Internet is up, but DNS is failing';
      desc =
          'The router and internet are reachable, but the ISP resolver isn\'t responding — try a public DNS like 8.8.8.8.';
      accent = AppColors.amberBg;
    } else if (weakSignal && conflictCount > 0) {
      title = 'Weak signal on a congested channel';
      desc =
          'Router and internet are reachable, but $conflictCount nearby network${conflictCount > 1 ? 's overlap' : ' overlaps'} your channel while your signal is weak ($rssi dBm).';
      accent = AppColors.amberBg;
    } else if (weakSignal) {
      title = 'Internet line is fine — the fault is local WiFi';
      desc =
          'Router reachable, internet reachable. Weak signal ($rssi dBm) is limiting throughput.';
      accent = AppColors.amberBg;
    } else if (conflictCount > 0) {
      title = 'Channel congestion detected';
      desc =
          '$conflictCount nearby network${conflictCount > 1 ? 's are' : ' is'} overlapping your WiFi channel. Consider switching to 1, 6, or 11.';
      accent = AppColors.amberBg;
    } else if (serviceIssues > 0) {
      title = 'Mostly healthy, a few services are slow';
      desc =
          '$serviceIssues service${serviceIssues > 1 ? 's are' : ' is'} slow or unreachable right now — this may be temporary.';
      accent = AppColors.amberBg;
    } else {
      title = 'Everything looks healthy';
      desc = 'Router and internet are both reachable with a solid signal.';
      accent = AppColors.green;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      width: Get.width,
      decoration: BoxDecoration(
        color: AppColors.cardBg2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent, width: .5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('VERDICT',
            style: TextStyle(
                color: accent,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1)),
        const SizedBox(height: 6),
        Text(title,
            style: TextStyle(
                color: AppColors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(desc, style: TextStyle(color: AppColors.subText, fontSize: 13)),
      ]),
    );
  }

  Widget _activeTraffic() {
    return Obx(() {
      final devices = wifiC.activeDevices;
      final total = devices.fold<double>(
        0.0,
        (a, b) => a + (b.mbps.value ?? 0.0),
      );
      final maxTraffic = devices.fold<double>(
        15.0,
        (max, b) {
          final v = b.mbps.value;
          if (v == null) return max;
          return v > max ? v : max;
        },
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('Active Traffic',
                style: TextStyle(
                    color: AppColors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
            _badge('${total.toStringAsFixed(1)} Mbps now', AppColors.cardBg2,
                AppColors.subText),
          ]),
          const SizedBox(height: 6),
          if (devices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('Scanning active traffic...',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
            )
          else
            ...devices.map((d) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(d.name,
                                  style: TextStyle(
                                      color: AppColors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13)),
                              if (d.subtitle.isNotEmpty)
                                Text(d.subtitle,
                                    style: TextStyle(
                                        color: AppColors.textMuted,
                                        fontSize: 11)),
                            ],
                          ),
                          Text(
                              d.mbps.value != null
                                  ? '${d.mbps.value!.toStringAsFixed(1)} Mbps'
                                  : 'Active',
                              style: TextStyle(
                                  color: AppColors.blueBg,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: d.mbps.value != null
                              ? (d.mbps.value! / maxTraffic).clamp(0.0, 1.0)
                              : 0.0,
                          backgroundColor: AppColors.cardBg2,
                          color: AppColors.blueBg,
                          minHeight: 3,
                        ),
                      ),
                    ],
                  ),
                )),
        ],
      );
    });
  }

  Widget _stability() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Stability · Last 24 h',
              style: TextStyle(
                  color: AppColors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15)),
          _badge('4 drops', AppColors.amberBg.withOpacity(0.15),
              AppColors.amberBg),
        ]),
        const SizedBox(height: 8),
        Text('Downtime 11 min · Uptime 99.2% · Longest drop 3m 40s',
            style: TextStyle(color: AppColors.subText, fontSize: 12)),
        const SizedBox(height: 12),
        SizedBox(
          height: 40,
          child: Row(
            children: List.generate(24, (h) {
              final bad = [15, 16, 21].contains(h);
              final warn = h == 18;
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  height: bad ? 34 : (warn ? 20 : 14),
                  decoration: BoxDecoration(
                    color: bad
                        ? AppColors.red
                        : (warn ? AppColors.amberBg : AppColors.green),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
        ),
      ]);

  // ── Footer: branding + copy/share ────────────────────
  Widget _footer(BuildContext context, info, List targets) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'Generated by GenNet · nuxtgen.com · Data collected on-device',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textMuted, fontSize: 11),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _footerButton(
                icon: Icons.copy_rounded,
                label: 'Copy as text',
                onTap: () => _copyReportAsText(context, info, targets),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _footerButton(
                icon: Icons.share_rounded,
                label: 'Share report',
                onTap: () => _shareReport(context, info, targets),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _footerButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.cardBg2,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border, width: .3),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppColors.white, size: 16),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      color: AppColors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  String _buildReportText(info, List targets) {
    final ts = DateTime.now();
    final conflictCount =
        wifiC.nearbyNetworks.where((n) => n.isOverlapping && !n.isSelf).length;
    final devices = wifiC.activeDevices;

    final buffer = StringBuffer();
    buffer.writeln('GenNet Diagnostic Report');
    buffer.writeln('Generated: ${ts.toLocal()}');
    buffer.writeln('');
    buffer.writeln('Network: ${info.ssid ?? '--'}');
    buffer.writeln('Client IP: ${info.ipAddress ?? '--'}');
    buffer.writeln('Access Point: ${info.bssid ?? '--'}');
    buffer.writeln('Signal: ${info.rssi ?? '--'} dBm');
    buffer.writeln(
        'Band: ${info.band ?? '--'} · ch ${info.channel ?? '--'} · ${info.channelWidthMhz ?? '--'} MHz');
    buffer.writeln('');
    buffer.writeln('-- Ping Targets --');
    for (final t in targets) {
      final last = t.history.isNotEmpty ? t.history.last : null;
      final ok = last?['success'] == true;
      final ms = ok ? (last!['avgMs'] as num?)?.round() : null;
      buffer.writeln(
          '${t.label} (${t.host}): ${ms != null ? '$ms ms' : 'unreachable'}');
    }
    buffer.writeln('');
    buffer.writeln('-- Channel Overlap --');
    buffer.writeln(
        'Current channel: ${wifiC.currentChannel.value}, $conflictCount conflicts');
    buffer.writeln('');
    buffer.writeln('-- Active Traffic --');
    for (final d in devices) {
      final mbps = d.mbps.value;
      buffer.writeln(
          '${d.name} (${d.ip}): ${mbps != null ? '${mbps.toStringAsFixed(1)} Mbps' : 'active'}');
    }
    buffer.writeln('');
    buffer.writeln(
        'Generated by GenNet · nuxtgen.com · Data collected on-device');

    return buffer.toString();
  }

  void _copyReportAsText(BuildContext context, info, List targets) {
    final text = _buildReportText(info, targets);
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Report copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _shareReport(BuildContext context, info, List targets) {
    final text = _buildReportText(info, targets);
    Share.share(text, subject: 'GenNet Diagnostic Report');
  }

  // ── Shared small widgets ────────────────────────────
  Widget _card(Widget child) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.cardBg2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border, width: .3),
        ),
        child: child,
      );

  Widget _kv(String k, String v, {Color? valueColor}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: TextStyle(color: AppColors.subText, fontSize: 11)),
        const SizedBox(height: 2),
        Text(v,
            style: TextStyle(
                color: valueColor ?? AppColors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13)),
      ]);

  Widget _badge(String text, Color bg, Color fg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Text(text,
            style: TextStyle(
                color: fg, fontSize: 11, fontWeight: FontWeight.bold)),
      );

  Widget _sectionTitle(String title, String badgeText, Color badgeColor) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(title,
            style: TextStyle(
                color: AppColors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15)),
        _badge(badgeText, badgeColor.withOpacity(0.15), badgeColor),
      ]);

  Widget _row(String title, String subtitle, bool ok, String trailing) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: ok ? AppColors.green : AppColors.amberBg,
                  shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: TextStyle(
                        color: AppColors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13)),
                Text(subtitle,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ])),
          Text(trailing,
              style: TextStyle(
                  color: ok ? AppColors.green : AppColors.amberBg,
                  fontWeight: FontWeight.bold,
                  fontSize: 13)),
        ]),
      );
}
