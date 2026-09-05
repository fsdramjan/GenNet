// Data model for a scanned device
class ScannedDevice {
  final String ipAddress;
  final String? deviceName; // Hostname or inferred name
  final String? manufacturer; // Inferred from hostname or OUI
  final Duration? pingTime;
  final bool isMe;
  final bool isGateway;
  List<int>? openPorts; // List of open ports

  ScannedDevice({
    required this.ipAddress,
    this.deviceName,
    this.manufacturer,
    this.pingTime,
    this.isMe = false,
    this.isGateway = false,
    this.openPorts,
  });

  // Helper to update properties
  ScannedDevice copyWith({
    String? ipAddress,
    String? deviceName,
    String? manufacturer,
    Duration? pingTime,
    bool? isMe,
    bool? isGateway,
    List<int>? openPorts,
  }) {
    return ScannedDevice(
      ipAddress: ipAddress ?? this.ipAddress,
      deviceName: deviceName ?? this.deviceName,
      manufacturer: manufacturer ?? this.manufacturer,
      pingTime: pingTime ?? this.pingTime,
      isMe: isMe ?? this.isMe,
      isGateway: isGateway ?? this.isGateway,
      openPorts: openPorts ?? this.openPorts,
    );
  }
}
