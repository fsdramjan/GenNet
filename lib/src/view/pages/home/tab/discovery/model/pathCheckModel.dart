enum PathStatus { ok, warning, failed }

class PathCheckItemModel {
  final String title;
  final String subtitle;
  final String value;
  final PathStatus status;

  PathCheckItemModel({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.status,
  });
}
