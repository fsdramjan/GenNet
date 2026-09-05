import 'package:flutter/material.dart';
import 'package:apptrack/src/service/configs/appColors.dart';
import 'package:apptrack/src/view/widgets/text/kText.dart';

Widget textButton({
  void Function()? onTap,
  String buttonText = '',
  IconData? icon,
  double? width,
}) {
  return IconButton(
    onPressed: onTap,
    icon: Container(
      width: width,
      decoration: BoxDecoration(
        color: AppColors.cardGrey,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 3,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            buttonText == ''
                ? SizedBox()
                : Padding(
                    padding: EdgeInsets.only(left: 10),
                    child: KText(
                      text: buttonText,
                      color: AppColors.lightBlue,
                    ),
                  ),
            icon == null
                ? SizedBox()
                : Icon(
                    Icons.refresh,
                    color: AppColors.lightBlue,
                    size: 15,
                  ),
          ],
        ),
      ),
    ),
  );
}
