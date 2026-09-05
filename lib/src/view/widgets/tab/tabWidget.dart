import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:apptrack/src/service/configs/appColors.dart';
import 'package:apptrack/src/view/widgets/text/kText.dart';

// ignore: must_be_immutable
class customTabWidget extends StatelessWidget {
  List<TabItem> tabItem = [];

  ///initial height of the tab box is 50
  double? tabBoxHeight;

  customTabWidget({
    this.tabBoxHeight,
    required this.tabItem,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: tabBoxHeight ?? 50,
      decoration: BoxDecoration(
        color: AppColors.cardGrey,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: EdgeInsets.all(5),
        child: Row(
          children: tabItem,
        ),
      ),
    );
  }
}

class TabItem extends StatelessWidget {
  final IconData iconPath;
  final String label;
  final int index;
  final int selectedIndex;
  final ValueChanged<int> onTap; // Callback for when this tab is tapped

  const TabItem({
    Key? key,
    required this.iconPath,
    required this.label,
    required this.index,
    required this.selectedIndex,
    required this.onTap,
  }) : super(key: key);

  bool get isSelected => index == selectedIndex;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        width: Get.width,
        decoration: isSelected
            ? BoxDecoration(
                color: AppColors.backgroundColor,
                borderRadius: BorderRadius.circular(8),
              )
            : null,
        child: InkWell(
          onTap: () => onTap(index),
          child: Padding(
            padding: EdgeInsets.all(3),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  iconPath,
                  color: isSelected ? AppColors.lightBlue : AppColors.white54,
                  size: 25,
                ),
                SizedBox(width: 8),
                KText(
                  text: label,
                  color: isSelected ? AppColors.lightBlue : AppColors.white54,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
