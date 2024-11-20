// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:logger/logger.dart' as logger_pkg;
import 'package:logging/logging.dart' as logging_pkg;
import 'package:logging_appenders/logging_appenders.dart';

class Log { 
  static Timer? timer;
  static String? appName;
  static String? platform;
  static String? systemName;
  static String? baseUrl;
  static String? storeId;
  static String? storeName;
  static String? terminalCode;
  static String? username;
  static bool consoleLogs = false;

  static var logger = logger_pkg.Logger(
    printer: logger_pkg.PrettyPrinter(
      printEmojis: consoleLogs,
      colors: consoleLogs,
      printTime: consoleLogs,
    )
  );

  static Future<void> sendLogEvent(
    logging_pkg.Level logLevel, 
    String name,
    {StackTrace? stackTrace, 
    bool error = false,
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

    try { 
      await lokiAppender.log(
        logLevel,
        DateTime.now(),
        name,
        {
          if(error)...{
            'stackTrace': '$stackTrace'
          }
        },
      );

      if (consoleLogs) {
        logToConsole(logLevel, name, stackTrace: stackTrace, error: error);
      }
    } catch (e) {
      logger.e('Error occurred while sending log event: $e');
    }
  }

  static void logToConsole(
    logging_pkg.Level logLevel,
    String message, {
    StackTrace? stackTrace,
    bool error = false,
  }) {
    switch (logLevel) {
      case logging_pkg.Level.INFO:
        logger.i(message);
        break;
      case logging_pkg.Level.WARNING:
        logger.w(message);
        break;
      case logging_pkg.Level.SEVERE:
        logger.e(message, error: stackTrace);
        break;
      case logging_pkg.Level.CONFIG:
        logger.d(message);
        break;
      default:
        logger.t(message);
    }
  }

  static Future<void> info(String name) async => Log.sendLogEvent(logging_pkg.Level.INFO, name);
  static Future<void> error(String name, StackTrace stackTrace) async =>
      Log.sendLogEvent(logging_pkg.Level.SEVERE, 'Error occurred: $name', stackTrace: stackTrace, error: true);
  static Future<void> debug(String name) async => Log.sendLogEvent(logging_pkg.Level.CONFIG, name);
  static Future<void> warning(String name) async => Log.sendLogEvent(logging_pkg.Level.WARNING, name);
}