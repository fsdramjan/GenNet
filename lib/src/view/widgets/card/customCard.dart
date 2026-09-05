import 'package:flutter/material.dart';
import 'package:apptrack/src/service/configs/appColors.dart';

Widget customCard({
  Widget? child,
  VoidCallback? onTap,
  Color? backgroundColor,
  double? width,
  double? height,
  double? borderRadius,
  String? tooltip = '',
}) {
  return Tooltip(
    message: tooltip,
    child: SizedBox(
      height: height,
      width: width,
      child: Card(
        color: backgroundColor ?? AppColors.cardGrey,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius ?? 8.0),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius ?? 8.0),
          child: child,
        ),
      ),
    ),
  );
}
