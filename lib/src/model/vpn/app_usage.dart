import 'dart:typed_data';

class AppInfo {
  final String packageName;
  final String appName;
  final int uid;
  final Uint8List? icon;

  const AppInfo({
    required this.packageName,
    required this.appName,
    required this.uid,
    this.icon,
  });

  factory AppInfo.fromMap(
    Map<dynamic, dynamic> map,
  ) {
    final rawIcon = map['icon'];

    Uint8List? icon;

    if (rawIcon is Uint8List) {
      icon = rawIcon;
    } else if (rawIcon is List) {
      icon = Uint8List.fromList(
        List<int>.from(
          rawIcon,
        ),
      );
    }

    return AppInfo(
      packageName: '${map['packageName'] ?? ''}',
      appName: '${map['appName'] ?? map['packageName'] ?? ''}',
      uid: (map['uid'] as num?)?.toInt() ?? -1,
      icon: icon,
    );
  }
}

class AppUsage {
  final String packageName;
  final String appName;
  final int uid;
  final int rxBytes;
  final int txBytes;

  const AppUsage({
    required this.packageName,
    required this.appName,
    required this.uid,
    required this.rxBytes,
    required this.txBytes,
  });

  int get totalBytes => rxBytes + txBytes;

  factory AppUsage.fromMap(
    Map<dynamic, dynamic> map,
  ) {
    return AppUsage(
      packageName: '${map['packageName'] ?? ''}',
      appName: '${map['appName'] ?? map['packageName'] ?? ''}',
      uid: (map['uid'] as num?)?.toInt() ?? -1,
      rxBytes: (map['rxBytes'] as num?)?.toInt() ?? 0,
      txBytes: (map['txBytes'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'packageName': packageName,
      'appName': appName,
      'uid': uid,
      'rxBytes': rxBytes,
      'txBytes': txBytes,
      'totalBytes': totalBytes,
    };
  }

  static String humanBytes(
    int bytes,
  ) {
    if (bytes < 1024) {
      return '$bytes B';
    }

    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }

    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }

    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class FlowEntry {
  final String destinationIp;
  final int destinationPort;
  final String protocol;
  final int bytes;
  final int ipVersion;
  final int uid;
  final int packetCount;

  const FlowEntry({
    required this.destinationIp,
    required this.destinationPort,
    required this.protocol,
    required this.bytes,
    required this.ipVersion,
    required this.uid,
    this.packetCount = 0,
  });

  factory FlowEntry.fromMap(
    Map<dynamic, dynamic> map,
  ) {
    return FlowEntry(
      destinationIp: '${map['destinationIp'] ?? ''}',
      destinationPort: (map['destinationPort'] as num?)?.toInt() ?? 0,
      protocol: '${map['protocol'] ?? 'IP'}',
      bytes: (map['bytes'] as num?)?.toInt() ?? 0,
      ipVersion: (map['ipVersion'] as num?)?.toInt() ?? 4,
      uid: (map['uid'] as num?)?.toInt() ?? -1,
      packetCount: (map['packetCount'] as num?)?.toInt() ?? 0,
    );
  }

  String get endpoint {
    if (destinationIp.isEmpty) {
      return '-';
    }

    if (destinationPort == 0) {
      return destinationIp;
    }

    return '$destinationIp:$destinationPort';
  }

  Map<String, dynamic> toJson() {
    return {
      'destinationIp': destinationIp,
      'destinationPort': destinationPort,
      'protocol': protocol,
      'bytes': bytes,
      'ipVersion': ipVersion,
      'uid': uid,
      'packetCount': packetCount,
    };
  }
}
