enum StabilityStatus { good, warning, bad }

class StabilityModel {
  final int dropsCount;
  final int downtimeMinutes;
  final double uptimePercentage;
  final String longestDrop;
  final List<StabilityStatus> hourlyStatus; // ২৪টি ঘণ্টার লিস্ট

  StabilityModel({
    required this.dropsCount,
    required this.downtimeMinutes,
    required this.uptimePercentage,
    required this.longestDrop,
    required this.hourlyStatus,
  });
}
