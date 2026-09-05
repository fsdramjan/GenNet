import 'package:flutter/material.dart';
import 'package:apptrack/src/service/configs/appColors.dart';

class AppTheme {
  final appTheme = ThemeData(
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.backgroundColor,
      iconTheme: IconThemeData(
        color: Colors.white,
        size: 20,
      ),
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontSize: 14,
        fontWeight: FontWeight.bold,
      ),
    ),
    scaffoldBackgroundColor: AppColors.backgroundColor,
  );
}
