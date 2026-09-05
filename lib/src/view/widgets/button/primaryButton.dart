import 'package:flutter/material.dart';
import 'package:apptrack/src/service/configs/appColors.dart';
import 'package:apptrack/src/view/widgets/text/kText.dart';

Widget primaryButton({
  Widget? child,
  VoidCallback? onPressed,
  Color? backgroundColor,
  double? width,
  double? height,
  double? borderRadius,
  String? tooltip,
  String? text,
  Color? textColor,
  double? fontSize,
}) {
  return SizedBox(
    width: width ?? double.infinity,
    height: height ?? 40,
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: backgroundColor ?? AppColors.cardGrey,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(borderRadius ?? 8.0),
        ),
      ),
      onPressed: onPressed ?? () {},
      child: child ??
          KText(
            text: text,
            fontSize: fontSize,
            color: textColor,
          ),
    ),
  );
}
