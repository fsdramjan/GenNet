import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:apptrack/src/controller/allController.dart';
import 'package:apptrack/src/service/configs/appColors.dart';
import 'package:apptrack/src/service/helpers/divider/cDivider.dart';
import 'package:apptrack/src/service/helpers/sizedBox.dart';
import 'package:apptrack/src/view/pages/home/tab/discovery/model/scannedDeviceModel.dart';
import 'package:apptrack/src/view/widgets/button/backButton.dart';
import 'package:apptrack/src/view/widgets/button/textButton.dart';
import 'package:apptrack/src/view/widgets/card/customCard.dart';
import 'package:apptrack/src/view/widgets/text/kText.dart';

class WifiDeviceDetailsPage extends StatefulWidget {
  final ScannedDevice scannedDeviceInfo;

  WifiDeviceDetailsPage({
    required this.scannedDeviceInfo,
  });
  @override
  _WifiDeviceDetailsPageState createState() => _WifiDeviceDetailsPageState();
}

class _WifiDeviceDetailsPageState extends State<WifiDeviceDetailsPage> {
  @override
  void initState() {
    super.initState();
    myDeviceC.getCurrentDeviceInfo();
  }

  Widget buildInfoRow(
    String label,
    String? value, {
    void Function()? onTap,
    Color? valueColor,
  }) {
    return ListTile(
      title: KText(
        text: label,
        // fontWeight: FontWeight.bold,
      ),
      trailing: onTap != null
          ? InkWell(
              onTap: onTap,
              radius: 100,
              child: KText(
                text: "  $value",
                fontWeight: FontWeight.w500,
                color: AppColors.lightBlue,
              ),
            )
          : KText(
              text: value ?? 'N/A',
              fontWeight: FontWeight.w500,
              color: valueColor ?? AppColors.white54,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: backButton(),
        title: KText(
          text: myDeviceC.myDeviceInfo.value.deviceName ==
                  widget.scannedDeviceInfo.deviceName
              ? 'Me'
              : widget.scannedDeviceInfo.deviceName,
          fontWeight: FontWeight.w500,
          fontSize: 16,
        ),
        centerTitle: true,
      ),
      body: Obx(
        () => myDeviceC.myDeviceInfo.value == ''
            ? KText(text: 'No Data')
            : ListView(
                padding: EdgeInsets.all(16),
                children: [
                  Column(
                    children: [
                      wifiC.getDeviceIcon(
                        widget.scannedDeviceInfo,
                        size: 100,
                      ),
                      SizedBox(height: 10),
                      KText(
                        text: myDeviceC.myDeviceInfo.value.deviceName ?? '',
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      KText(
                        text: myDeviceC.myDeviceInfo.value.manufacturer +
                                ' ' +
                                myDeviceC.myDeviceInfo.value.model ??
                            '',
                      ),
                      hSizedBox(10),
                      if (widget.scannedDeviceInfo.isMe ||
                          widget.scannedDeviceInfo.isGateway)
                        Padding(
                          padding: EdgeInsets.only(left: 10),
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.lightBlue.withAlpha(50),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              child: KText(
                                text: widget.scannedDeviceInfo.isMe
                                    ? 'Me'
                                    : widget.scannedDeviceInfo.isGateway
                                        ? 'Gateway'
                                        : '',
                                fontWeight: FontWeight.w500,
                                fontSize: 10,
                                color: AppColors.lightBlue,
                              ),
                            ),
                          ),
                        ),
                      hSizedBox(5),
                      customCard(
                        child: Column(
                          children: [
                            buildInfoRow(
                                'Model', myDeviceC.myDeviceInfo.value.model),
                            cDivider(),
                            buildInfoRow(
                              'Manufacturer',
                              myDeviceC.myDeviceInfo.value.manufacturer,
                            ),
                            cDivider(),
                            buildInfoRow(
                              'Device Type',
                              myDeviceC.myDeviceInfo.value.deviceType,
                            ),
                            cDivider(),
                            buildInfoRow(
                              'Firmware Version',
                              myDeviceC.myDeviceInfo.value.firmwareVersion,
                            ),
                            cDivider(),
                            buildInfoRow(
                              'Uptime',
                              myDeviceC.myDeviceInfo.value.uptime,
                            ),
                          ],
                        ),
                      ),
                      hSizedBox(20),
                      Padding(
                        padding: EdgeInsets.only(left: 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: KText(
                            text: 'Network',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      customCard(
                        child: Column(
                          children: [
                            buildInfoRow(
                              'IP Address',
                              myDeviceC.myDeviceInfo.value.ipAddress,
                            ),
                            cDivider(),
                            buildInfoRow(
                              'Gateway',
                              myDeviceC.myDeviceInfo.value.gateway,
                              onTap: () {},
                            ),
                            cDivider(),
                            buildInfoRow(
                              'DNS Server',
                              myDeviceC.myDeviceInfo.value.dnsServer,
                              onTap: () {},
                            ),
                          ],
                        ),
                      ),
                      hSizedBox(20),
                      Padding(
                        padding: EdgeInsets.only(left: 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: KText(
                            text: 'Cellular',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      customCard(
                        child: Column(
                          children: [
                            buildInfoRow(
                              'Signal',
                              myDeviceC.myDeviceInfo.value.signal + ' dBm',
                              valueColor: AppColors.oliveGreen,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}
