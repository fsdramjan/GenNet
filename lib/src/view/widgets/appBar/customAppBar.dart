import 'package:flutter/material.dart';
import 'package:apptrack/src/service/configs/appColors.dart';
import 'package:apptrack/src/service/helpers/sizedBox.dart';

Widget customAppBar() {
  return AppBar(
    elevation: 0,
    surfaceTintColor: AppColors.backgroundColor,
    title: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        CircleAvatar(
          backgroundColor: AppColors.backgroundColor,
          radius: 15,
          child: CircleAvatar(
            backgroundColor: AppColors.white,
            radius: 14,
            child: Icon(
              Icons.person_rounded,
              color: AppColors.backgroundColor,
              size: 35,
            ),
          ),
        ),
        Row(
          children: [
            Icon(
              Icons.wifi_rounded,
              color: AppColors.lightGreen,
            ),
            wSizedBox(5),
            Text(
              'Fsd Ramjan',
              style: TextStyle(
                color: AppColors.white,
              ),
            ),
          ],
        ),
        SizedBox(),
      ],
    ),
  );
}
