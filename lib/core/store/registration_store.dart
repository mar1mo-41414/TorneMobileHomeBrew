/// Local persistence for registrations and cached channel lists
/// (plan 12.7: registrations + channel lists persist; schedule and
/// title lists are display caches only, with the device as truth).
library;

import 'dart:convert';
import 'dart:io';

import '../models/channel.dart';
import '../models/device.dart';

/// Stores the user's registered nasne devices.
abstract interface class RegistrationStore {
  Future<List<RegisteredNasne>> loadAll();

  /// Inserts or replaces the registration for [device]'s host.
  Future<void> save(RegisteredNasne device);

  Future<void> remove(String host);
}

class InMemoryRegistrationStore implements RegistrationStore {
  InMemoryRegistrationStore([Iterable<RegisteredNasne>? initial])
      : _byHost = {
          for (final d in initial ?? const <RegisteredNasne>[]) d.host: d,
        };

  final Map<String, RegisteredNasne> _byHost;

  @override
  Future<List<RegisteredNasne>> loadAll() async =>
      List.unmodifiable(_byHost.values);

  @override
  Future<void> save(RegisteredNasne device) async {
    _byHost[device.host] = device;
  }

  @override
  Future<void> remove(String host) async {
    _byHost.remove(host);
  }
}

/// JSON-file backed store: a list of [RegisteredNasne] JSON objects.
class JsonFileRegistrationStore implements RegistrationStore {
  JsonFileRegistrationStore(this.file);

  final File file;

  Future<List<RegisteredNasne>> _read() async {
    if (!await file.exists()) return [];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      return [
        for (final e in decoded)
          if (e is Map)
            RegisteredNasne.fromJson(e.cast<String, dynamic>()),
      ];
    } on FormatException {
      return [];
    }
  }

  Future<void> _write(List<RegisteredNasne> devices) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
        jsonEncode([for (final d in devices) d.toJson()]));
  }

  @override
  Future<List<RegisteredNasne>> loadAll() => _read();

  @override
  Future<void> save(RegisteredNasne device) async {
    final devices = await _read();
    devices.removeWhere((d) => d.host == device.host);
    devices.add(device);
    await _write(devices);
  }

  @override
  Future<void> remove(String host) async {
    final devices = await _read();
    devices.removeWhere((d) => d.host == host);
    await _write(devices);
  }
}

/// Minimal string key-value persistence used for caches.
abstract interface class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class InMemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

/// JSON-file backed key-value store (one JSON object per file).
class JsonFileKeyValueStore implements KeyValueStore {
  JsonFileKeyValueStore(this.file);

  final File file;

  Future<Map<String, String>> _read() async {
    if (!await file.exists()) return {};
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return {};
      return {
        for (final e in decoded.entries) e.key.toString(): e.value.toString(),
      };
    } on FormatException {
      return {};
    }
  }

  Future<void> _write(Map<String, String> values) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(values));
  }

  @override
  Future<String?> read(String key) async => (await _read())[key];

  @override
  Future<void> write(String key, String value) async {
    final values = await _read();
    values[key] = value;
    await _write(values);
  }

  @override
  Future<void> delete(String key) async {
    final values = await _read();
    values.remove(key);
    await _write(values);
  }
}

/// Cache for channel lists, keyed per device and broadcasting type.
/// Channels are stored in the WebAPI JSON shape so [Channel.fromJson]
/// reads them back unchanged.
class ChannelCache {
  ChannelCache(this._kv);

  final KeyValueStore _kv;

  String _key(String host, int broadcastingType) =>
      'channels:$host:$broadcastingType';

  Future<List<Channel>?> load(String host, int broadcastingType) async {
    final raw = await _kv.read(_key(host, broadcastingType));
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final list = decoded['channels'];
      if (list is! List) return null;
      return [
        for (final e in list)
          if (e is Map)
            Channel.fromJson(e.cast<String, dynamic>(),
                broadcastingType: broadcastingType),
      ];
    } on FormatException {
      return null;
    }
  }

  Future<void> save(
      String host, int broadcastingType, List<Channel> channels) async {
    await _kv.write(
      _key(host, broadcastingType),
      jsonEncode({
        'broadcastingType': broadcastingType,
        'fetchedAt': DateTime.now().toIso8601String(),
        'channels': [for (final c in channels) _channelToJson(c)],
      }),
    );
  }

  static Map<String, dynamic> _channelToJson(Channel c) => {
        'networkId': c.networkId,
        'transportStreamId': c.transportStreamId,
        'serviceId': c.serviceId,
        'serviceType': c.serviceType,
        'channelNumber': c.channelNumber,
        'branchNumber': c.branchNumber,
        'serviceName': c.serviceName,
        if (c.serviceProviderName != null)
          'serviceProviderName': c.serviceProviderName,
        if (c.freqChannelNo != null) 'freqChannelNo': c.freqChannelNo,
        if (c.remoteControlKeyId != null)
          'remoteControlKeyId': c.remoteControlKeyId,
        'contract': c.contract,
      };
}
