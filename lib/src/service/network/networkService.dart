import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'nativeNetworkChannel.dart';
import 'wifiInfoModel.dart';

class PingTarget {
  final String label;
  final String host;
  final bool removable;
  final List<Map<String, dynamic>> history; // [{success, avgMs}]

  PingTarget({
    required this.label,
    required this.host,
    this.removable = true,
    List<Map<String, dynamic>>? history,
  }) : history = history ?? [];

  Map<String, dynamic> toJson() => {'label': label, 'host': host};
  factory PingTarget.fromJson(Map<String, dynamic> j) =>
      PingTarget(label: j['label'], host: j['host']);
}

class NetworkService {
  NetworkService._();
  static final instance = NetworkService._();

  final wifiInfo = ValueNotifier<WifiInfoModel?>(null);
  final targets = ValueNotifier<List<PingTarget>>([]);
  final serviceReachabilityList = ValueNotifier<List<PingTarget>>([]);
  final isPinging = ValueNotifier<bool>(false);
  final gatewayReachable = ValueNotifier<bool?>(null);
  final internetReachable = ValueNotifier<bool?>(null);

  Timer? _wifiTimer;
  Timer? _pingTimer;
  Timer? _ispTimer;
  static const _prefsKey = 'genhr_ping_targets';

  Future<void> init() async {
    await Permission.locationWhenInUse.request();
    await _loadTargets();
    await refreshWifiInfo();
    startAutoRefresh();
  }

  bool _wifiRefreshInFlight = false;

  void startAutoRefresh() {
    _wifiTimer?.cancel();
    _pingTimer?.cancel();
    _ispTimer?.cancel();
    // Fast, near-realtime refresh. Guarded against overlap (see refreshWifiInfo
    // / pingAllTargets) so a slow native call never causes calls to stack up.
    _wifiTimer =
        Timer.periodic(const Duration(seconds: 2), (_) => refreshWifiInfo());
    _pingTimer =
        Timer.periodic(const Duration(seconds: 1), (_) => pingAllTargets());
    // Public IP / ISP rarely changes and depends on an external HTTP call —
    // keep this slow so it doesn't hammer ipapi.co or burn mobile data.
    _ispTimer =
        Timer.periodic(const Duration(minutes: 2), (_) => _fetchIspInfo());
    pingAllTargets();
  }

  void dispose() {
    _wifiTimer?.cancel();
    _pingTimer?.cancel();
    _ispTimer?.cancel();
  }

  String? _lastPublicIp;
  String? _lastIsp;

  Future<void> refreshWifiInfo() async {
    if (_wifiRefreshInFlight)
      return; // skip tick if previous call still running
    _wifiRefreshInFlight = true;
    try {
      final full = await NativeNetworkChannel.getWifiFullDetails();
      final enhanced = await NativeNetworkChannel.getEnhancedDeviceInfo();
      if (_lastPublicIp == null) await _fetchIspInfo();

      wifiInfo.value = WifiInfoModel.merge(
        full: full,
        enhanced: enhanced,
        publicIp: _lastPublicIp,
        ispName: _lastIsp,
      );
      _ensureDefaultTargets(wifiInfo.value!);
      _serviceReachability(wifiInfo.value!);
    } catch (_) {
      // keep last known good value on transient failure
    } finally {
      _wifiRefreshInFlight = false;
    }
  }

  Future<void> _fetchIspInfo() async {
    try {
      final res = await http
          .get(Uri.parse('https://ipwho.is/'))
          .timeout(const Duration(seconds: 6));
      if (res.statusCode == 200) {
        final map = jsonDecode(res.body) as Map;

        // ipwho.is সফল হলে "success": true দেয়, ব্যর্থ হলে false — আগে চেক করা দরকার
        if (map['success'] == false) return;

        _lastPublicIp = map['ip'] as String?;

        // ISP নাম connection.isp এর মধ্যে থাকে, না পেলে connection.org fallback
        final connection = map['connection'] as Map?;
        _lastIsp =
            (connection?['isp'] as String?) ?? (connection?['org'] as String?);

        if (wifiInfo.value != null) {
          wifiInfo.value = WifiInfoModel.merge(
            full: {},
            enhanced: {},
            publicIp: _lastPublicIp,
            ispName: _lastIsp,
          ).let(wifiInfo.value!);
        }
      }
    } catch (_) {}
  }

  void _ensureDefaultTargets(WifiInfoModel info) {
    if (targets.value.isNotEmpty) return;
    final list = <PingTarget>[
      if (info.gatewayIp != null)
        PingTarget(
            label: 'Router gateway', host: info.gatewayIp!, removable: false),
      if (info.dns1 != null && info.dns1 != '0.0.0.0')
        PingTarget(label: 'ISP DNS', host: info.dns1!, removable: false),
      PingTarget(label: 'BDIX peer', host: 'bdix.net.bd', removable: false),
      PingTarget(label: 'Google DNS', host: '8.8.8.8', removable: false),
      PingTarget(label: 'Cloudflare', host: '1.1.1.1', removable: false),
    ];
    targets.value = list;
  }

  void _serviceReachability(WifiInfoModel info) {
    if (serviceReachabilityList.value.isNotEmpty) return;
    final list = <PingTarget>[
      PingTarget(label: 'YouTube', host: 'youtube.com', removable: false),
      PingTarget(label: 'Facebook', host: 'facebook.com', removable: false),
      PingTarget(label: 'Netflix', host: 'netflix.com', removable: false),
      PingTarget(
          label: 'Google Play', host: 'play.google.com', removable: false),
      PingTarget(label: 'Google DNS', host: '8.8.8.8', removable: false),
    ];
    serviceReachabilityList.value = list;
  }

  Future<void> pingAllTargets() async {
    if (targets.value.isEmpty) return;
    if (isPinging.value)
      return; // previous round still running — don't stack up
    isPinging.value = true;
    final list = targets.value;

    await Future.wait(list.map((t) async {
      final res = await NativeNetworkChannel.pingHost(t.host,
          count: 1, timeoutSeconds: 1);
      t.history
          .add({'success': res['success'] ?? false, 'avgMs': res['avgMs']});
      if (t.history.length > 12) t.history.removeAt(0);

      if (t.label == 'Router gateway') {
        gatewayReachable.value = res['success'] as bool? ?? false;
      }
      if (t.host == '8.8.8.8') {
        internetReachable.value = res['success'] as bool? ?? false;
      }
    }));

    targets.value = [...list];
    // ২. নতুন serviceReachabilityList পিং করা (এটি যোগ করুন)
    if (serviceReachabilityList.value.isNotEmpty) {
      final serviceList = serviceReachabilityList.value;
      await Future.wait(serviceList.map((t) async {
        final res = await NativeNetworkChannel.pingHost(t.host,
            count: 1, timeoutSeconds: 1);
        t.history
            .add({'success': res['success'] ?? false, 'avgMs': res['avgMs']});
        if (t.history.length > 12) t.history.removeAt(0);
      }));
      serviceReachabilityList.value = [...serviceList];
    }
    isPinging.value = false;
  }

  Future<void> addTarget(String label, String host) async {
    targets.value = [
      ...targets.value,
      PingTarget(label: label.isEmpty ? host : label, host: host)
    ];
    await _saveTargets();
    pingAllTargets();
  }

  Future<void> removeTarget(int index) async {
    final list = [...targets.value];
    if (!list[index].removable) return;
    list.removeAt(index);
    targets.value = list;
    await _saveTargets();
  }

  Future<void> _loadTargets() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    final custom = (jsonDecode(raw) as List)
        .map((e) => PingTarget.fromJson(e as Map<String, dynamic>))
        .toList();
    targets.value = custom;
  }

  Future<void> _saveTargets() async {
    final prefs = await SharedPreferences.getInstance();
    final custom = targets.value.where((t) => t.removable).toList();
    await prefs.setString(
        _prefsKey, jsonEncode(custom.map((t) => t.toJson()).toList()));
  }

  /// Diagnosis text based on real reachability + signal quality
  String diagnosisTitle(WifiInfoModel info) =>
      'WiFi signal is ${info.signalQualityLabel}';

  String diagnosisSubtitle() {
    if (gatewayReachable.value == false)
      return 'Cannot reach the router — check WiFi connection';
    if (internetReachable.value == false)
      return 'Router OK, but internet is unreachable';
    return 'Internet line is stable — the issue is local';
  }
}

extension _MergeExt on WifiInfoModel {
  WifiInfoModel let(WifiInfoModel base) => WifiInfoModel(
        ssid: base.ssid,
        bssid: base.bssid,
        rssi: base.rssi,
        linkSpeedMbps: base.linkSpeedMbps,
        frequencyMhz: base.frequencyMhz,
        channelWidthMhz: base.channelWidthMhz,
        ipAddress: base.ipAddress,
        gatewayIp: base.gatewayIp,
        dns1: base.dns1,
        dns2: base.dns2,
        subnetMask: base.subnetMask,
        dhcpLeaseSeconds: base.dhcpLeaseSeconds,
        deviceName: base.deviceName,
        publicIp: publicIp,
        ispName: ispName,
      );
}
