import 'package:flutter/material.dart';
import 'package:apptrack/src/service/configs/appColors.dart';
import 'package:apptrack/src/view/widgets/button/primaryButton.dart';
import 'package:apptrack/src/view/widgets/text/kText.dart';

Widget buildSpeedTestSection() {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Speed Test',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          TextButton(
            onPressed: () {},
            child: Text(
              'All Results',
              style: TextStyle(
                color: AppColors.lightBlue2,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
      primaryButton(
        backgroundColor: AppColors.lightBlue,
        child: KText(
          text: 'Start Speed Test',
          // fontSize: 12,
        ),
      ),
      SizedBox(height: 10),
      primaryButton(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.adjust,
              color: AppColors.lightBlue,
              size: 20,
            ),
            SizedBox(width: 8),
            KText(
              text: 'Auto Server Detection',
              fontSize: 12,
            ),
          ],
        ),
      ),
    ],
  );
}
