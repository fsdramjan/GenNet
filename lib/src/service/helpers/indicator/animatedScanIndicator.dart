import 'dart:async';
import 'package:flutter/material.dart';
import 'package:apptrack/src/service/configs/appColors.dart';
import 'package:apptrack/src/view/widgets/text/kText.dart';

class AnimatedScanIndicator extends StatefulWidget {
  final double scanProgress; // 0.0 to 1.0
  final String text;

  const AnimatedScanIndicator({
    super.key,
    required this.scanProgress,
    this.text = "Searching Network...",
  });

  @override
  State<AnimatedScanIndicator> createState() => _AnimatedScanIndicatorState();
}

class _AnimatedScanIndicatorState extends State<AnimatedScanIndicator> {
  bool _visible = true;
  Timer? _hideTimer;
  double _lastProgress = 0.0;

  @override
  void didUpdateWidget(covariant AnimatedScanIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);

    // If progress just completed
    if (widget.scanProgress >= 1.0 && _lastProgress < 1.0) {
      _hideTimer?.cancel();
      _hideTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _visible = false);
      });
    }

    // If scan restarted
    if (widget.scanProgress < 1.0 && _lastProgress >= 1.0) {
      _hideTimer?.cancel();
      setState(() => _visible = true);
    }

    _lastProgress = widget.scanProgress;
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    final isCompleted = widget.scanProgress >= 1.0;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: _visible ? 1.0 : 0.0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.cardGrey,
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            isCompleted
                ? Icon(Icons.check, color: AppColors.greenAccent, size: 20)
                : SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      value: widget.scanProgress,
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(AppColors.lightBlue),
                      backgroundColor: AppColors.white24,
                    ),
                  ),
            const SizedBox(width: 12),
            KText(
              text: isCompleted ? "Scan Complete" : widget.text,
              color: Colors.white70,
              fontSize: 14,
            ),
          ],
        ),
      ),
    );
  }
}
