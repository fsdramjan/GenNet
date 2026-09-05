import 'package:flutter/services.dart';

class NativeNetworkChannel {
  static const _channel = MethodChannel('wifi.info.channel');

  static Future<Map<String, dynamic>> getWifiFullDetails() async {
    final r = await _channel.invokeMethod('getWifiFullDetails');
    return Map<String, dynamic>.from(r as Map);
  }

  static Future<Map<String, dynamic>> getEnhancedDeviceInfo() async {
    final r = await _channel.invokeMethod('getEnhancedDeviceInfo');
    return Map<String, dynamic>.from(r as Map);
  }

  static Future<Map<String, dynamic>> pingHost(
    String host, {
    int count = 1,
    int timeoutSeconds = 3,
  }) async {
    try {
      final r = await _channel.invokeMethod('pingHost', {
        'host': host,
        'count': count,
        'timeoutSeconds': timeoutSeconds,
      });
      return Map<String, dynamic>.from(r as Map);
    } catch (e) {
      return {'success': false, 'avgMs': null, 'host': host};
    }
  }
}
