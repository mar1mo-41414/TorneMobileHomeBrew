/// External browser opening tests (plan 154): the nasneHOME
/// URL built from a registered host, the per-platform browser
/// commands, the Windows launcher's meaningless exit code being
/// ignored, honest non-zero exits surfacing as errors, and the
/// mobile channel's answer (including a native build predating
/// the channel) folding into the opened / not-opened result.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tmhb/app/external_browser.dart';
import 'package:tmhb/core/core.dart';

void main() {
  group('nasneHomeUrl', () {
    test('builds the measured nasneHOME URL from the host', () {
      expect(
        nasneHomeUrl('192.168.11.129'),
        'http://192.168.11.129:64210/nasne_home/index.html',
      );
    });

    test('keeps a hostname host as-is', () {
      expect(
        nasneHomeUrl('nasne.local'),
        'http://nasne.local:64210/nasne_home/index.html',
      );
    });
  });

  group('browserCommandFor', () {
    const url = 'http://192.168.11.129:64210/nasne_home/index.html';

    test('windows opens through cmd start and ignores its exit code', () {
      final command = browserCommandFor(
        isWindows: true,
        isMacOS: false,
        isLinux: false,
        url: url,
      );
      expect(command, isNotNull);
      expect(command!.executable, 'cmd');
      expect(command.arguments, ['/c', 'start', '', url]);
      expect(command.exitCodeMatters, isFalse);
    });

    test('macos opens with open and checks its exit code', () {
      final command = browserCommandFor(
        isWindows: false,
        isMacOS: true,
        isLinux: false,
        url: url,
      );
      expect(command, isNotNull);
      expect(command!.executable, 'open');
      expect(command.arguments, [url]);
      expect(command.exitCodeMatters, isTrue);
    });

    test('linux opens with xdg-open and checks its exit code', () {
      final command = browserCommandFor(
        isWindows: false,
        isMacOS: false,
        isLinux: true,
        url: url,
      );
      expect(command, isNotNull);
      expect(command!.executable, 'xdg-open');
      expect(command.arguments, [url]);
      expect(command.exitCodeMatters, isTrue);
    });

    test('mobile platforms have no desktop command', () {
      expect(
        browserCommandFor(
          isWindows: false,
          isMacOS: false,
          isLinux: false,
          url: url,
        ),
        isNull,
      );
    });
  });

  group('ExternalBrowserOpener', () {
    const url = 'http://192.168.11.129:64210/nasne_home/index.html';

    ExternalBrowserOpener desktopOpener({
      required bool isWindows,
      required bool isMacOS,
      required bool isLinux,
      required Future<ProcessResult> Function(String, List<String>) runProcess,
    }) => ExternalBrowserOpener(
      runProcess: runProcess,
      isWindows: isWindows,
      isMacOS: isMacOS,
      isLinux: isLinux,
      isAndroid: false,
      isIOS: false,
    );

    test('macos runs open with the URL and reports opened', () async {
      String? seenExecutable;
      List<String>? seenArguments;
      final opener = desktopOpener(
        isWindows: false,
        isMacOS: true,
        isLinux: false,
        runProcess: (executable, arguments) async {
          seenExecutable = executable;
          seenArguments = arguments;
          return ProcessResult(0, 0, '', '');
        },
      );
      expect(await opener.open(url), isTrue);
      expect(seenExecutable, 'open');
      expect(seenArguments, [url]);
    });

    test(
      'a non-zero exit on macos throws instead of reporting opened',
      () async {
        final opener = desktopOpener(
          isWindows: false,
          isMacOS: true,
          isLinux: false,
          runProcess: (_, _) async => ProcessResult(0, 1, '', 'no browser'),
        );
        await expectLater(opener.open(url), throwsA(isA<ProcessException>()));
      },
    );

    test('windows ignores the launcher exit code', () async {
      final opener = desktopOpener(
        isWindows: true,
        isMacOS: false,
        isLinux: false,
        runProcess: (_, _) async => ProcessResult(0, 1, '', ''),
      );
      expect(await opener.open(url), isTrue);
    });

    test('android passes the platform answer through', () async {
      String? seenUrl;
      final opener = ExternalBrowserOpener(
        platformOpen: (u) async {
          seenUrl = u;
          return true;
        },
        isWindows: false,
        isMacOS: false,
        isLinux: false,
        isAndroid: true,
        isIOS: false,
      );
      expect(await opener.open(url), isTrue);
      expect(seenUrl, url);

      final refused = ExternalBrowserOpener(
        platformOpen: (_) async => false,
        isWindows: false,
        isMacOS: false,
        isLinux: false,
        isAndroid: true,
        isIOS: false,
      );
      expect(await refused.open(url), isFalse);
    });

    test('a native build predating the channel reads as not opened', () async {
      final opener = ExternalBrowserOpener(
        platformOpen: (_) async => throw MissingPluginException('no channel'),
        isWindows: false,
        isMacOS: false,
        isLinux: false,
        isAndroid: false,
        isIOS: true,
      );
      expect(await opener.open(url), isFalse);
    });

    test('an unsupported platform opens nothing', () async {
      final opener = ExternalBrowserOpener(
        isWindows: false,
        isMacOS: false,
        isLinux: false,
        isAndroid: false,
        isIOS: false,
      );
      expect(await opener.open(url), isFalse);
    });
  });
}
