import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:apptrack/src/controller/allController.dart';
import 'package:apptrack/src/service/configs/appColors.dart';

Widget buildNetworkFlowDiagram() {
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceAround,
    children: [
      _buildNetworkNode(
        icon: Icons.public,
        title: 'RSM Network',
        subtitle: '103.149.72.90',
        status: 'Available',
        statusColor: Colors.green,
      ),
      Icon(
        Icons.arrow_forward_ios,
        color: AppColors.lightGreen,
        size: 20,
      ),
      _buildNetworkNode(
        icon: Icons.router,
        title: 'Access Point',
      ),
      Icon(
        Icons.arrow_forward_ios,
        color: AppColors.lightGreen,
        size: 20,
      ),
      Obx(
        () => _buildNetworkNode(
          iconWidget: Image.asset(
            'assets/icons/device.png',
            height: 40,
            width: 40,
          ), // Placeholder for custom image
          title: myDeviceC.myDeviceInfo.value.deviceName ?? 'Unknown Device',
          subtitle: myDeviceC.myDeviceInfo.value.ipAddress,
        ),
      ),
    ],
  );
}

Widget _buildNetworkNode({
  IconData? icon,
  Widget? iconWidget,
  required String title,
  String? subtitle,
  String? status,
  Color? statusColor,
}) {
  return Column(
    children: [
      if (iconWidget != null)
        iconWidget
      else
        Icon(icon, color: AppColors.white, size: 40),
      SizedBox(height: 8),
      Text(title, style: TextStyle(color: AppColors.white, fontSize: 14)),
      if (subtitle != null)
        Text(subtitle,
            style: TextStyle(color: AppColors.white70, fontSize: 12)),
      if (status != null)
        Text(status,
            style: TextStyle(
                color: statusColor ?? AppColors.white70, fontSize: 12)),
    ],
  );
}
