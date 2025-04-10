import 'dart:io';

import 'package:log/src/logger/appender.dart';

Future<void> initFile({
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
}) => Appender.initFile(
        directory: directory,
        server: server,
        username: username,
        password: password,
        appName: appName,
        platform: platform,
        systemName: systemName,
        baseUrl: baseUrl,
        loggedInUser: loggedInUser,
        storeCode: storeCode,
        storeName: storeName,
        terminalCode: terminalCode,
      );

Future<void> info(String message) => Appender.info(message);

Future<void> debug(String message) => Appender.debug(message);

Future<void> warning(String message) => Appender.warning(message);

Future<void> error(String message, {required StackTrace stackTrace}) => Appender.error(message, stackTrace);