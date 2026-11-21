/// Recording-destination selection for the reservation form
/// (plan 89.12 / 89.14).
///
/// The landing drive of a recording follows the reservation's
/// `recordDestinationID` ('HDD' internal / 'USBHDD' external),
/// measured on the real device with four recordings (plan
/// 89.12): the value decides where the recording lands, so the
/// form lets the user pick it directly instead of deriving it
/// from anything else. The external choice exists only while
/// an external HDD is registered and mounted.
library;

import '../core/core.dart';

/// `recordDestinationID` of the internal HDD.
const String recordDestinationInternal = 'HDD';

/// `recordDestinationID` of the external (USB) HDD.
const String recordDestinationExternal = 'USBHDD';

/// True when an external HDD is registered and mounted, i.e.
/// the 'USBHDD' destination can actually be recorded to.
///
/// Entries are told apart by id: id 0 is the internal drive and
/// any other id is an external one (HDDListGet, plan 89.8). The
/// response's `internalFlag` does not follow its name — the
/// internal drive reports 0 and the external SSD reported 1 —
/// so [HddEntry.internal] is not used here.
bool externalDestinationAvailable(List<HddEntry> hdds) =>
    hdds.any((e) => e.id != 0 && e.mounted && e.registered);

/// The destination a create request may carry: the external
/// choice stands only while the external HDD is available;
/// anything else (including unknown values) falls back to the
/// internal HDD.
String effectiveRecordDestination(
  String selected, {
  required bool externalAvailable,
}) {
  if (selected == recordDestinationExternal && externalAvailable) {
    return recordDestinationExternal;
  }
  return recordDestinationInternal;
}

/// Display label of a destination value in the form.
String recordDestinationLabel(String destinationId) => switch (destinationId) {
  recordDestinationExternal => '外付け',
  _ => '内蔵',
};
