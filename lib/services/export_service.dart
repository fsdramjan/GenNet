import 'dart:developer' as dev;
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/app_usage.dart';

class ExportService {
  Future<Directory> _exportDirectory() async {
    if (Platform.isAndroid) {
      final dir = await getExternalStorageDirectory();
      if (dir != null) {
        final exportDir = Directory('${dir.path}/exports');
        if (!await exportDir.exists()) {
          await exportDir.create(recursive: true);
        }
        return exportDir;
      }
    }

    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${dir.path}/exports');
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }
    return exportDir;
  }

  String _csv(String value) {
    final escaped = value.replaceAll('"', '""');
    return '"$escaped"';
  }

  Future<File> exportCsv(List<FlowEntry> entries) async {
    final dir = await _exportDirectory();
    final file = File(
      '${dir.path}/apptrack_flows_${DateTime.now().millisecondsSinceEpoch}.csv',
    );
    final buffer = StringBuffer(
      'destination_ip,port,protocol,ip_version,bytes\r\n',
    );
    for (final e in entries) {
      buffer.writeln(
        '${_csv(e.destinationIp)},${e.destinationPort},${_csv(e.protocol)},'
        '${e.ipVersion},${e.bytes}',
      );
    }
    return file.writeAsString(buffer.toString(), flush: true);
  }

  Future<File> exportTxt(List<FlowEntry> entries) async {
    final dir = await _exportDirectory();
    final file = File(
      '${dir.path}/apptrack_flows_${DateTime.now().millisecondsSinceEpoch}.txt',
    );
    final buffer = StringBuffer();
    buffer.writeln('AppTrack Local TUN Flow Export');
    buffer.writeln('Generated: ${DateTime.now().toIso8601String()}');
    buffer.writeln();
    buffer.writeln('Destination\tPort\tProtocol\tIP\tBytes');
    for (final e in entries) {
      buffer.writeln(
        '${e.destinationIp}\t${e.destinationPort}\t${e.protocol}\t'
        '${e.ipVersion}\t${FlowEntryBytes.human(e.bytes)}',
      );
    }
    return file.writeAsString(buffer.toString(), flush: true);
  }
}

class FlowEntryBytes {
  static String human(int bytes) => AppUsage.humanBytes(bytes);
}
