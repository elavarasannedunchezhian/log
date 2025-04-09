import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:log/src/logger/rotate_logs.dart';
import 'package:log/src/telemetry/metric.dart';
import 'package:logging/logging.dart';
import 'package:logging_appenders/base_remote_appender.dart';
import 'package:logging_appenders/logging_appenders.dart';

class Log { 
  static late LokiApiAppender lokiAppender;
  static late RotatingFileAppender fileAppender;
  static final logger = Logger('Log');
  static Timer? timer;
  static String? appName;
  static String? platform;
  static String? systemName;
  static String? baseUrl;
  static String? storeCode;
  static String? storeName;
  static String? terminalCode;
  static String? username;
  static bool consoleLog = false;

  static Future<void> initFile({
    required Directory directory,
    required String server,
    required String username,
    required String password,
    required String appName,
    String? platform,
    String? systemName,
    String? baseUrl,
    String? loggedInUser,
    String? storeCode,
    String? storeName,
    String? terminalCode,
  }) async {
    await Metric.initFile(
      directory: directory,
      server: server,
      username: username,
      password: password,
      appName: appName,
      platform: platform,
      systemName: systemName,
      baseUrl: baseUrl,
      storeCode: storeCode,
      storeName: storeName,
      terminalCode: terminalCode,
    );
    Log.appName = appName;
    Log.platform = platform;
    Log.systemName = systemName;
    Log.baseUrl = baseUrl;
    Log.storeCode = storeCode;
    Log.storeName = storeName;    
    Log.terminalCode = terminalCode;
    Log.username = loggedInUser;

    Logger.root.level = Level.ALL;
    Logger.root.onRecord.listen((record) {
      if (consoleLog) log('${record.level.name}: ${record.time.toUtc()}: ${record.message}');
    });
    final dir = directory;
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
      server: server,
      username: username,
      password: password,
      labels: {
        'app': appName,
        'system': systemName ?? '',
        'terminal': terminalCode ?? '',
        'username': loggedInUser  ?? '',
        'storeCode': storeCode ?? '',
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
          'app': appName ?? '',
        },
      );

      await lokiAppender.sendLogEventsWithDio([logEntry], {}, CancelToken());
    } catch (e) {
      log('Error occurred while sending log event: $e');
      final logPayload = <String, dynamic>{
        'labels': {
          if (appName?.isNotEmpty ?? false) 'app': appName ?? '',
          if (systemName?.isNotEmpty ?? false) 'system': systemName ?? '',
          if (terminalCode?.isNotEmpty ?? false)'terminal': terminalCode ?? '',
          if (username?.isNotEmpty ?? false) 'username': username  ?? '',
          if (storeCode?.isNotEmpty ?? false) 'storeCode': storeCode ?? '',
          if (storeName?.isNotEmpty ?? false) 'storeName': storeName ?? '',
          if (platform?.isNotEmpty ?? false) 'platform': platform ?? '',
        }
      };
      final logRecord = LogRecord(
        logLevel, 
        name,
        jsonEncode(logPayload),
        stackTrace,
      );
      fileAppender.handle(logRecord);
      //RotateLogs.startTimer();
      //log('timer started');
      log('Logs sent to local file');
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
    Log.sendLogEvent(Level.FINER, name, DateTime.now().toUtc());
    logger.finer(name);
  }

  static Future<void> warning(String name) async {
    Log.sendLogEvent(Level.WARNING, name, DateTime.now().toUtc());
    logger.warning(name);
  }
}