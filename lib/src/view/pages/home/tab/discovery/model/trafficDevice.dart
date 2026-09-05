import 'package:get/get.dart';

class TrafficDevice {
  final String id;
  final String name;
  final String subtitle;
  final String ip;
  final Rx<double?> mbps;

  TrafficDevice({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.ip,
    double? mbps,
  }) : mbps = Rx<double?>(mbps);
}
