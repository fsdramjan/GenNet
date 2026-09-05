// import 'package:flutter/material.dart';
// import 'app.dart';

// void main() {
//   WidgetsFlutterBinding.ensureInitialized();
//   runApp(const AppTrackApp());
// }

import 'package:apptrack/src/service/configs/appTheme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart'; // get
import 'package:apptrack/src/view/pages/home/homePage.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized(); // ensure initialized

  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
  )); // status bar color and icon brightness
  runApp(MyApp()); // run app
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      theme: AppTheme().appTheme, // app theme
      home: HomePage(), // home page
    );
  }
}
