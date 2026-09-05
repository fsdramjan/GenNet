import 'package:apptrack/src/service/configs/appColors.dart';
import 'package:apptrack/src/view/pages/vpn/vpnPage.dart';
import 'package:flutter/material.dart';
import 'package:apptrack/src/view/pages/home/tab/discovery/discoveryPage.dart';
import 'package:apptrack/src/view/pages/home/tab/signal/signalPage.dart';
import 'package:apptrack/src/view/pages/home/tab/speed/speedPage.dart';

class HomePage extends StatefulWidget {
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedPageIndex = 0;

  List<Widget> allPages = [
    SpeedPage(),
    SignalPage(),
    // SignalPage(),
    VpnPage(),
    DiscoveryPage(),
    SignalPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: allPages[_selectedPageIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedPageIndex,
        onTap: (index) {
          setState(() {
            _selectedPageIndex = index;
          });
        },
        backgroundColor: AppColors.backgroundColor,
        selectedItemColor: AppColors.lightBlue,
        unselectedItemColor: AppColors.white54, // Inactive icon color

        type: BottomNavigationBarType.fixed, // To show all labels
        selectedFontSize: 13,
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.signal_cellular_alt),
            label: 'Signal',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.podcasts_rounded),
            label: 'IP Tracker',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.travel_explore),
            label: 'Discovery',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.telegram),
            label: 'Teleport',
          ),
        ],
      ),
    );
  }
}
