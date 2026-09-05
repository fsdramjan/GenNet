// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:dart_ping/dart_ping.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:apptrack/src/service/configs/appColors.dart';
import 'package:apptrack/src/service/helpers/sizedBox.dart';
import 'dart:async';

import 'package:apptrack/src/view/widgets/text/kText.dart';

class SocialNetworkLatency extends StatefulWidget {
  @override
  _SocialNetworkLatencyState createState() => _SocialNetworkLatencyState();
}

class _SocialNetworkLatencyState extends State<SocialNetworkLatency> {
  String _googleLatency = '... ms';
  String _facebookLatency = '... ms';
  String _xcomLatency = '... ms';
  String _gatewayLatency = '... ms';

  Timer? _latencyTimer;

  @override
  void initState() {
    super.initState();
    _startLatencyMonitoring();
  }

  @override
  void dispose() {
    _latencyTimer?.cancel();
    super.dispose();
  }

  void _startLatencyMonitoring() {
    // Initial fetches
    _fetchLatency(
        'google.com', (latency) => setState(() => _googleLatency = latency));
    _fetchLatency('facebook.com',
        (latency) => setState(() => _facebookLatency = latency));
    _fetchLatency('x.com', (latency) => setState(() => _xcomLatency = latency));
    _fetchGatewayLatency(
        (latency) => setState(() => _gatewayLatency = latency));

    // Optional: Refresh every X seconds
    _latencyTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      _fetchLatency(
        'google.com',
        (latency) => setState(
          () => _googleLatency = latency,
        ),
      );
      _fetchLatency(
        'facebook.com',
        (latency) => setState(
          () => _facebookLatency = latency,
        ),
      );
      _fetchLatency(
        'x.com',
        (latency) => setState(
          () => _xcomLatency = latency,
        ),
      );
      _fetchGatewayLatency(
        (latency) => setState(
          () => _gatewayLatency = latency,
        ),
      );
    });
  }

  Future<void> _fetchLatency(String host, Function(String) updateState) async {
    try {
      final ping = Ping(host, count: 1, timeout: 2); // Ping once, 2 sec timeout

      await for (var pingData in ping.stream) {
        if (pingData.response != null && pingData.response!.time != null) {
          updateState('${pingData.response!.time!.inMilliseconds} ms');
          return; // Stop after first successful ping
        } else if (pingData.error != null) {
          print('Ping error for $host: ${pingData.error?.error}');
          updateState('Error'); // Or a more specific error message
          return;
        }
      }
      updateState('Timed out'); // If stream completes without successful ping
    } catch (e) {
      print('Exception pinging $host: $e');
      updateState('Error');
    }
  }

  Future<void> _fetchGatewayLatency(Function(String) updateState) async {
    String? gatewayIp;
    try {
      final NetworkInfo networkInfo = NetworkInfo();
      gatewayIp = await networkInfo.getWifiGatewayIP();
    } catch (e) {
      print("Could not get gateway IP: $e");
    }

    if (gatewayIp == null || gatewayIp.isEmpty) {
      // Check for empty string as well
      updateState('N/A (Gateway)');
      return;
    }

    try {
      final ping = Ping(gatewayIp, count: 1, timeout: 2);
      await for (var pingData in ping.stream) {
        if (pingData.response != null && pingData.response!.time != null) {
          updateState('${pingData.response!.time!.inMilliseconds} ms');
          return;
        } else if (pingData.error != null) {
          print(
              'Ping error for Gateway ($gatewayIp): ${pingData.error?.error}');
          updateState('Error');
          return;
        }
      }
      updateState('Timed out');
    } catch (e) {
      print('Exception pinging Gateway ($gatewayIp): $e');
      updateState('Error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return

        // Network Latency
        _buildNetworkLatencySection();
  }

  // MODIFIED _buildNetworkLatencySection
  Widget _buildNetworkLatencySection() {
    return Container(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                KText(
                  text: 'Network Latency',
                  color: AppColors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 18),
              ],
            ),
          ),
          SizedBox(height: 16), // Spacing between title and items
          _buildLatencyItemsRow(),
        ],
      ),
    );
  }

  Widget _buildLatencyItemsRow() {
    return Row(
      // mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildLatencyItem(
          iconPath: 'assets/icons/google.png',
          label: 'google.co...',
          latencyMs: _googleLatency,
        ),
        wSizedBox(10),
        _buildLatencyItem(
          iconPath: 'assets/icons/facebook.png',
          label: 'facebook....',
          latencyMs: _facebookLatency,
        ),
        wSizedBox(10),
        _buildLatencyItem(
          iconPath: 'assets/icons/x.png',
          label: 'x.com',
          latencyMs: _xcomLatency,
        ),
        wSizedBox(10),
        _buildLatencyItem(
          iconPath: 'assets/icons/gateway.png',
          label: 'Gateway',
          latencyMs: _gatewayLatency,
        ),
      ],
    );
  }

  Widget _buildLatencyItem({
    required String iconPath,
    required String label,
    required String latencyMs,
  }) {
    Color latencyColor = Colors.white;
    if (latencyMs.contains('ms') && !latencyMs.contains('...')) {
      final ms = int.tryParse(latencyMs.replaceAll(' ms', '')) ?? 0;
      if (ms > 200) {
        latencyColor = Colors.red;
      } else if (ms > 50) {
        latencyColor = Colors.orange;
      } else if (ms > 0) {
        // Only green if it's a positive measurement
        latencyColor = Colors.green;
      }
    }

    return SizedBox(
      width: 50,
      child: Column(
        children: [
          Container(
            width: 45,
            height: 45,
            padding: EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.cardGrey,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  spreadRadius: 1,
                  blurRadius: 3,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Image.asset(
                iconPath,
                // height: 40,
                // width: 40,
                color: label.contains('Gateway') ? AppColors.white : null,
              ),
            ),
          ),
          SizedBox(height: 8),
          KText(
            text: label,
            color: Colors.white70,
            fontSize: 12,
            maxLines: 1,
          ),
          // SizedBox(height: 4),
          KText(
            text: latencyMs,
            fontSize: 12,
            color: latencyColor,
          ),
        ],
      ),
    );
  }
}
