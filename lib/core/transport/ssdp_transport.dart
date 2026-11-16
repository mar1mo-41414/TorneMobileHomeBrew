/// SSDP transport: M-SEARCH send / response collection (plan 5.2).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../errors.dart';

/// One SSDP response datagram, parsed as HTTP-like headers.
class SsdpResponse {
  const SsdpResponse({required this.from, required this.headers});

  final InternetAddress from;

  /// Header names upper-cased.
  final Map<String, String> headers;

  String? get location => headers['LOCATION'];
  String? get searchTarget => headers['ST'];
  String? get server => headers['SERVER'];
}

/// Sends M-SEARCH and collects responses. Pure dart:io, no platform
/// channels; OS-level multicast restrictions are the app layer's
/// concern (manual registration is the fallback, plan 5.2).
class SsdpTransport {
  const SsdpTransport();

  static final InternetAddress multicastAddress =
      InternetAddress('239.255.255.250');
  static const int port = 1900;

  Future<List<SsdpResponse>> search(
    String searchTarget, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final responses = <SsdpResponse>[];
    final seen = <String>{};
    final done = Completer<void>();
    final sub = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = socket.receive();
      if (datagram == null) return;
      final parsed = _parse(datagram);
      if (parsed == null) return;
      final key =
          '${parsed.from.address}|${parsed.location}|${parsed.searchTarget}';
      if (seen.add(key)) responses.add(parsed);
    }, onError: (_) {}, onDone: () {}, cancelOnError: false);

    final request = 'M-SEARCH * HTTP/1.1\r\n'
        'HOST: 239.255.255.250:1900\r\n'
        'MAN: "ssdp:discover"\r\n'
        'MX: 3\r\n'
        'ST: $searchTarget\r\n'
        '\r\n';
    try {
      socket.send(utf8.encode(request), multicastAddress, port);
      // A second send improves reliability on lossy Wi-Fi.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      socket.send(utf8.encode(request), multicastAddress, port);
      await Future<void>.delayed(timeout).whenComplete(() {
        if (!done.isCompleted) done.complete();
      });
      await done.future;
    } catch (e) {
      throw NasneError.unreachable('ssdp:search', cause: e);
    } finally {
      await sub.cancel();
      socket.close();
    }
    return responses;
  }

  SsdpResponse? _parse(Datagram datagram) {
    final text = utf8.decode(datagram.data, allowMalformed: true);
    final lines = text.split('\r\n');
    if (lines.isEmpty || !lines.first.contains('200')) return null;
    final headers = <String, String>{};
    for (final line in lines.skip(1)) {
      if (line.isEmpty) break;
      final colon = line.indexOf(':');
      if (colon <= 0) continue;
      headers[line.substring(0, colon).trim().toUpperCase()] =
          line.substring(colon + 1).trim();
    }
    return SsdpResponse(from: datagram.address, headers: headers);
  }
}
