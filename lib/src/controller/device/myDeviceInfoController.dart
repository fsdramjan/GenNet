import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:apptrack/src/model/device/myDeviceModel.dart';

class MyDeviceController extends GetxController {
  static const platform = MethodChannel('wifi.info.channel');
  var myDeviceInfo = MyDeviceModel().obs;

  Future getCurrentDeviceInfo() async {
    try {
      final result = await platform.invokeMethod<Map>('getDeviceInfo');

      myDeviceInfo.value = MyDeviceModel(
        deviceName: result!['deviceName'],
        model: result['model'],
        manufacturer: result['manufacturer'],
        deviceType: result['deviceType'],
        firmwareVersion: result['firmwareVersion'],
        uptime: result['uptime'],
        ipAddress: result['ipAddress'],
        gateway: result['gateway'],
        dnsServer: result['dnsServer'],
        signal: result['signal'],
      );
    } on PlatformException catch (e) {
      print('Failed to get device info: ${e.message}');
    }
  }
}
