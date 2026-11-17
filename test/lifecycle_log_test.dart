/// App lifecycle logging tests (plan 36): every transition the
/// platform reports is written to the diagnostics log under the
/// playback category, so a field log can show when the process
/// was suspended and resumed around a playback session.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/app/lifecycle_log.dart';
import 'package:tmhb/core/core.dart';

void main() {
  group('LifecycleLogger', () {
    late List<String> records;
    late LifecycleLogger logger;

    setUp(() {
      records = [];
      logger = LifecycleLogger(
        DiagLog(
          (category, message) => records.add('${category.name}: $message'),
          (_) => true,
        ),
      );
    });

    test('each transition is recorded under the playback category', () {
      for (final state in AppLifecycleState.values) {
        logger.didChangeAppLifecycleState(state);
      }
      expect(records, [
        for (final state in AppLifecycleState.values)
          'playback: app lifecycle: ${state.name}',
      ]);
    });

    test('a sleep/wake walk reads as inactive, paused, resumed', () {
      logger.didChangeAppLifecycleState(AppLifecycleState.inactive);
      logger.didChangeAppLifecycleState(AppLifecycleState.paused);
      logger.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(records, [
        'playback: app lifecycle: inactive',
        'playback: app lifecycle: paused',
        'playback: app lifecycle: resumed',
      ]);
    });

    test('a disabled category records nothing', () {
      final silent = LifecycleLogger(const DiagLog.none());
      silent.didChangeAppLifecycleState(AppLifecycleState.paused);
      // Nothing to assert on records (the sink discards); the
      // point is that recording is safe when logging is off.
    });
  });
}
