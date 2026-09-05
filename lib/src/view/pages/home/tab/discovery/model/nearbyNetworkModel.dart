class NearbyNetwork {
  final String ssid;
  final int channel;
  final int signalDbm;
  final bool isOverlapping;
  final bool isSelf; // নিজের নেটওয়ার্ক চেনার জন্য

  NearbyNetwork({
    required this.ssid,
    required this.channel,
    required this.signalDbm,
    required this.isOverlapping,
    this.isSelf = false,
  });
}
