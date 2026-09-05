import 'package:flutter/services.dart';

class WifiService {
  static const MethodChannel _channel = MethodChannel('wifi.info.channel');

  static Future<bool> getWifiEnabled() async {
    final result = await _channel.invokeMethod<bool>('getWifiEnabled');

    return result ?? false;
  }

  static Future<Map<String, dynamic>> toggleWifi() async {
    final result = await _channel.invokeMethod('toggleWifi');

    return Map<String, dynamic>.from(result);
  }
}
