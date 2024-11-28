// ignore_for_file: deprecated_member_use, avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:log/src/telemetry/metric_appender.dart';
import 'package:log/src/telemetry/rotate_metrics.dart';
import 'package:logging/logging.dart';
import 'package:logging_appenders/base_remote_appender.dart';
import 'package:logging_appenders/logging_appenders.dart';
import 'package:path_provider/path_provider.dart';

class Metric {
  static late MetricAppender metricAppender;
  static late RotatingFileAppender fileAppender;
  static final Map<String, SpanInfo> spanTree = {};
  static Timer? timer;
  static String? appName;
  static String? platform;
  static String? systemName;
  static String? baseUrl;
  static String? storeId;
  static String? storeName;
  static String? terminalCode;
  static String? username;
  static bool consoleMetric = false;

  static Future<void> initFile() async {
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((record) {
      if (consoleMetric) print('${record.level.name}: ${record.time.toUtc()} ${record.message}');
    });
    final dir = await getApplicationSupportDirectory();
    final dirPath = '${dir.path}/metrics';
    final metricDir = Directory(dirPath);
    if (!await metricDir.exists()) {
      await metricDir.create(recursive: true);
    }

    final metricPath = '$dirPath/app_metrics';

    fileAppender = RotatingFileAppender(
      baseFilePath: metricPath,
      rotateCheckInterval: const Duration(seconds: 5),
    );

    metricAppender = MetricAppender(
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
  }

  static Future<void> sendMetricEvent(
    String name, 
    SpanInfo spanInfo, 
    {bool stop = false, 
    String? status,
  }) async {
    final startTime = spanInfo.startTime;
    final stopTime = spanInfo.stopTime;

    final metricPayload = <String, dynamic>{
      'type': 'start_span',
      'event': name,
      'startTime': '$startTime',
    };

    try {
      if (stop && stopTime != null ) {
        final duration = stopTime.difference(startTime);

        int durationValue;
        String durationUnit;
        if (duration.inMilliseconds < 1000) {
          durationValue = duration.inMilliseconds;
          durationUnit = 'ms';
        } else if (duration.inSeconds < 60) {
          durationValue = duration.inSeconds;
          durationUnit = durationValue == 1 ? 'sec' : 'secs';
        } else if (duration.inMinutes < 60) {
          durationValue = duration.inMinutes;
          durationUnit = durationValue == 1 ? 'min' : 'mins';
        } else {
          durationValue = duration.inHours;
          durationUnit = durationValue == 1 ? 'hour' : 'hours';
        }

        metricPayload.addAll({
          'type': 'stop_span',
          'stopTime': '$stopTime',
          'duration': '$durationValue$durationUnit',
          'status': status ?? 'Unknown',
        });
      }

      final logEntry = LogEntry(
        logLevel: Level.FINE, 
        ts: DateTime.now().toUtc(), 
        line: jsonEncode(metricPayload), 
        lineLabels: {
          'app': appName!,
        }
      );

      await metricAppender.sendMeticEventsWithDio([logEntry], {}, CancelToken());
      print('Metrics sent to loki');
    } catch (e) {
      print('Error occurred while sending metric event: $e');
      final logRecord = LogRecord(
        Level.FINE, 
        jsonEncode(metricPayload), 
        appName!,
      );
      fileAppender.handle(logRecord);
      RotateMetrics.startTimer();
      print('timer started');
      print('Metrics sent to local file');
    }
    metricPayload.clear();
  }

  static Future<void> startSpan(String spanName) async {
    if (spanName.isEmpty) {
      return print('SpanName connot be empty');
    }
    if (spanTree.containsKey(spanName)) {
      return print('Span with name $spanName already exist');
    }
    final startTime = DateTime.now().toUtc();
    final spanInfo = SpanInfo(startTime: startTime);
    spanTree[spanName] = spanInfo;
    await Metric.sendMetricEvent(spanName, spanInfo); 
  }

  static Future<void> stopSpan(String spanName, String status) async {
    if (spanTree.isEmpty) {
      return print('No spans to stop');
    }

    final spanInfo = spanTree[spanName];
    if (spanInfo == null) {
      return print('Span with name $spanName does not exist');
    }
    
    final stopTime = DateTime.now().toUtc();
    spanInfo.stopTime = stopTime;

    await Metric.sendMetricEvent(spanName, spanInfo, stop: true, status: status);
    spanTree.remove(spanName);
  }
}

class SpanInfo {
  DateTime startTime;
  DateTime? stopTime;

  SpanInfo({required this.startTime});
}