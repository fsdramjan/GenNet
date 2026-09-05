import 'package:flutter/services.dart';

class NetworkInfo {
  // This is the name of the MethodChannel.
  // It MUST exactly match the CHANNEL string defined in your MainActivity.kt file.
  static const MethodChannel _platform =
      const MethodChannel('wifi.info.channel');

  /// Fetches Wi-Fi signal strength (RSSI) and link speed from the native side.
  ///
  /// Returns a [Map<String, dynamic>] containing:
  /// - 'signalStrength': [int] The RSSI value in dBm (e.g., -60).
  /// - 'linkSpeed': [int] The link speed in Mbps (e.g., 72).
  ///
  /// Returns an empty map if an error occurs during the native method invocation.
  static Future<Map<String, dynamic>> getWifiSignalInfo() async {
    try {
      // Invoke the native method named 'getWifiSignalInfo'
      final Map<dynamic, dynamic>? result =
          await _platform.invokeMethod('getWifiSignalInfo');

      if (result != null) {
        // Cast the results to the expected types and return
        return {
          'signalStrength': result['signalStrength'] as int?,
          'linkSpeed': result['linkSpeed'] as int?,
        };
      }
      return {}; // Return empty map if result is null
    } on PlatformException catch (e) {
      // Catch PlatformException which occurs if the native method call fails
      print("Failed to get Wi-Fi signal info: '${e.message}'.");
      return {}; // Return empty map on error
    } catch (e) {
      // Catch any other unexpected errors
      print("An unexpected error occurred getting Wi-Fi signal info: '$e'.");
      return {};
    }
  }

  /// Fetches the ARP table (list of connected device IP addresses) from the native side.
  /// This method reads from `/proc/net/arp` on Android.
  ///
  /// Returns a [List<String>] where each string is an IP address of a connected device.
  ///
  /// Returns an empty list if an error occurs during the native method invocation
  /// or if no reachable devices are found in the ARP cache.
  static Future<List<String>> getConnectedDevices() async {
    try {
      // Invoke the native method named 'getArpTable'
      final List<dynamic>? result = await _platform.invokeMethod('scanConnectedDevices');

      if (result != null) {
        // Cast the dynamic list to a List<String> and return
        return result.cast<String>();
      }
      return []; // Return empty list if result is null
    } on PlatformException catch (e) {
      // Catch PlatformException which occurs if the native method call fails
      print("Failed to get ARP table: '${e.message}'.");
      return []; // Return empty list on error
    } catch (e) {
      // Catch any other unexpected errors
      print("An unexpected error occurred getting ARP table: '$e'.");
      return [];
    }
  }
}
