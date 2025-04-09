import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:log/log.dart';
import 'package:log/src/telemetry/metric_appender.dart';
import 'package:log/src/telemetry/rotate_metrics.dart';
import 'package:logging/logging.dart';
import 'package:logging_appenders/base_remote_appender.dart';
import 'package:logging_appenders/logging_appenders.dart';

class Metric {
  static late MetricAppender metricAppender;
  static late RotatingFileAppender fileAppender;
  static final Map<String, SpanInfo> spanTree = {};
  static Timer? timer;
  static bool consoleMetric = false;

  static Future<void> initFile({
    required Directory directory,
    required String server,
    required String username,
    required String password,
    required String appName,
    String? platform,
    String? systemName,
    String? baseUrl,
    String? storeCode,
    String? storeName,
    String? terminalCode,
  }) async {
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((record) {
      if (consoleMetric) log('${record.level.name}: ${record.time.toUtc()} ${record.message}');
    });
    final dir = directory;
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
        'app': Log.appName ?? '',
        'system': Log.systemName ?? '',
        'terminal': Log.terminalCode ?? '',
        'username': Log.username  ?? '',
        'storeCode': Log.storeCode ?? '',
        'storeName': Log.storeName ?? '',
        'platform': Log.platform ?? '',
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
          'app': Log.appName ?? '',
        }
      );

      await metricAppender.sendMeticEventsWithDio([logEntry], {}, CancelToken());
      log('Metrics sent to loki');
    } catch (e) {
      log('Error occurred while sending metric event: $e');
      final labelPayload = {
        'labels': {
          if (Log.appName?.isNotEmpty ?? false) 'app': Log.appName ?? '',
          if (Log.systemName?.isNotEmpty ?? false) 'system': Log.systemName ?? '',
          if (Log.terminalCode?.isNotEmpty ?? false)'terminal': Log.terminalCode ?? '',
          if (Log.username?.isNotEmpty ?? false) 'username': Log.username  ?? '',
          if (Log.storeCode?.isNotEmpty ?? false) 'storeCode': Log.storeCode ?? '',
          if (Log.storeName?.isNotEmpty ?? false) 'storeName': Log.storeName ?? '',
          if (Log.platform?.isNotEmpty ?? false) 'platform': Log.platform ?? '',
        }
      };
      final logRecord = LogRecord(
        Level.FINE, 
        jsonEncode(metricPayload), 
        jsonEncode(labelPayload),
      );
      fileAppender.handle(logRecord);
      //RotateMetrics.startTimer();
      //log('timer started');
      log('Metrics sent to local file');
    }
    metricPayload.clear();
  }

  static Future<void> startSpan(String spanName) async {
    if (spanName.isEmpty) {
      return log('SpanName connot be empty');
    }
    /*if (spanTree.containsKey(spanName)) {
      return log('Span with name $spanName already exist');
    }*/
    final startTime = DateTime.now().toUtc();
    final spanInfo = SpanInfo(startTime: startTime);
    spanTree[spanName] = spanInfo;
    await Metric.sendMetricEvent(spanName, spanInfo); 
  }

  static Future<void> stopSpan(String spanName, String status) async {
    if (spanTree.isEmpty) {
      return log('No spans to stop');
    }

    final spanInfo = spanTree[spanName];
    if (spanInfo == null) {
      return log('Span with name $spanName does not exist');
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