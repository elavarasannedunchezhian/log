import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:log/src/telemetry/metric.dart';
import 'package:logging/logging.dart';
import 'package:logging_appenders/base_remote_appender.dart';

class RotateMetrics {
  static late File filePath;
  static Timer? timer;
  static List<LogEntry> metricEntries = [];
  static bool timerRunning = false;
  static int intervalTime = 10;

  // rotate metric on interval
  static void startTimer() {
    if (!timerRunning) return;
    timerRunning = true;

    int currentTime = 0;
    timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      currentTime++;
      
      if (currentTime == intervalTime) {
        retrieveMetrics();
        currentTime = 0;
      }
    });
  }

  // Retrieve all metrics and send them to Loki.
  static Future<void> retrieveMetrics() async {
    final metricFiles = Metric.fileAppender.getAllLogFiles();
    bool metricsRemaining = false;

    for (final metricFile in metricFiles) {
      filePath = metricFile;

      if (await metricFile.exists()) {
        final metricLines = await metricFile.readAsLines();

        for (int i = 0; i < metricLines.length; i++) {
          try {
            final metricLine = metricLines[i];
            final parsedMetric = parseMetricLine(metricLine);

            if (parsedMetric != null) {
              metricEntries.add(
                LogEntry(
                  ts: parsedMetric['time'],
                  logLevel: parsedMetric['level'],
                  line: parsedMetric['message'],
                  lineLabels: {
                    'app': parsedMetric['loggerName'],
                  },
                ),
              );
            }
          } catch (e) {
            metricsRemaining = true; // Ensure retry for failed parsing
            log('Error processing metric line: $e');
          }
        }

        if (metricEntries.isNotEmpty) {
          final sentSuccessfully = await sendMetricsBackToLoki(metricEntries);
          if (!sentSuccessfully) {
            metricsRemaining = true; // Retry if sending fails
          } else {
            await deleteFile();
          }
        }
      } else {
        log('No metric file found: ${metricFile.path}');
      }
    }

    if (!metricsRemaining && metricEntries.isEmpty) {
      stopTimer();
      log('All metrics processed. Stopping retry timer.');
    }
  }

  // Parse the metric line into a structured map.
  static Map<String, dynamic>? parseMetricLine(String metricLine) {
    try {
      final regex = RegExp(
        r'^(?<time>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{6})\s+(?<level>[A-Z]+)\s+(?<loggerName>[^\s]+)\s+-\s+(?<message>\{.*\})$'
      );

      final match = regex.firstMatch(metricLine);
      if (match != null) {
        final time = DateTime.parse(match.namedGroup('time')!);
        final level = Level.LEVELS.firstWhere(
          (level) => level.name == match.namedGroup('level'),
          orElse: () => Level.ALL,
        );
        final message = match.namedGroup('message')!;
        final loggerName = match.namedGroup('loggerName')!;

        return {
          'time': time,
          'level': level,
          'message': message,
          'loggerName': loggerName,
        };
      }
    } catch (e) {
      log('Error parsing metric line: $metricLine\nError: $e');
    }
    return null;
  }

  // send a list of metric entries to loki
  static Future<bool> sendMetricsBackToLoki(List<LogEntry> metricEntries) async {
    try {
      await Metric.metricAppender.sendMeticEventsWithDio(metricEntries, {}, CancelToken());
      metricEntries.clear();
      return true;
    } catch (e) {
      log('Error occurred while sending metrics to loki: $e');
      return false;
    }
  }

  // after sending metrics to loki, delete the file
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
  