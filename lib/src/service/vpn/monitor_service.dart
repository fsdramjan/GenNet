import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/services.dart';

import '../../model/vpn/app_usage.dart';

class MonitorService {
  static const _methodChannel = MethodChannel('apptrack/monitor');

  static const _eventChannel = EventChannel('apptrack/monitor/events');

  StreamSubscription<dynamic>? _eventSub;

  final StreamController<List<FlowEntry>> _flowController =
      StreamController<List<FlowEntry>>.broadcast();

  DateTime? _sessionStart;

  Stream<List<FlowEntry>> get flowStream => _flowController.stream;

  DateTime? get sessionStart => _sessionStart;

  Future<List<AppInfo>> listInstalledApps() async {
    final result = await _methodChannel.invokeMethod<List<dynamic>>(
      'listInstalledApps',
    );

    return (result ?? [])
        .whereType<Map<dynamic, dynamic>>()
        .map(AppInfo.fromMap)
        .toList()
      ..sort(
        (a, b) => a.appName.toLowerCase().compareTo(
              b.appName.toLowerCase(),
            ),
      );
  }

  Future<String> start(
    List<String> packageNames,
  ) async {
    if (packageNames.isEmpty) {
      return 'empty';
    }

    await _eventSub?.cancel();

    _eventSub = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is! List) {
          return;
        }

        try {
          final flows = event
              .whereType<Map<dynamic, dynamic>>()
              .map(
                FlowEntry.fromMap,
              )
              .toList();

          _flowController.add(flows);
        } catch (e, stack) {
          dev.log(
            'Flow parse failed',
            name: 'MonitorService',
            error: e,
            stackTrace: stack,
          );
        }
      },
      onError: (
        Object error,
        StackTrace stack,
      ) {
        dev.log(
          'TUN stream error',
          name: 'MonitorService',
          error: error,
          stackTrace: stack,
        );

        _flowController.addError(
          error,
          stack,
        );
      },
    );

    final status = await _methodChannel.invokeMethod<String>(
      'startSession',
      {
        'packages': packageNames,
      },
    );

    if (status == 'started') {
      _sessionStart = DateTime.now();
    } else if (status != 'vpn_permission_required') {
      await _eventSub?.cancel();
      _eventSub = null;
    }

    return status ?? 'failed';
  }

  Future<void> stop() async {
    try {
      await _methodChannel.invokeMethod(
        'stopSession',
      );
    } finally {
      await _eventSub?.cancel();

      _eventSub = null;

      _sessionStart = null;

      _flowController.add([]);
    }
  }

  Future<bool> hasVpnPermission() async {
    return await _methodChannel.invokeMethod<bool>(
          'hasVpnPermission',
        ) ??
        false;
  }

  Future<void> openVpnPermission() async {
    await _methodChannel.invokeMethod(
      'openVpnPermission',
    );
  }

  /// Reads live RX/TX packet/byte counts straight from the device's
  /// TUN interface(s) via /proc/net/dev -- the same numbers `adb shell
  /// cat /proc/net/dev` would show, but callable in-app without a PC.
  ///
  /// Returns one map per tun interface found, e.g.:
  /// [{name: tun1, rxBytes: 0, rxPackets: 0, txBytes: 0, txPackets: 0}]
  Future<List<Map<String, dynamic>>> getTunStats() async {
    final result = await _methodChannel.invokeMethod<List<dynamic>>(
      'getTunStats',
    );

    return (result ?? [])
        .whereType<Map<dynamic, dynamic>>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> dispose() async {
    await _eventSub?.cancel();

    _eventSub = null;

    await _flowController.close();
  }

  /// Overlay (floating PIP-style panel showing live traffic on top of
  /// other apps, similar to Reqable's debug panel).
  Future<bool> hasOverlayPermission() async {
    return await _methodChannel.invokeMethod<bool>(
          'hasOverlayPermission',
        ) ??
        false;
  }

  Future<void> openOverlayPermission() async {
    await _methodChannel.invokeMethod(
      'openOverlayPermission',
    );
  }

  /// Returns true if started, throws a PlatformException with code
  /// 'OVERLAY_PERMISSION_REQUIRED' if the permission isn't granted yet.
  Future<void> startOverlay() async {
    await _methodChannel.invokeMethod(
      'startOverlay',
    );
  }

  Future<void> stopOverlay() async {
    await _methodChannel.invokeMethod(
      'stopOverlay',
    );
  }
}
