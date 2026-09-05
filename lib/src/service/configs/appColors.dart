import 'package:flutter/material.dart';
import 'package:apptrack/src/service/helpers/hexColor.dart';

class AppColors {
  static final transparent = Colors.transparent;
  static final backgroundColor = Color(0xFF0F1013);
  // static final backgroundColor = HexColor('#1d1e22');

  static final lightGreen = HexColor('#51ac70');
  static final greenAccent = Colors.greenAccent;
  static final green = Colors.green;

  static final lightBlue = HexColor('#4897fe');
  static final lightGrey = HexColor('#282b30');
  static final cardGrey = const Color.fromARGB(255, 39, 39, 39);
  static final lightBlue2 = HexColor('#5183c1');
  //
  static final white = HexColor('#ffffff');
  static final white24 = Colors.white24;
  static final white54 = Colors.white54;
  static final white70 = Colors.white70;
  //

  static final black = HexColor('#000000');

  static final border = Colors.white24;

  //
  static final orange = HexColor('#FFA500');
  static final red50 = HexColor('#b56161');

  static var oliveGreen = HexColor('#768632');
  static var red = Colors.red;

  // ── Added for Speed page (GenNet-style UI) ─────────────
  static final subText = HexColor('#8E8E93'); // secondary/grey text
  static final textMuted = HexColor('#636366'); // timestamps, faint text
  static final line = HexColor('#2E2E30'); // card borders / dividers
  static final cardBg = HexColor('#1C1C1E'); // card background
  static final cardBg2 = HexColor('#2A2A2C'); // nested card / progress track
  static final amberBg = HexColor('#F5A524'); // warning/fair status
  static final blueBg = HexColor('#4A90FF'); // primary blue buttons

  static final sheetHandle = HexColor('#48484A'); // drag handle bar

  static final chipBlueBg = HexColor('#223555');
  static final chipBlueText = HexColor('#6B9CFA');
}
