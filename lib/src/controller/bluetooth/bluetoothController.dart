import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:apptrack/src/controller/allController.dart';
import 'package:apptrack/src/service/configs/appUtils.dart';

class BluetoothController extends GetxController {
  var scannedDevices = RxList<Map<String, dynamic>>();
  var isScanning = RxBool(false);
  Timer? timer;
  var scanProgress = RxDouble(0.0);

  Future<void> requestPermissionsAndStartScan(BuildContext context) async {
    bool granted = await requestPermissions();
    if (granted) {
      startContinuousScan();
    } else {
      // Permission denied, show dialog or message
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('Permissions required'),
          content: Text(
              'Location and Nearby Devices permissions are required for BLE scanning.'),
          actions: [
            TextButton(
              child: Text('Open Settings'),
              onPressed: () {
                openAppSettings();
                Navigator.pop(context);
              },
            ),
          ],
        ),
      );
    }
  }

  Future<bool> requestPermissions() async {
    // Location permission (required for BLE scanning on Android)
    final statusLocation = await Permission.location.status;
    final statusNearby = await Permission.bluetoothScan.status;

    if (!statusLocation.isGranted) {
      final locResult = await Permission.location.request();
      if (!locResult.isGranted) return false;
    }

    // Android 12+ needs BLUETOOTH_SCAN permission separately
    if (!statusNearby.isGranted) {
      final nearbyResult = await Permission.bluetoothScan.request();
      if (!nearbyResult.isGranted) return false;
    }

    // Optionally request BLUETOOTH_CONNECT for Android 12+
    final statusConnect = await Permission.bluetoothConnect.status;
    if (!statusConnect.isGranted) {
      final connectResult = await Permission.bluetoothConnect.request();
      if (!connectResult.isGranted) return false;
    }

    return true;
  }

  void startContinuousScan() async {
    await startScan();
    timer = Timer.periodic(Duration(seconds: 1), (_) async {
      await fetchDevices();
    });
  }

  Future<void> startScan() async {
    try {
      wifiC.scanSubscription!.cancel();
      wifiC.scanSubscription = null;
      isScanning.value = true;

      await AppUtils.platform.invokeMethod('startBleScan');
    } on PlatformException catch (e) {
      print("Failed to start scan: '${e.message}'.");
    }
  }

  Future<void> stopScan() async {
    try {
      await AppUtils.platform.invokeMethod('stopBleScan');
    } on PlatformException catch (e) {
      print("Failed to stop scan: '${e.message}'.");
    }
  }

  Future<void> fetchDevices() async {
    try {
      isScanning.value = true;
      scanProgress.value = 10.0;

      final List<dynamic> results =
          await AppUtils.platform.invokeMethod('getScannedBluetoothDevices');
      scanProgress.value = 50.0;

      scannedDevices.value = results.map<Map<String, dynamic>>((device) {
        return Map<String, dynamic>.from(
            device.map((key, value) => MapEntry(key.toString(), value)));
      }).toList();

      scanProgress.value = 70.0;
    } on PlatformException catch (e) {
      print("Failed to get devices: '${e.message}'.");
    } finally {
      // Always called, success or error

      await Timer.periodic(Duration(seconds: 1), (v) {});
      isScanning.value = false;
      scanProgress.value = 100.0;
    }
  }

  // Future<void> fetchDevices() async {
  //   try {
  //     scanProgress .value= 10.0;

  //     final List<dynamic> results =
  //         await AppUtils.platform.invokeMethod('getScannedBluetoothDevices');
  //     scanProgress.value = 30.0;

  //     scannedDevices.value = results.map<Map<String, dynamic>>((device) {
  //       scanProgress .value= 50.0;

  //       return Map<String, dynamic>.from(
  //           device.map((key, value) => MapEntry(key.toString(), value)));
  //     }).toList();
  //     scanProgress.value = 70.0;

  //       isScanning .value= false;
  //       scanProgress .value= 100.0;

  //   } on PlatformException catch (e) {
  //     print("Failed to get devices: '${e.message}'.");

  //       isScanning .value= false;
  //       scanProgress .value= 100.0;

  //   }
  // }

  // Widget buildDeviceTile(Map<String, dynamic> device) {
  //   return Card(
  //     margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
  //     child: ListTile(
  //       title: KText(text: device['name'] ?? 'Unknown Device'),
  //       subtitle: KText(
  //         text: 'MAC: ${device['address']}\n'
  //             'RSSI: ${device['rssi']}\n'
  //             'Manufacturer: ${device['manufacturer'] ?? 'N/A'}\n'
  //             'Device Type: ${device['deviceType'] ?? 'N/A'}\n'
  //             'Service UUIDs: ${device['serviceUuids'] ?? 'N/A'}',
  //       ),
  //       isThreeLine: true,
  //     ),
  //   );
  // }
}
