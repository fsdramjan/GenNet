import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:apptrack/src/controller/allController.dart';
import 'package:apptrack/src/service/helpers/indicator/animatedScanIndicator.dart';
import 'package:apptrack/src/view/pages/home/tab/discovery/widgets/bluetoothWidget.dart';
import 'package:apptrack/src/view/pages/home/tab/discovery/widgets/wifiWidget.dart';
import 'package:apptrack/src/view/widgets/appBar/customAppBar.dart';
import 'package:apptrack/src/view/widgets/tab/tabWidget.dart';

class DiscoveryPage extends StatefulWidget {
  @override
  State<DiscoveryPage> createState() => _DiscoveryPageState();
}

class _DiscoveryPageState extends State<DiscoveryPage> {
  int selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: Size.fromHeight(60),
        child: customAppBar(),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Obx(
        () => AnimatedScanIndicator(
          text: selectedIndex == 1
              ? "Searching Bluetooth..."
              : "Searching Network...",
          scanProgress: selectedIndex == 1
              ? bluetoothC.scanProgress.value
              : wifiC.scanProgress.value,
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 20,
          ),
          child: Column(
            children: [
              customTabWidget(
                tabBoxHeight: 65,
                tabItem: [
                  TabItem(
                    iconPath: Icons.wifi,
                    label: 'Wifi',
                    index: 0,
                    selectedIndex: selectedIndex,
                    onTap: (val) {
                      setState(() {
                        selectedIndex =
                            val; // Update the selected index to 0 for Wifi tab
                      });
                    },
                  ),
                  TabItem(
                    iconPath: Icons.bluetooth,
                    label: 'Bluetooth',
                    index: 1,
                    selectedIndex: selectedIndex,
                    onTap: (val) {
                      setState(() {
                        selectedIndex =
                            val; // Update the selected index to 0 for Wifi tab
                      });
                    },
                  ),
                ],
              ),
              SizedBox(
                height: Get.height - 150,
                child: selectedIndex == 0 ? WifiWidget() : BluetoothWidget(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
