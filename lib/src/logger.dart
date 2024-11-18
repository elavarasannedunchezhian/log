import 'dart:async';

import 'package:logging/logging.dart';
import 'package:logging_appenders/logging_appenders.dart';

class Logger { 

  static Timer? timer;
  static String? appName;
  static String? platform;
  static String? systemName;
  static String? baseUrl;
  static String? storeId;
  static String? storeName;
  static String? terminalCode;
  static String? username;

  static Future<void> sendLogEvent(
    Level loglevel, 
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
        loglevel,
        DateTime.now(),
        name,
        {
          if(error)...{
            'stackTrace': '$stackTrace'
          }
        },
      );
    } catch (e) {
      print(e);
    }
  }

  static Future<void> info(String name) async => Logger.sendLogEvent(Level.INFO, name);
  static Future<void> error(String name, StackTrace stackTrace) async =>
      Logger.sendLogEvent(Level.SEVERE, 'Error occurred: $name', stackTrace: stackTrace, error: true);
  static Future<void> debug(String name) async => Logger.sendLogEvent(Level.CONFIG, name);
  static Future<void> warning(String name) async => Logger.sendLogEvent(Level.WARNING, name);
}