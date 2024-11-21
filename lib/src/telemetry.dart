import 'dart:async';

import 'package:intl/intl.dart';
import 'package:logging/logging.dart';
import 'package:logging_appenders/logging_appenders.dart';

class Telemetry {
  static Timer? timer;
  static final Map<String, SpanInfo> spanTree = {};
  static final DateFormat dateFormat = DateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'");
  static String? appName;
  static String? platform;
  static String? systemName;
  static String? baseUrl;
  static String? storeId;
  static String? storeName;
  static String? terminalCode;
  static String? username;

  static Future<void> sendMetricEvent(
    String name, 
    SpanInfo spanInfo, 
    {bool isStop = false, 
    String? status,
  }) async {
    final lokiAppender = LokiApiAppender(
      server: '172.208.58.149:3100',
      username: 'admin',
      password: 'admin',
      labels: {
        'app': appName ?? '',
        'system': systemName ?? '',
        'terminal': terminalCode ?? '',
        'username': username  ?? '',
        'storeId': storeId ?? '',
        'storeName': storeName ?? '',
        'platform': platform ?? '',
      },
    );

    lokiAppender.log(
      Level.FINE,
      DateTime.now(),
      name,
      {
        'startTime': spanInfo.startTime,
        if (isStop) 
          'stopTime': spanInfo.stopTime ?? '',
          'duration': '${DateTime.parse(spanInfo.stopTime!)
              .difference(DateTime.parse(spanInfo.startTime)).inMilliseconds}',
          'status': '$status',
      }
    );
  }

   static Future<void> startSpan(String spanName) async {
    if (spanName.isNotEmpty) {
      final startTime = dateFormat.format(DateTime.now().toUtc());
      final spanInfo = SpanInfo(startTime: startTime);
      spanTree[spanName] = spanInfo;
      await Telemetry.sendMetricEvent(spanName, spanInfo);
    } else {
      return print('SpanName cannot be empty');
    }
    
  }

  static Future<void> stopSpan(String spanName, String status) async {
    if (spanName.isNotEmpty) {
      final spanInfo = spanTree[spanName];
      final stopTime = dateFormat.format(DateTime.now().toUtc());
      spanInfo!.stopTime = stopTime;
      await Telemetry.sendMetricEvent(spanName, spanInfo, isStop: true, status: status);
      spanTree.remove(spanName);
    } else {
      return print('spanName cannot be empty');
    }

  }
}

class SpanInfo {
  String startTime;
  String? stopTime;

  SpanInfo({required this.startTime});
}