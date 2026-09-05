import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:apptrack/src/controller/allController.dart';
import 'package:apptrack/src/service/configs/appColors.dart';
import 'package:apptrack/src/service/helpers/divider/cDivider.dart';
import 'package:apptrack/src/service/helpers/sizedBox.dart';
import 'package:apptrack/src/view/pages/home/tab/discovery/wifi/wifiDeviceDetailsPage.dart';

import 'package:apptrack/src/view/widgets/text/kText.dart';

class WifiWidget extends StatefulWidget {
  @override
  _WifiWidgetState createState() => _WifiWidgetState();
}

class _WifiWidgetState extends State<WifiWidget> {
  @override
  void initState() {
    super.initState();
    myDeviceC.getCurrentDeviceInfo();
    wifiC.getConnectedWifiDevices();
  }

  @override
  void dispose() {
    wifiC.scanSubscription?.cancel();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
      () => SizedBox(
        height: Get.height - 150,
        width: Get.width,
        child: RefreshIndicator(
          onRefresh: wifiC.getConnectedWifiDevices,
          child: ListView(
            shrinkWrap: true,
            primary: false,
            children: [
              Row(
                children: [
                  KText(
                    text: 'Devices (${wifiC.scannedDevices.length})',
                    fontWeight: FontWeight.bold,
                  ),
                  Spacer(),
                  IconButton(
                    onPressed: wifiC.getConnectedWifiDevices,
                    icon: Container(
                      decoration: BoxDecoration(
                        color: AppColors.cardGrey,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        child: Row(
                          children: [
                            Padding(
                              padding: EdgeInsets.only(left: 10),
                              child: KText(
                                text: 'Refresh ',
                                color: AppColors.lightBlue,
                              ),
                            ),
                            Icon(
                              Icons.refresh,
                              color: AppColors.lightBlue,
                              size: 15,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // Padding(
              //   padding: const EdgeInsets.all(16.0),
              //   child: _isScanning
              //       ? GestureDetector(
              //           onTap: _startScan,
              // child: CircularPercentIndicator(
              //   radius: 60.0,
              //   lineWidth: 8.0,
              //   percent: _scanProgress,
              //   center: KText(
              //       text: "${(_scanProgress * 100).toStringAsFixed(0)}%"),
              //   progressColor: Colors.green,
              // ),
              //         )
              //       : ElevatedButton(
              //           onPressed: _startScan,
              //           child: Text('Start Scan'),
              //         ),
              // ),
              if (wifiC.errorMessage.isNotEmpty)
                Padding(
                  padding: EdgeInsets.all(8.0),
                  child: KText(
                    text: wifiC.errorMessage.value,
                    color: Colors.red,
                    textAlign: TextAlign.center,
                  ),
                ),
              Card(
                color: AppColors.cardGrey,
                child: ListView.builder(
                  shrinkWrap: true,
                  primary: false,
                  itemCount: wifiC.scannedDevices.length,
                  itemBuilder: (context, index) {
                    final device = wifiC.scannedDevices[index];
                    return Column(
                      children: [
                        SizedBox(
                          height: 58,
                          child: ListTile(
                            onTap: () {
                              Get.to(
                                WifiDeviceDetailsPage(
                                  scannedDeviceInfo: device,
                                ),
                              );
                            },
                            shape: RoundedRectangleBorder(
                              borderRadius: index == 0
                                  ? BorderRadius.only(
                                      topLeft: Radius.circular(8),
                                      topRight: Radius.circular(8),
                                    )
                                  : index == wifiC.scannedDevices.length - 1
                                      ? BorderRadius.only(
                                          bottomLeft: Radius.circular(8),
                                          bottomRight: Radius.circular(8),
                                        )
                                      : BorderRadius.zero,
                            ),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 2,
                            ),
                            leading: wifiC.getDeviceIcon(device),
                            title: Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                KText(
                                  text: device.deviceName,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w400,
                                  textAlign: TextAlign.start,
                                ),
                                if (device.isMe || device.isGateway)
                                  Padding(
                                    padding: EdgeInsets.only(left: 10),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color:
                                            AppColors.lightBlue.withAlpha(50),
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                      child: Padding(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 5,
                                          vertical: 2,
                                        ),
                                        child: KText(
                                          text: device.isMe
                                              ? 'Me'
                                              : device.isGateway
                                                  ? 'Gateway'
                                                  : '',
                                          fontWeight: FontWeight.w500,
                                          fontSize: 10,
                                          color: AppColors.lightBlue,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: (device.manufacturer != null &&
                                    device.manufacturer!.isNotEmpty &&
                                    device.manufacturer !=
                                        'Unknown Router Brand')
                                ? KText(
                                    text: device.manufacturer!,
                                    fontSize: 11,
                                    color: AppColors.white54,
                                  )
                                : null,
                            trailing: SizedBox(
                              width: 120,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  KText(
                                    text: device.ipAddress +
                                        (device.pingTime != null
                                            ? ' (${device.pingTime!.inMilliseconds}ms)'
                                            : ''),
                                    color: AppColors.white54,
                                    fontSize: 12,
                                    textAlign: TextAlign.end,
                                  ),
                                  wSizedBox(5),
                                  Icon(
                                    Icons.arrow_forward_ios_outlined,
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Conditionally hide the divider for the last item
                        if (index <
                            wifiC.scannedDevices.length -
                                1) // <-- MODIFIED LINE
                          cDivider(),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
