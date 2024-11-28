// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:log/src/logger/rotate_logs.dart';
import 'package:logging/logging.dart';
import 'package:logging_appenders/base_remote_appender.dart';
import 'package:logging_appenders/logging_appenders.dart';
import 'package:path_provider/path_provider.dart';

class Log { 
  static late LokiApiAppender lokiAppender;
  static late RotatingFileAppender fileAppender;
  static final logger = Logger('Log');
  static Timer? timer;
  static String? appName;
  static String? platform;
  static String? systemName;
  static String? baseUrl;
  static String? storeId;
  static String? storeName;
  static String? terminalCode;
  static String? username;
  static bool consoleLog = false;

  static Future<void> initFile() async {
    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((record) {
      if (consoleLog) print('${record.level.name}: ${record.time.toUtc()}: ${record.message}');
    });
    final dir = await getApplicationSupportDirectory();
    final dirPath = '${dir.path}/logs';
    final logDir = Directory(dirPath);
    if (!await logDir.exists()) {
      await logDir.create(recursive: true);
    }

    final logPath = '$dirPath/app_logs';

    fileAppender = RotatingFileAppender(
      baseFilePath: logPath,
      rotateCheckInterval: const Duration(seconds: 5),
    );

    lokiAppender = LokiApiAppender(
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

  static Future<void> sendLogEvent(
    Level logLevel, 
    String name,
    DateTime time,
    {StackTrace? stackTrace, 
    bool error = false,
  }) async {

    try { 
      final logEntry = LogEntry(
        ts: time,
        logLevel: logLevel,
        line: '$name ${error ? ' - stackTrace: $stackTrace' : ''}',
        lineLabels: {
          'app': appName!,
        },
      );

      await lokiAppender.sendLogEventsWithDio([logEntry], {}, CancelToken());
    } catch (e) {
      print('Error occurred while sending log event: $e');
      final logRecord = LogRecord(
        logLevel, 
        name, 
        appName!, 
        error, 
        stackTrace,
      );
      fileAppender.handle(logRecord);
      RotateLogs.startTimer();
      print('timer started');
      print('Logs sent to local file');
    }
  }

  static Future<void> info(String name) async {
    Log.sendLogEvent(Level.INFO, name, DateTime.now().toUtc());
    logger.info(name);
  }

  static Future<void> error(String name, StackTrace stackTrace) async {
    Log.sendLogEvent(
      Level.SEVERE, 
      'Error occurred: $name', 
      DateTime.now().toUtc(),
      stackTrace: stackTrace, 
      error: true,
    );
    logger.severe(name, stackTrace);
  }

  static Future<void> debug(String name) async {
    Log.sendLogEvent(Level.CONFIG, name, DateTime.now().toUtc());
    logger.config(name);
  }

  static Future<void> warning(String name) async {
    Log.sendLogEvent(Level.WARNING, name, DateTime.now().toUtc());
    logger.warning(name);
  }
}