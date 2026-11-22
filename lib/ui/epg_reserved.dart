/// Reserved-programme marking for the programme guide
/// (backlog 2026-11-22, plan 120): the guide grid frames
/// every event that already has a recording reservation
/// in red, so a reserved programme reads at a glance
/// while the tile keeps its genre tint — the frame is
/// painted over the tile, the tint underneath is
/// untouched, and both readings survive.
///
/// The match between a reservation and a guide event
/// uses the two identities a reservation can carry:
///  * an event reservation (created from the guide or
///    by the official app) names its programme in the
///    server-normalised desiredMatchingID — the 4th
///    element is the EIT event id — so (broadcastingType,
///    serviceId, eventId) identifies the event exactly,
///    whatever start the device normalised the
///    reservation to;
///  * a manual (time-based) reservation carries event
///    id 0, so it is matched by (broadcastingType,
///    serviceId, start instant) instead.
/// A repeating reservation (created by the official app;
/// this app cannot create one) appears in the schedule
/// list only as the concrete instance the device lists
/// — its next occurrence. The list carries no repeat
/// rule the app could expand, so only listed instances
/// are marked (plan 120).
library;

import 'package:material_ui/material_ui.dart';

import '../core/core.dart';

/// The colour of the frame painted around a reserved
/// event's tile: a saturated red that stays legible over
/// every genre tint and in both themes.
const Color epgReservedFrameColor = Color(0xFFD32F2F);

/// The frame width: thick enough to read at grid scale,
/// thin enough to leave the tile's own content alone.
const double epgReservedFrameWidth = 2.5;

/// Parses the event id (4th element) out of a
/// desiredMatchingID value. Accepts both the
/// server-normalised list form
/// (`0x7880,0x7880,0xDE00,0x1234`) and the create form
/// (`,,0x7880,0x1234`); returns null when the value does
/// not have four elements or the event element is empty
/// or unparseable. An event id of 0 means "no event"
/// (a manual reservation) and is returned as 0.
int? desiredMatchingEventId(String desiredMatchingId) {
  final parts = desiredMatchingId.split(',');
  if (parts.length != 4) return null;
  final text = parts[3].trim();
  if (text.isEmpty) return null;
  try {
    return ScheduleChannel.parseServiceId(text);
  } on FormatException {
    return null;
  }
}

/// The decoration framing a reserved tile, or null for
/// an unreserved one. Used as the foreground decoration
/// of a box around the tile, so it paints over the
/// tile's edge without touching the genre tint inside.
BoxDecoration? epgReservedFrame(bool reserved) => reserved
    ? BoxDecoration(
        border: Border.all(
          color: epgReservedFrameColor,
          width: epgReservedFrameWidth,
        ),
        borderRadius: BorderRadius.circular(3),
      )
    : null;

/// The set of guide events covered by a reservation
/// list, as lookup keys for the guide grid.
class EpgReservedIndex {
  EpgReservedIndex.fromSchedules(List<RecordSchedule> schedules) {
    for (final s in schedules) {
      final bt = s.channel.broadcastingType;
      final sid = s.channel.serviceId;
      _byStart.add((bt, sid, s.start.millisecondsSinceEpoch));
      final eventId = desiredMatchingEventId(s.desiredMatchingId);
      if (eventId != null && eventId != 0) {
        _byEvent.add((bt, sid, eventId));
      }
    }
  }

  /// (broadcastingType, serviceId, eventId) of every
  /// event reservation.
  final Set<(int, int, int)> _byEvent = {};

  /// (broadcastingType, serviceId, start epoch ms) of
  /// every reservation, event and manual alike.
  final Set<(int, int, int)> _byStart = {};

  bool get isEmpty => _byEvent.isEmpty && _byStart.isEmpty;

  /// Whether [event] on [channel] already has a
  /// reservation.
  bool isReserved(Channel channel, EpgEvent event) =>
      _byEvent.contains((
        channel.broadcastingType,
        channel.serviceId,
        event.eventId,
      )) ||
      _byStart.contains((
        channel.broadcastingType,
        channel.serviceId,
        event.start.millisecondsSinceEpoch,
      ));
}
