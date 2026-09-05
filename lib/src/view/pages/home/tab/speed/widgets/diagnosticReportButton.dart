import 'package:flutter/material.dart';
import 'package:apptrack/src/service/configs/appColors.dart';

class DiagnosticReportButton extends StatelessWidget {
  final void Function()? onTap;
  final bool isDone;
  final bool isLoading;
  final String? step;
  final double? progress;

  const DiagnosticReportButton({
    super.key,
    required this.onTap,
    this.isDone = false,
    this.isLoading = false,
    required this.step,
    required this.progress,
  });
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
              color: AppColors.chipBlueText,
              borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              SizedBox(
                  width: 16,
                  height: 16,
                  child: !isLoading
                      ? Icon(Icons.check_circle_outline,
                          size: 18, color: AppColors.white)
                      : const CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white)),
              const SizedBox(width: 5),
              Text(isLoading ? 'Running' : 'Run',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ]),
            const SizedBox(height: 4),
            Text(step.toString(),
                style: const TextStyle(color: Colors.white70, fontSize: 12)),
          ]),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.cardBg2,
              color: AppColors.chipBlueText,
              minHeight: 3),
        ),
      ]),
    );
  }
}
