/// Tests for the player teardown policy (plan 104): leaving
/// the player screen runs every teardown step in order, and
/// one step's failure — or the failure report's own failure —
/// never starves the steps after it. The field failure this
/// guards: dispose aborted by its first step (the resume
/// report's ref read) left the player undisposed and the
/// audio playing on the list screen.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/ui/player_teardown_policy.dart';

void main() {
  group('runTeardownSteps', () {
    test('runs every step in order when nothing fails', () {
      final ran = <String>[];
      final failures = <String>[];
      runTeardownSteps([
        (name: 'a', run: () => ran.add('a')),
        (name: 'b', run: () => ran.add('b')),
        (name: 'c', run: () => ran.add('c')),
      ], onFailure: (name, error) => failures.add(name));
      expect(ran, ['a', 'b', 'c']);
      expect(failures, isEmpty);
    });

    test('a failing step is reported and the rest still run', () {
      final ran = <String>[];
      final failures = <(String, Object)>[];
      runTeardownSteps([
        (name: 'player', run: () => throw StateError('ref in dispose')),
        (name: 'session', run: () => ran.add('session')),
        (name: 'report', run: () => ran.add('report')),
      ], onFailure: (name, error) => failures.add((name, error)));
      expect(ran, ['session', 'report']);
      expect(failures, hasLength(1));
      expect(failures.single.$1, 'player');
      expect(failures.single.$2, isA<StateError>());
    });

    test('a failure in the middle leaves the steps around it intact', () {
      final ran = <String>[];
      runTeardownSteps([
        (name: 'a', run: () => ran.add('a')),
        (name: 'b', run: () => throw Exception('boom')),
        (name: 'c', run: () => ran.add('c')),
      ], onFailure: (name, error) {});
      expect(ran, ['a', 'c']);
    });

    test('a throwing failure report does not interrupt the sequence', () {
      final ran = <String>[];
      runTeardownSteps([
        (name: 'a', run: () => throw Exception('boom')),
        (name: 'b', run: () => ran.add('b')),
      ], onFailure: (name, error) => throw Exception('log failed too'));
      expect(ran, ['b']);
    });

    test('an empty step list is a no-op', () {
      var reports = 0;
      runTeardownSteps([], onFailure: (name, error) => reports++);
      expect(reports, 0);
    });
  });
}
