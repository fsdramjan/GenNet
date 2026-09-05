import 'dart:math';

class WifiInfoModel {
  final String? ssid;
  final String? bssid;
  final int? rssi;
  final int? linkSpeedMbps;
  final int? frequencyMhz;
  final int? channelWidthMhz;
  final String? ipAddress;
  final String? gatewayIp;
  final String? dns1;
  final String? dns2;
  final String? subnetMask;
  final int? dhcpLeaseSeconds;
  final String? deviceName;
  final String? publicIp;
  final String? ispName;

  const WifiInfoModel({
    this.ssid,
    this.bssid,
    this.rssi,
    this.linkSpeedMbps,
    this.frequencyMhz,
    this.channelWidthMhz,
    this.ipAddress,
    this.gatewayIp,
    this.dns1,
    this.dns2,
    this.subnetMask,
    this.dhcpLeaseSeconds,
    this.deviceName,
    this.publicIp,
    this.ispName,
  });

  factory WifiInfoModel.merge({
    required Map<String, dynamic> full,
    required Map<String, dynamic> enhanced,
    String? publicIp,
    String? ispName,
  }) {
    String? cleanSsid(dynamic v) {
      final s = v?.toString().replaceAll('"', '');
      if (s == null || s.isEmpty || s == '<unknown ssid>') return null;
      return s;
    }

    return WifiInfoModel(
      ssid: cleanSsid(full['ssid']),
      bssid: (full['bssid'] == '02:00:00:00:00:00')
          ? null
          : full['bssid'] as String?,
      rssi: (full['rssi'] as int?) ?? (enhanced['wifiRssi'] as int?),
      linkSpeedMbps:
          (full['linkSpeed'] as int?) ?? (enhanced['wifiLinkSpeed'] as int?),
      frequencyMhz:
          (full['frequency'] as int?) ?? (enhanced['wifiFrequency'] as int?),
      channelWidthMhz: full['channelWidth'] as int?,
      ipAddress:
          (enhanced['ipAddress'] as String?) ?? (full['ipAddress'] as String?),
      gatewayIp: enhanced['gateway'] as String?,
      dns1: enhanced['dns1'] as String?,
      dns2: enhanced['dns2'] as String?,
      subnetMask: enhanced['subnetMask'] as String?,
      dhcpLeaseSeconds: enhanced['leaseDuration'] as int?,
      deviceName: enhanced['deviceName'] as String?,
      publicIp: publicIp,
      ispName: ispName,
    );
  }

  int? get channel {
    if (frequencyMhz == null) return null;
    final f = frequencyMhz!;

    // Check if frequency is in the 2.4 GHz band (Channel 1-14)
    if (f >= 2412 && f <= 2484) {
      return (f - 2412) ~/ 5 + 1;
    }

    // Check if frequency is in the 5 GHz band
    if (f >= 5170 && f <= 5825) {
      return (f - 5170) ~/ 5 + 34;
    }

    return null;
  }

  bool get in24 =>
      frequencyMhz != null && frequencyMhz! >= 2412 && frequencyMhz! <= 2484;

  String? get band {
    if (frequencyMhz == null) return null;
    return in24 ? '2.4 GHz' : '5 GHz';
  }

  String get signalQualityLabel {
    if (rssi == null) return '--';
    if (rssi! > -50) return 'Excellent';
    if (rssi! > -60) return 'Good';
    if (rssi! > -70) return 'Fair';
    return 'Weak';
  }

  String get signalQualityDesc {
    switch (signalQualityLabel) {
      case 'Excellent':
        return 'Strong signal, no issues expected';
      case 'Good':
        return 'Solid connection for most tasks';
      case 'Fair':
        return 'Usable, but speed will drop on heavy use';
      case 'Weak':
        return 'Move closer to the router for better speed';
      default:
        return '';
    }
  }

  /// Approximate distance from RSSI (log-distance path-loss model).
  /// This is an estimate — real accuracy needs AP calibration.
  double? get estimatedDistanceMeters {
    if (rssi == null) return null;
    const txPower = -40;
    const n = 2.5;
    final ratio = (txPower - rssi!) / (10 * n);
    return double.parse(pow(10, ratio).toStringAsFixed(1));
  }
}
