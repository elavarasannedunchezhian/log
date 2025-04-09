import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:log/src/logger/log.dart';
import 'package:logging/logging.dart';
import 'package:logging_appenders/base_remote_appender.dart';

class RotateLogs {
  static late File filePath;
  static Timer? timer;
  static List<LogEntry> logEntries = [];
  static bool timerRunning = false;
  static int intervalTime = 10;

  // rotate logs on interval
  static void startTimer() {
    if (!timerRunning) return;
    timerRunning = true;

    int currentTime = 0;
    timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      currentTime++;
      
      if (currentTime == intervalTime) {
        retrieveLogs();
        currentTime = 0;
      }
    });
  }


  // Retrieve all logs and send them to Loki.
  static Future<void> retrieveLogs() async {
    final logFiles = Log.fileAppender.getAllLogFiles();
    bool logsRemaining = false;

    for (final logFile in logFiles) {
      filePath = logFile;

      if (await logFile.exists()) {
        final logLines = await logFile.readAsLines();

        for (int i = 0; i < logLines.length; i++) {
          try {
            final logLine = logLines[i];
            final parsedLog = parseLogLine(logLine);

            if (parsedLog != null) {
              String stackTrace = '';
              if (parsedLog['level'] == Level.SEVERE) {
                // Collect the entire stack trace for SEVERE logs
                final buffer = StringBuffer();
                int j = i + 1;
                while (j < logLines.length && logLines[j].startsWith('#')) {
                  buffer.writeln(logLines[j]);
                  j++;
                }
                stackTrace = buffer.toString().trim();
                i = j - 1; // Skip the processed stack trace line
              }
              log('Stack trace: $stackTrace');

              logEntries.add(LogEntry(
                ts: parsedLog['time'],
                logLevel: parsedLog['level'],
                line: stackTrace.isNotEmpty
                  ? '${parsedLog['message']} \n$stackTrace'
                  : parsedLog['message'],
                lineLabels: {
                  'app': parsedLog['loggerName'],
                },
              ));
            }
          } catch (e) {
            logsRemaining = true; // Ensure retry for failed parsing
            log('Error processing log line: $e');
          }
        }

        if (logEntries.isNotEmpty) {
          final sentSuccessfully = await sendLogBackToLoki(logEntries);
          if (!sentSuccessfully) {
            logsRemaining = true; // Retry if sending fails
          } else {
            await deleteFile();
          }
        }
      } else {
        log('No log file found: ${logFile.path}');
      }
    }

    if (!logsRemaining && logEntries.isEmpty) {
      stopTimer();
      log('All logs processed. Stopping retry timer.');
    }
  }

  // Parse the log line into a structured map.
  static Map<String, dynamic>? parseLogLine(String logLine) {
    try {
      final regex = RegExp(
        r'^(?<time>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{6}) (?<level>[A-Z]+) (?<loggerName>[^\s]+) (?<message>.+)(?:\n(?<stackTrace>.+))?$'
      );

      final match = regex.firstMatch(logLine);

      if (match != null) {
        final time = DateTime.parse(match.namedGroup('time')!);
        final level = Level.LEVELS.firstWhere(
          (level) => level.name == match.namedGroup('level'),
          orElse: () => Level.ALL,
        );
        final message = match.namedGroup('message')!;
        final loggerName = match.namedGroup('loggerName');

        return {
          'time': time,
          'level': level,
          'message': message,
          'loggerName': loggerName,
        };
      }
    } catch (e) {
      log('Failed to parse log line: $logLine\nError: $e');
    }
    return null;
  }

  // send a list of log entries to loki
  static Future<bool> sendLogBackToLoki(List<LogEntry> logEntries) async {
    try {
      await Log.lokiAppender.sendLogEventsWithDio(logEntries, {}, CancelToken());
      logEntries.clear();
      return true;
    } catch (e) {
      log('Error occurred while sending logs to loki: $e');
      return false;
    }
  }

  // after sending logs to loki, delete the file
  static Future<void> deleteFile() async {
    try {
      closeFile();
      await File(filePath.path).delete();
      log('File deleted successfully: ${filePath.path}');
    } catch (e) {
      log('Error occurred while deleting file: $e');
    }
  }

  // close file
  static closeFile() async {
    await File(filePath.path).open(mode: FileMode.append).then((raf) async {
      await raf.close();
    });
  }

  // stop timer
  static void stopTimer() {
    timerRunning = false;
    timer?.cancel();
  }
}