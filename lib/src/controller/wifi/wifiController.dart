import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:lan_scanner/lan_scanner.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'package:apptrack/src/controller/allController.dart';
import 'package:apptrack/src/service/configs/appColors.dart';
import 'package:apptrack/src/view/pages/home/tab/discovery/model/nearbyNetworkModel.dart';
import 'package:apptrack/src/view/pages/home/tab/discovery/model/scannedDeviceModel.dart';
import 'package:apptrack/src/view/pages/home/tab/discovery/model/trafficDevice.dart';

const _routerBrands = [
  'tp-link',
  'tplink',
  'netgear',
  'asus',
  'linksys',
  'd-link',
  'dlink',
  'huawei',
  'xiaomi',
  'mercusys',
  'tenda',
  'zte',
  'mikrotik',
  'cisco',
];

class WifiController extends GetxController {
  StreamSubscription? scanSubscription;

  var scannedDevices = RxList<ScannedDevice>();
  var scanProgress = RxDouble(0.0);
  var isScanning = RxBool(false);
  var errorMessage = RxString('');

  final _platform = const MethodChannel('genhr.network/native');

  int? _lastRx;
  int? _lastTx;
  int? _lastTimestampMs;
  final myTrafficMbps =
      RxDouble(0.0); // upload+download মিলিয়ে (নিজের ফোনের রিয়েল ডেটা)

  // ==================== ACTIVE TRAFFIC — ONE-SHOT LOAD ====================

  var activeDevices = <TrafficDevice>[].obs;

  /// একবারই কল হবে — কোনো periodic timer, রিফ্রেশ, বা স্ট্রিম নেই।
  /// শিট ওপেন হওয়ার পরে ব্যাকগ্রাউন্ডে চলে, যাতে বাটনের progress loop
  /// ব্লক না হয়।
  Future<void> loadTrafficOnce() async {
    // নিজের ফোনের real rx/tx baseline নেওয়া (দুইবার tick করে delta বের করা)
    await _tickRealTraffic();
    await Future.delayed(const Duration(milliseconds: 1100));
    await _tickRealTraffic();

    // Discovery ট্যাবে আগেই স্ক্যান করা থাকলে সেটাই ব্যবহার করা হবে —
    // নতুন করে ভারী ২৫৪-IP ICMP scan আর চালানো হবে না।
    if (scannedDevices.isNotEmpty) {
      activeDevices.value =
          scannedDevices.map((d) => _trafficDeviceFromScanned(d)).toList();
      return;
    }

    // fallback: Discovery স্ক্যান না থাকলে নিজে হালকা স্ক্যান চালাবে
    await fetchConnectedDevices();
  }

  TrafficDevice _trafficDeviceFromScanned(ScannedDevice d) {
    final isSelf = d.isMe;
    final isRouter = d.isGateway;

    // নিজের ফোনের জন্য real mbps, বাকিদের জন্য deterministic (IP-ভিত্তিক)
    // estimate — random না, তাই বারবার দেখলেও একই সংখ্যা আসবে।
    final double mbps = isSelf
        ? myTrafficMbps.value
        : (isRouter
            ? 1.2 + ((d.ipAddress.hashCode.abs() % 10) / 10.0)
            : 0.3 + ((d.ipAddress.hashCode.abs() % 40) / 10.0));

    return TrafficDevice(
      id: d.ipAddress,
      name: d.deviceName ?? 'Unknown Device',
      subtitle: isSelf
          ? 'active connection'
          : (isRouter
              ? 'gateway interface'
              : '${_activityLabel(mbps)} (estimated)'),
      ip: d.ipAddress,
      mbps: mbps,
    );
  }

  Future<void> _tickRealTraffic() async {
    try {
      final Map result = await _platform.invokeMethod('getTrafficStats');
      final rx = result['totalRxBytes'] as int?;
      final tx = result['totalTxBytes'] as int?;
      final ts = result['timestampMs'] as int?;

      if (rx == null || tx == null || ts == null || rx < 0 || tx < 0) return;

      if (_lastRx != null && _lastTx != null && _lastTimestampMs != null) {
        final dtSec = (ts - _lastTimestampMs!) / 1000.0;
        if (dtSec > 0) {
          final deltaBytes = (rx - _lastRx!) + (tx - _lastTx!);
          // bytes -> bits -> Mbps
          final mbps = (deltaBytes * 8) / (dtSec * 1000000);
          myTrafficMbps.value = double.parse(mbps.toStringAsFixed(2));
        }
      }

      _lastRx = rx;
      _lastTx = tx;
      _lastTimestampMs = ts;
    } catch (e) {
      debugPrint('TrafficStats error: $e');
    }
  }

  // ==================== LAN DEVICES SCANNING (Discovery ট্যাব) ====================

  Future<bool> _ensureLocationPermission() async {
    var status = await Permission.location.status;
    if (!status.isGranted) status = await Permission.location.request();
    if (!status.isGranted) {
      errorMessage.value =
          "Location permission is required for Wi-Fi scanning.";
    }
    return status.isGranted;
  }

  Future<void> getConnectedWifiDevices() async {
    scanSubscription?.cancel();
    scanSubscription = null;

    if (!await _ensureLocationPermission()) {
      errorMessage.value = "Scan aborted: Location permission not granted.";
      return;
    }

    isScanning.value = true;
    scannedDevices.clear();
    scanProgress.value = 0.0;
    errorMessage.value = '';

    try {
      final info = NetworkInfo();
      final myIp = await info.getWifiIP();
      final gatewayIp = await info.getWifiGatewayIP();

      if (myIp == null || myIp.isEmpty) {
        errorMessage.value =
            "Could not get device IP. Are you connected to Wi-Fi?";
        return;
      }

      final subnet = myIp.substring(0, myIp.lastIndexOf('.'));
      final tempDevices = <ScannedDevice>[];

      scanSubscription = LanScanner()
          .icmpScan(
        subnet,
        firstIP: 1,
        lastIP: 254,
        scanThreads: 24,
        timeout: const Duration(milliseconds: 200),
        progressCallback: (p) => scanProgress.value = p,
      )
          .listen(
        (device) async {
          tempDevices.add(await _buildScannedDevice(device, myIp, gatewayIp));
          scannedDevices.value = List.from(tempDevices)
            ..sort((a, b) {
              if (a.isGateway != b.isGateway) return a.isGateway ? -1 : 1;
              if (a.isMe != b.isMe) return a.isMe ? -1 : 1;
              return a.ipAddress.compareTo(b.ipAddress);
            });
        },
        onError: (e) {
          errorMessage.value = "Scan error: $e";
          isScanning.value = false;
        },
        onDone: () {
          isScanning.value = false;
          scanProgress.value = 1.0;
        },
        cancelOnError: false,
      );
    } catch (e) {
      errorMessage.value = "Scan error: $e";
      isScanning.value = false;
    }
  }

  Future<ScannedDevice> _buildScannedDevice(
      Host device, String myIp, String? gatewayIp) async {
    final currentIp = device.internetAddress.address;
    final isMe = currentIp == myIp;
    final isGateway = currentIp == gatewayIp;

    String? inferredName;
    String? manufacturer;

    try {
      final names = await InternetAddress.lookup(currentIp);
      if (names.isNotEmpty) {
        inferredName = names.first.host;
        if (inferredName == currentIp || inferredName == 'localhost') {
          inferredName = null;
        }
      }
    } catch (_) {}

    if (isMe) {
      inferredName ??= myDeviceC.myDeviceInfo.value.deviceName ?? 'Your Device';
    } else if (isGateway) {
      manufacturer = await _detectRouterBrand(currentIp);
      inferredName = manufacturer != 'Unknown Router Brand'
          ? '$manufacturer Router'
          : 'Router';
    }

    final lower = (inferredName ?? '').toLowerCase();
    if (lower.contains('apple')) {
      manufacturer = 'Apple';
    } else if (lower.contains('samsung')) {
      manufacturer = 'Samsung';
    } else if (lower.contains('android')) {
      manufacturer = 'Android Device';
    }

    return ScannedDevice(
      ipAddress: currentIp,
      deviceName: inferredName ?? 'Unknown Device',
      manufacturer: manufacturer,
      pingTime: device.pingTime,
      isMe: isMe,
      isGateway: isGateway,
    );
  }

  Future<String> _detectRouterBrand(String ip) async {
    try {
      final response = await http
          .get(Uri.parse('http://$ip'))
          .timeout(const Duration(seconds: 2));
      final body = response.body.toLowerCase();
      final server = response.headers['server']?.toLowerCase() ?? '';
      for (final b in _routerBrands) {
        if (body.contains(b) || server.contains(b)) return b;
      }
    } catch (_) {}
    return 'Unknown Router Brand';
  }

  Widget getDeviceIcon(ScannedDevice device, {double? size}) {
    if (device.isMe) {
      return Image.asset('assets/icons/device.png',
          height: size ?? 25, width: size ?? 25, alignment: Alignment.center);
    }
    final name = device.deviceName?.toLowerCase() ?? '';
    IconData icon = Icons.devices;
    if (device.isGateway) {
      icon = Icons.router_outlined;
    } else if (name.contains('tv')) {
      icon = Icons.tv;
    } else if (name.contains('printer')) {
      icon = Icons.print;
    }
    return Icon(icon, color: AppColors.white54, size: size);
  }

  // ==================== WI-FI CHANNEL OVERLAP SCANNING ====================

  var nearbyNetworks = RxList<NearbyNetwork>();
  var channelRecommendation = RxString('Scanning nearby channels...');
  var currentChannel = RxInt(1);
  var channelWidthMhz = RxInt(20);

  Future<void> scanRealChannelOverlap() async {
    try {
      if (await WiFiScan.instance.canStartScan() != CanStartScan.yes) {
        channelRecommendation.value =
            'Failed to scan nearby networks. Check permissions.';
        return;
      }

      await WiFiScan.instance.startScan();
      final results = await WiFiScan.instance.getScannedResults();
      final currentBssid = await NetworkInfo().getWifiBSSID();

      if (currentBssid != null && currentBssid.isNotEmpty) {
        final connectedAp = results.firstWhereOrNull(
            (ap) => ap.bssid.toLowerCase() == currentBssid.toLowerCase());
        if (connectedAp != null) {
          currentChannel.value =
              _getChannelFromFrequency(connectedAp.frequency);
          channelWidthMhz.value = _getBandwidthInMhz(connectedAp.channelWidth);
        }
      }

      final spanOffset = _getSpanOffset(channelWidthMhz.value);
      final realNetworks = <NearbyNetwork>[];
      var conflictCount = 0;

      for (final ap in results) {
        final ch = _getChannelFromFrequency(ap.frequency);
        final isSelf = currentBssid != null &&
            ap.bssid.toLowerCase() == currentBssid.toLowerCase();
        final isOverlapping = _isSameBand(currentChannel.value, ch) &&
            !isSelf &&
            ch >= currentChannel.value - spanOffset &&
            ch <= currentChannel.value + spanOffset;

        if (isOverlapping) conflictCount++;

        realNetworks.add(NearbyNetwork(
          ssid: ap.ssid.isNotEmpty ? ap.ssid : 'Hidden Network',
          channel: ch,
          signalDbm: ap.level,
          isOverlapping: isOverlapping,
          isSelf: isSelf,
        ));
      }

      realNetworks.sort((a, b) => b.signalDbm.compareTo(a.signalDbm));
      nearbyNetworks.value = realNetworks;

      channelRecommendation.value = conflictCount > 0
          ? 'Warning: Found $conflictCount overlapping networks. Consider changing your router channel to 1, 6, or 11.'
          : 'Great! Your channel ${currentChannel.value} is clear from interference.';
    } catch (e) {
      channelRecommendation.value = 'Scan error: $e';
    }
  }

  String getChannelSpanText(int channel, int bandwidthMhz) {
    final spanOffset = _getSpanOffset(bandwidthMhz);
    final maxLimit = channel <= 14 ? 14 : 165;
    final start = (channel - spanOffset).clamp(1, maxLimit);
    final end = (channel + spanOffset).clamp(1, maxLimit);
    return 'Your channel $channel at $bandwidthMhz MHz spans $start – $end';
  }

  int _getSpanOffset(int widthMhz) =>
      widthMhz >= 80 ? 8 : (widthMhz >= 40 ? 4 : 2);

  bool _isSameBand(int ch1, int ch2) => (ch1 <= 14) == (ch2 <= 14);

  int _getChannelFromFrequency(int freq) {
    if (freq >= 2412 && freq <= 2484) return ((freq - 2412) / 5).round() + 1;
    if (freq >= 5170 && freq <= 5825) return ((freq - 5170) / 5).round() + 34;
    return 1;
  }

  int _getBandwidthInMhz(dynamic bw) {
    final str = bw?.toString().toLowerCase() ?? '';
    if (str.contains('160')) return 160;
    if (str.contains('80')) return 80;
    if (str.contains('40')) return 40;
    return 20;
  }

  // ==================== ACTIVE TRAFFIC — FALLBACK SCAN ====================

  /// একবার স্ক্যান করে activeDevices আপডেট করে — শুধুমাত্র fallback হিসেবে
  /// ব্যবহৃত হয় যখন Discovery ট্যাবে আগে থেকে কোনো স্ক্যান করা থাকে না।
  Future<void> fetchConnectedDevices() async {
    if (!await _ensureLocationPermission()) {
      errorMessage.value =
          "Location permission is required for traffic scanning.";
      return;
    }

    isScanning.value = true;
    try {
      final info = NetworkInfo();
      final myIp = await info.getWifiIP();
      if (myIp == null || myIp.isEmpty) {
        errorMessage.value =
            "Could not get device IP. Are you connected to Wi-Fi?";
        return;
      }

      final subnet = myIp.substring(0, myIp.lastIndexOf('.'));
      final seenIds = <String>{};
      final completer = Completer<void>();

      LanScanner()
          .icmpScan(
        subnet,
        firstIP: 1,
        lastIP: 254,
        scanThreads: 24,
        timeout: const Duration(milliseconds: 200),
      )
          .listen(
        (host) async {
          final device =
              await _buildTrafficDevice(host.internetAddress.address, myIp);
          seenIds.add(device.id);
          final idx = activeDevices.indexWhere((d) => d.id == device.id);
          if (idx == -1) {
            activeDevices.add(device);
          } else {
            activeDevices[idx].mbps.value = device.mbps.value;
          }
        },
        onDone: () {
          activeDevices.removeWhere((d) => !seenIds.contains(d.id));
          if (!completer.isCompleted) completer.complete();
        },
        onError: (e) {
          errorMessage.value = "Scan error: $e";
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: false,
      );

      await completer.future;
    } catch (e) {
      debugPrint('Network scan error: $e');
    } finally {
      isScanning.value = false;
    }
  }

  Future<TrafficDevice> _buildTrafficDevice(String ip, String myIp) async {
    final isSelf = ip == myIp;
    final isRouter = ip.endsWith('.1');

    String name = 'Unknown Device';
    String? subtitle;

    if (isSelf) {
      name = myDeviceC.myDeviceInfo.value.deviceName ?? 'This Phone (You)';
      subtitle = 'active connection';
    } else if (isRouter) {
      name = 'Wi-Fi Router';
      subtitle = 'gateway interface';
    } else {
      try {
        final host = await InternetAddress(ip)
            .reverse()
            .timeout(const Duration(milliseconds: 400));
        name = host.host != ip ? _prettifyHostname(host.host) : 'Device ($ip)';
      } catch (_) {
        name = 'Device ($ip)';
      }
    }

    final double mbps = isSelf
        ? myTrafficMbps.value
        : (isRouter
            ? 1.2 + ((ip.hashCode.abs() % 10) / 10.0)
            : 0.3 + ((ip.hashCode.abs() % 40) / 10.0));

    return TrafficDevice(
      id: ip,
      name: name,
      subtitle: subtitle ?? '${_activityLabel(mbps)} (estimated)',
      ip: ip,
      mbps: mbps,
    );
  }

  /// "semol-s-a34" / "laptop_hp" এর মতো raw hostname কে "Semol S A34" /
  /// "Laptop Hp" এর মতো readable Title Case-এ কনভার্ট করে।
  String _prettifyHostname(String host) {
    final base = host.split('.').first.replaceAll(RegExp(r'[-_]+'), ' ').trim();
    if (base.isEmpty) return host;
    return base
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  String _activityLabel(double mbps) {
    if (mbps >= 8) return '4K streaming';
    if (mbps >= 3) return 'streaming';
    if (mbps >= 1) return 'browsing';
    return 'background sync';
  }

  @override
  void onClose() {
    scanSubscription?.cancel();
    super.onClose();
  }
}
