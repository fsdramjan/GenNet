import 'package:flutter/material.dart';
import 'package:apptrack/src/service/configs/appColors.dart';
import 'package:apptrack/src/service/helpers/hexColor.dart';
import 'package:apptrack/src/view/widgets/text/kText.dart';

Widget buildSpeedFactorCard({
  required String title,
  double? titleFontSize,
  String? status,
  Color? statusTextColor,
  required List<Map<String, String>> details,
  bool showWarning = false,
  bool showCheckmark = false,
  bool showInfo = false,
  Color? borderColor,
  EdgeInsetsGeometry? padding,
  isExpandedValueText = false,
}) {
  return Container(
    padding: padding ?? EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    decoration: BoxDecoration(
      border: Border.all(
        color: borderColor ?? AppColors.white54,
        width: .3,
      ),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            KText(
              text: title,
              color: AppColors.white,
              fontSize: titleFontSize,
              fontWeight: FontWeight.w500,
            ),
            Row(
              children: [
                if (status != null)
                  KText(
                    text: status,
                    color: statusTextColor ?? AppColors.white70,
                    fontSize: 14,
                  ),
                SizedBox(width: 4),
                if (showWarning)
                  Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.orange,
                    size: 20,
                  ),
                if (showCheckmark)
                  Icon(Icons.check_circle_outline,
                      color: Colors.green, size: 20),
                if (showInfo)
                  Icon(
                    Icons.info_outline,
                    color: AppColors.lightBlue2,
                    size: 20,
                  ),
              ],
            ),
          ],
        ),
        SizedBox(height: 10),
        Padding(
          padding: EdgeInsets.only(bottom: 4.0),
          child: Row(
              children: details.map((detail) {
            return Padding(
              padding: EdgeInsets.only(right: 10),
              child: Row(children: [
                KText(
                  text: detail['label']!,
                  color: AppColors.white,
                  fontSize: 13,
                ),
                SizedBox(width: 8),
                isExpandedValueText == true
                    ? Expanded(
                        child: KText(
                          text: detail['value']!,
                          color: detail['valueColor'] == null
                              ? AppColors.white70
                              : HexColor(detail['valueColor']!),
                          fontSize: 13,
                        ),
                      )
                    : KText(
                        text: detail['value']!,
                        color: detail['valueColor'] == null
                            ? AppColors.white70
                            : HexColor(detail['valueColor']!),
                        fontSize: 13,
                      ),
              ]),
            );
          }).toList()),
        ),
      ],
    ),
  );
}
