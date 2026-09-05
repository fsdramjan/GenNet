import 'package:flutter/material.dart';
import 'package:apptrack/src/service/configs/appColors.dart';

class KText extends StatelessWidget {
  final String? text;
  final Color? color;
  final double? fontSize;

  final String? fontFamily;
  final int? maxLines;
  final FontWeight? fontWeight;
  final TextAlign? textAlign;
  final double? wordSpacing;

  final TextDirection? textDirection;
  final TextDecoration? decoration;

  const KText({
    super.key,
    required this.text,
    this.color,
    this.fontSize,
    this.fontFamily,
    this.maxLines,
    this.fontWeight,
    this.textAlign,
    this.textDirection,
    this.wordSpacing,
    this.decoration,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      '$text',
      style: TextStyle(
        decoration: decoration,
        fontSize: fontSize ?? 14,
        fontWeight: fontWeight ?? FontWeight.normal,
        color: color ?? AppColors.white,
        wordSpacing: wordSpacing,
      ),
      maxLines: maxLines,
      textAlign: TextAlign.justify,
      textDirection: textDirection,
      overflow: TextOverflow.ellipsis,
    );
  }
}
