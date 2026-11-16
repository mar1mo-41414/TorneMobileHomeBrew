/// tmhb core: UI-independent nasne client core.
///
/// Layering (plan 5.0 / 12.2): domain interfaces (services/) depend on
/// models/ and errors.dart only; transports live behind the service
/// implementations and are replaceable.
library;

export 'endpoints.dart';
export 'errors.dart';
export 'json_util.dart';
export 'time_util.dart';
export 'token.dart';
export 'models/channel.dart';
export 'models/device.dart';
export 'models/didl.dart';
export 'models/live_status.dart';
export 'models/schedule.dart';
export 'models/title.dart';
export 'services/interfaces.dart';
export 'services/playback.dart';
