import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../service/configs/appColors.dart';

Widget backButton({
  void Function()? onTap,
  IconData? icon,
}) {
  return IconButton(
    onPressed: onTap ?? () => Get.back(),
    icon: Icon(
      icon ?? Icons.arrow_back_ios_new_outlined,
      color: AppColors.white54,
    ),
  );
}
