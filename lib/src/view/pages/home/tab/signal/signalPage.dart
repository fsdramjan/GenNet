import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:apptrack/src/service/configs/appColors.dart';
import 'package:apptrack/src/view/pages/home/tab/signal/widgets/signalStrength.dart';
import 'package:apptrack/src/view/widgets/appBar/customAppBar.dart';
import 'package:apptrack/src/view/widgets/text/kText.dart';

class SignalPage extends StatefulWidget {
  @override
  _SignalPageState createState() => _SignalPageState();
}

class _SignalPageState extends State<SignalPage>
    with SingleTickerProviderStateMixin {
  //first tab signal strength and Floor Plan
  int _firstSelectedTabIndex = 0; // 0: Signal Strength, 1: Floor Plan

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(60.0),
        child: customAppBar(),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTopTabs(),
              SizedBox(height: 16),
              _firstSelectedTabIndex == 0 ? SignalStrengthTab() : SizedBox(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopTabs() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardGrey,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: EdgeInsets.all(5),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 70,
                width: Get.width,
                padding: EdgeInsets.symmetric(vertical: 12),
                decoration: _firstSelectedTabIndex == 0
                    ? BoxDecoration(
                        color: AppColors.backgroundColor,
                        borderRadius: BorderRadius.circular(8),
                      )
                    : null,
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _firstSelectedTabIndex = 0; // Signal Strength
                    });
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Icon(
                      //   Icons.stacked_bar_chart_sharp,
                      //   color: _firstSelectedTabIndex == 0
                      //       ? AppColors.lightBlue
                      //       : AppColors.white54,
                      //   size: 20,
                      // ),
                      Image.asset(
                        'assets/icons/signal_strength.png',
                        color: _firstSelectedTabIndex == 0
                            ? AppColors.lightBlue
                            : AppColors.white54,
                        height: 25,
                      ),
                      SizedBox(width: 8),
                      KText(
                        text: 'Signal Strength',
                        color: _firstSelectedTabIndex == 0
                            ? AppColors.lightBlue
                            : AppColors.white54,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Container(
                height: 70,
                width: Get.width,
                padding: EdgeInsets.symmetric(vertical: 12),
                decoration: _firstSelectedTabIndex == 1
                    ? BoxDecoration(
                        color: AppColors.backgroundColor,
                        borderRadius: BorderRadius.circular(8),
                      )
                    : null,
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _firstSelectedTabIndex = 1; // Floor Plan
                    });
                  },
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/icons/stacks_icon.png',
                        color: _firstSelectedTabIndex == 1
                            ? AppColors.lightBlue
                            : AppColors.white54,
                        height: 25,
                      ),
                      // Icon(
                      //   Icons.stacked_bar_chart_sharp,
                      // color: _firstSelectedTabIndex == 1
                      //     ? AppColors.lightBlue
                      //     : AppColors.white54,
                      // size: 20,
                      // ),
                      SizedBox(width: 8),
                      KText(
                        text: 'Floor Plan',
                        color: _firstSelectedTabIndex == 1
                            ? AppColors.lightBlue
                            : AppColors.white54,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
