import 'package:log/src/telemetry/metric.dart';

Future<void> startSpan(String spanName) => Metric.startSpan(spanName);
Future<void> stopSpan(String spanName, String status) => Metric.stopSpan(spanName, status);