// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'package:log/src/metric_appender.dart';
import 'package:logger/logger.dart' as logger_pkg;
import 'package:logging/logging.dart' as logging_pkg;
import 'package:logging_appenders/base_remote_appender.dart';

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
  static bool consoleMetrics = false;

  static var logger = logger_pkg.Logger(
    printer: logger_pkg.PrettyPrinter(
      printEmojis: true,
      colors: true,
      printTime: true,
      methodCount: 0,
    )
  );

  static Future<void> sendMetricEvent(
    String name, 
    SpanInfo spanInfo, 
    {bool isStop = false, 
    String? status,
  }) async {
    final metricAppender = MetricAppender(
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

    try {
      final startTime = spanInfo.startTime;
      final stopTime = spanInfo.stopTime;

      final logPayload = <String, dynamic>{
        'type': 'start_span',
        'event': name,
        'startTime': startTime,
      };

      if (isStop && stopTime != null ) {
        logPayload.addAll({
          'type': 'stop_span',
          'stopTime': stopTime,
          'duration': DateTime.parse(stopTime)
              .difference(DateTime.parse(startTime))
              .inMilliseconds,
          'status': status ?? 'Unknown',
        });
      }

      final logEntry = LogEntry(
        logLevel: logging_pkg.Level.FINE, 
        ts: DateTime.now(), 
        line: jsonEncode(logPayload), 
        lineLabels: {}
      );

      await metricAppender.sendMeticEventsWithDio([logEntry], {}, CancelToken());
      if (consoleMetrics) {
        metricToConsole(logPayload);
      }
    } catch (e) {
      logger.e('Error occurred while sending metric event: $e');
    }
  }

  static void metricToConsole(Map<String, dynamic> logPayload) {
    final type = logPayload['type'];
    final event = logPayload['event'];
    final duration = logPayload['duration'];
    final status = logPayload['status'];

    if (type == 'start_span') {
      logger.f('Start Span: $event');
    } else if (type == 'stop_span') {
      logger.f('Stop Span: $event, Duration: ${duration ?? 'N/A'} ms, Status: ${status ?? 'N/A'}');
    } else {
      logger.t('Unknown Event: $event');
    }
  }

   static Future<void> startSpan(String spanName) async {
    if (spanName.isNotEmpty) {
      final startTime = dateFormat.format(DateTime.now().toUtc());
      final spanInfo = SpanInfo(startTime: startTime);
      spanTree[spanName] = spanInfo;
      await Telemetry.sendMetricEvent(spanName, spanInfo);
    } else {
      return logger.e('SpanName cannot be empty');
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
      return logger.e('spanName cannot be empty');
    }

  }
}

class SpanInfo {
  String startTime;
  String? stopTime;

  SpanInfo({required this.startTime});
}