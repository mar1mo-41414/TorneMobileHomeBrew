/// Opening a URL in the system browser (plan 154).
///
/// The first consumer is the registered-nasne menu's nasneHOME
/// action: nasneHOME is the unit's own web UI, so the app hands
/// its URL to the OS instead of reimplementing it. No package
/// dependency is taken for this (the same line as the hand-rolled
/// wakelock channel, plan 35): desktop launches the platform's
/// URL opener as a process — the route the log-folder opener
/// (plan 71) already uses for directories — and mobile rides a
/// small method channel to the platform's view intent / open
/// call.
///
/// A failed open is never silent: desktop process failures throw
/// (the caller surfaces them, the plan 69.5 line), and a mobile
/// platform that cannot or will not open the URL answers false.
library;

import 'dart:io';

import 'package:flutter/services.dart';

/// A command that opens a URL in the desktop's default browser.
class BrowserCommand {
  const BrowserCommand(
    this.executable,
    this.arguments, {
    required this.exitCodeMatters,
  });

  /// The program to run (`open`, `xdg-open`, `cmd`).
  final String executable;

  /// Its arguments: the URL to open (plus the launcher's own
  /// fixed arguments, e.g. the Windows `start` verb).
  final List<String> arguments;

  /// Whether a non-zero exit code means the open failed.
  ///
  /// The Windows `start` verb detaches the browser and reports
  /// nothing useful back through cmd's exit code, so on Windows
  /// only a failure to start the process counts (the same
  /// treatment explorer.exe gets in the log-folder opener).
  /// `open` and `xdg-open` report honestly and are checked.
  final bool exitCodeMatters;
}

/// The browser command that opens [url] on the platform selected
/// by [isWindows] / [isMacOS] / [isLinux], or null when none of
/// them applies (mobile: the platform channel's job).
BrowserCommand? browserCommandFor({
  required bool isWindows,
  required bool isMacOS,
  required bool isLinux,
  required String url,
}) {
  if (isWindows) {
    // `start` is a cmd builtin, not an executable; the empty
    // string is its window-title argument (without it, a quoted
    // URL would be taken as the title and nothing would open).
    return BrowserCommand('cmd', [
      '/c',
      'start',
      '',
      url,
    ], exitCodeMatters: false);
  }
  if (isMacOS) {
    return BrowserCommand('open', [url], exitCodeMatters: true);
  }
  if (isLinux) {
    return BrowserCommand('xdg-open', [url], exitCodeMatters: true);
  }
  return null;
}

/// The platform call behind [ExternalBrowserOpener] on mobile:
/// whether the platform opened [url] in a browser.
typedef PlatformOpenUrl = Future<bool> Function(String url);

/// Opens URLs in the system browser.
class ExternalBrowserOpener {
  ExternalBrowserOpener({
    Future<ProcessResult> Function(String executable, List<String> arguments)?
    runProcess,
    PlatformOpenUrl? platformOpen,
    bool? isWindows,
    bool? isMacOS,
    bool? isLinux,
    bool? isAndroid,
    bool? isIOS,
  }) : _runProcess = runProcess ?? Process.run,
       _platformOpen = platformOpen ?? _channelOpenUrl,
       _isWindows = isWindows ?? Platform.isWindows,
       _isMacOS = isMacOS ?? Platform.isMacOS,
       _isLinux = isLinux ?? Platform.isLinux,
       _isAndroid = isAndroid ?? Platform.isAndroid,
       _isIOS = isIOS ?? Platform.isIOS;

  final Future<ProcessResult> Function(String, List<String>) _runProcess;
  final PlatformOpenUrl _platformOpen;
  final bool _isWindows;
  final bool _isMacOS;
  final bool _isLinux;
  final bool _isAndroid;
  final bool _isIOS;

  static const MethodChannel _channel = MethodChannel(
    'com.markun.tmhb/external_browser',
  );

  static Future<bool> _channelOpenUrl(String url) async =>
      await _channel.invokeMethod<bool>('openUrl', url) ?? false;

  /// Opens [url] in the system browser.
  ///
  /// Returns whether the URL was handed to a browser. False
  /// means the platform has no route to one (an unsupported
  /// platform, a mobile platform with no browser able to take
  /// the intent, or a native build predating the channel) —
  /// the caller tells the user instead of the tap looking dead.
  ///
  /// Throws when a desktop opener process fails: a non-zero
  /// exit on platforms whose exit code matters, or the process
  /// failing to start at all.
  Future<bool> open(String url) async {
    final command = browserCommandFor(
      isWindows: _isWindows,
      isMacOS: _isMacOS,
      isLinux: _isLinux,
      url: url,
    );
    if (command != null) {
      final result = await _runProcess(command.executable, command.arguments);
      if (command.exitCodeMatters && result.exitCode != 0) {
        throw ProcessException(
          command.executable,
          command.arguments,
          'exited with code ${result.exitCode}',
          result.exitCode,
        );
      }
      return true;
    }
    if (_isAndroid || _isIOS) {
      try {
        return await _platformOpen(url);
      } on MissingPluginException {
        // A native build predating the channel: no route to a
        // browser from here, which the caller reports like any
        // other could-not-open.
        return false;
      }
    }
    return false;
  }
}
