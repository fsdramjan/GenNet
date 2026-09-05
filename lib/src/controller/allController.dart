import 'package:get/get.dart';
import 'package:apptrack/src/controller/bluetooth/bluetoothController.dart';
import 'package:apptrack/src/controller/wifi/wifiController.dart';
import 'device/myDeviceInfoController.dart';

final myDeviceC = Get.put(MyDeviceController(), permanent: true);
final wifiC = Get.put(WifiController(), permanent: true);
final bluetoothC = Get.put(BluetoothController(), permanent: true);
