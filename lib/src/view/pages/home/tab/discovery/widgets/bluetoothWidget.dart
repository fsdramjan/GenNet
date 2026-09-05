// import 'dart:async';

// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'package:get/get.dart';
// import 'package:permission_handler/permission_handler.dart';
// import 'package:apptrack/src/controller/allController.dart';
// import 'package:apptrack/src/service/configs/appColors.dart';
// import 'package:apptrack/src/view/widgets/text/kText.dart';

// class BluetoothWidget extends StatefulWidget {
//   @override
//   _BluetoothWidgetState createState() => _BluetoothWidgetState();
// }

// class _BluetoothWidgetState extends State<BluetoothWidget> {
// @override
// void initState() {
//   super.initState();
//   bluetoothC.requestPermissionsAndStartScan(context);
// }

// @override
// void dispose() {
//   bluetoothC.stopScan();
//   bluetoothC.timer?.cancel();
//   super.dispose();
// }

//   // Future<void> requestPermissionsAndStartScan() async {
//   //   bool granted = await _requestPermissions();
//   //   if (granted) {
//   //     startContinuousScan();
//   //   } else {
//   //     // Permission denied, show dialog or message
//   //     showDialog(
//   //       context: context,
//   //       builder: (_) => AlertDialog(
//   //         title: Text('Permissions required'),
//   //         content: Text(
//   //             'Location and Nearby Devices permissions are required for BLE scanning.'),
//   //         actions: [
//   //           TextButton(
//   //             child: Text('Open Settings'),
//   //             onPressed: () {
//   //               openAppSettings();
//   //               Navigator.pop(context);
//   //             },
//   //           ),
//   //         ],
//   //       ),
//   //     );
//   //   }
//   // }

//   // Future<bool> _requestPermissions() async {
//   //   // Location permission (required for BLE scanning on Android)
//   //   final statusLocation = await Permission.location.status;
//   //   final statusNearby = await Permission.bluetoothScan.status;

//   //   if (!statusLocation.isGranted) {
//   //     final locResult = await Permission.location.request();
//   //     if (!locResult.isGranted) return false;
//   //   }

//   //   // Android 12+ needs BLUETOOTH_SCAN permission separately
//   //   if (!statusNearby.isGranted) {
//   //     final nearbyResult = await Permission.bluetoothScan.request();
//   //     if (!nearbyResult.isGranted) return false;
//   //   }

//   //   // Optionally request BLUETOOTH_CONNECT for Android 12+
//   //   final statusConnect = await Permission.bluetoothConnect.status;
//   //   if (!statusConnect.isGranted) {
//   //     final connectResult = await Permission.bluetoothConnect.request();
//   //     if (!connectResult.isGranted) return false;
//   //   }

//   //   return true;
//   // }

//   // void startContinuousScan() async {
//   //   await startScan();
//   //   _timer = Timer.periodic(Duration(seconds: 1), (_) async {
//   //     await fetchDevices();
//   //   });
//   // }

//   // Future<void> startScan() async {
//   //   try {
//   //     setState(() => isScanning = true);

//   //     await platform.invokeMethod('startBleScan');
//   //   } on PlatformException catch (e) {
//   //     print("Failed to start scan: '${e.message}'.");
//   //   }
//   // }

//   // Future<void> stopScan() async {
//   //   try {
//   //     await platform.invokeMethod('stopBleScan');
//   //   } on PlatformException catch (e) {
//   //     print("Failed to stop scan: '${e.message}'.");
//   //   }
//   // }

//   // Future<void> fetchDevices() async {
//   //   try {
//   //    scanProgress= 10.0;

//   //     final List<dynamic> results =
//   //         await platform.invokeMethod('getScannedBluetoothDevices');
//   //    scanProgress= 30.0;

//   //     scannedDevices = results.map<Map<String, dynamic>>((device) {
//   //      scanProgress= 50.0;

//   //       return Map<String, dynamic>.from(
//   //           device.map((key, value) => MapEntry(key.toString(), value)));
//   //     }).toList();
//   //    scanProgress= 70.0;

//   //     setState(() {
//   //       isScanning = false;
//   //      scanProgress= 100.0;
//   //     });
//   //   } on PlatformException catch (e) {
//   //     print("Failed to get devices: '${e.message}'.");
//   //     setState(() {
//   //       isScanning = false;
//   //      scanProgress= 100.0;
//   //     });
//   //   }
//   // }

//   // Widget buildDeviceTile(Map<String, dynamic> device) {
//   //   return Card(
//   //     margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
//   //     child: ListTile(
// title: Text(device['name'] ?? 'Unknown Device'),
//   //       subtitle: Text(
//   //         'MAC: ${device['address']}\n'
//   //         'RSSI: ${device['rssi']}\n'
//   //         'Manufacturer: ${device['manufacturer'] ?? 'N/A'}\n'
//   //         'Device Type: ${device['deviceType'] ?? 'N/A'}\n'
//   //         'Service UUIDs: ${device['serviceUuids'] ?? 'N/A'}',
//   //       ),
//   //       isThreeLine: true,
//   //     ),
//   //   );
//   // }

//   @override
//   Widget build(BuildContext context) {
//     return Obx(
//       () => bluetoothC.isScanning.value && bluetoothC.scannedDevices.isEmpty
//           ? Center(child: CircularProgressIndicator())
//           : bluetoothC.scannedDevices.isEmpty
//               ? Center(
//                   child: KText(
//                     text: 'No devices found.',
//                     color: AppColors.white,
//                   ),
//                 )
//               : ListView.builder(
//                   itemCount: bluetoothC.scannedDevices.length,
//                   itemBuilder: (context, index) => bluetoothC
//                       .buildDeviceTile(bluetoothC.scannedDevices[index]),
//                 ),
//     );
//   }
// }

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:apptrack/src/controller/allController.dart';
import 'package:apptrack/src/service/configs/appColors.dart';
import 'package:apptrack/src/service/helpers/divider/cDivider.dart';
import 'package:apptrack/src/service/helpers/sizedBox.dart';

import 'package:apptrack/src/view/widgets/text/kText.dart';

class BluetoothWidget extends StatefulWidget {
  @override
  _BluetoothWidgetState createState() => _BluetoothWidgetState();
}

class _BluetoothWidgetState extends State<BluetoothWidget> {
  @override
  void initState() {
    super.initState();
    bluetoothC.startContinuousScan();
  }

  @override
  void dispose() {
    bluetoothC.stopScan();
    bluetoothC.timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => SizedBox(
        height: Get.height - 150,
        width: Get.width,
        child: ListView(
          shrinkWrap: true,
          primary: false,
          children: [
            Row(
              children: [
                KText(
                  text: 'Devices (${bluetoothC.scannedDevices.length})',
                  fontWeight: FontWeight.bold,
                ),
                Spacer(),
                IconButton(
                  onPressed: () =>
                      bluetoothC.requestPermissionsAndStartScan(context),
                  icon: Container(
                    decoration: BoxDecoration(
                      color: AppColors.cardGrey,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      child: Row(
                        children: [
                          Padding(
                            padding: EdgeInsets.only(left: 10),
                            child: KText(
                              text: 'Refresh ',
                              color: AppColors.lightBlue,
                            ),
                          ),
                          Icon(
                            Icons.refresh,
                            color: AppColors.lightBlue,
                            size: 15,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // if (bluetoothC.errorMessage.isNotEmpty)
            //   Padding(
            //     padding: EdgeInsets.all(8.0),
            //     child: KText(
            //       text: bluetoothC.er.value,
            //       color: AppColors.red,
            //       textAlign: TextAlign.center,
            //     ),
            //   ),
            Card(
              color: AppColors.cardGrey,
              child: ListView.builder(
                shrinkWrap: true,
                primary: false,
                itemCount: bluetoothC.scannedDevices.length,
                itemBuilder: (context, index) {
                  final device = bluetoothC.scannedDevices[index];
                  return Column(
                    children: [
                      ListTile(
                        onTap: () {
                          // Get.to(
                          //   WifiDeviceDetailsPage(
                          //     scannedDeviceInfo: device,
                          //   ),
                          // );
                        },
                        shape: RoundedRectangleBorder(
                          borderRadius: index == 0
                              ? BorderRadius.only(
                                  topLeft: Radius.circular(8),
                                  topRight: Radius.circular(8),
                                )
                              : index == bluetoothC.scannedDevices.length - 1
                                  ? BorderRadius.only(
                                      bottomLeft: Radius.circular(8),
                                      bottomRight: Radius.circular(8),
                                    )
                                  : BorderRadius.zero,
                        ),

                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 2,
                        ),

                        // leading: bluetoothC.buildDeviceTile(device),
                        // isThreeLine: true,
                        title: KText(
                          text: device['name'] ?? 'Unknown Device',
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                          textAlign: TextAlign.start,
                        ),
                        subtitle: KText(text: device['address']),
                        trailing: SizedBox(
                          width: 120,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              KText(
                                text: device['rssi'].toString(),
                                color: AppColors.white54,
                                fontSize: 12,
                                textAlign: TextAlign.end,
                              ),
                              wSizedBox(5),
                              Icon(
                                Icons.arrow_forward_ios_outlined,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Conditionally hide the divider for the last item
                      if (index <
                          bluetoothC.scannedDevices.length -
                              1) // <-- MODIFIED LINE
                        cDivider(),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
