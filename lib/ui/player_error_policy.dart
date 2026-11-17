/// Player error policy (plan 43).
///
/// mpv can report "Cannot seek in this stream." while a stream
/// is being opened. The demuxer queues an initial seek for
/// streams whose timestamps do not start at zero; the core's
/// seek path refuses it because the stream — served by the
/// loopback proxy as a chunked response without ranges — is not
/// seekable, and the refusal is logged at error level. In mpv
/// itself the refusal is non-fatal (playback continues), but
/// media_kit forwards the message to the player's error stream,
/// where the player screen used to turn ANY error into a
/// failed start.
///
/// That is what an external reporter hit on Android: BS live at
/// DR quality failed to start with exactly this message, while
/// the mobile quality — whose timestamps start at zero, so no
/// initial seek is queued — played fine. (The same app on iOS
/// played DR live; the Android mpv build is the one that queues
/// and reports the seek.) The app itself never issues a seek:
/// the seek is mpv-internal.
///
/// A live stream is endless and unseekable by design, so for
/// live viewing the complaint carries no information: it is
/// logged and ignored, and the start watchdog remains the
/// arbiter of a start that never reaches playback. Recorded
/// playback keeps the previous behaviour — every player error
/// fails the start — so this changes nothing for recordings.
library;

/// True when [error] is mpv's refusal to seek in an unseekable
/// stream ("Cannot seek in this stream.").
bool isUnseekableStreamError(String error) =>
    error.contains('Cannot seek in this stream');

/// Whether a player [error] must fail the start. For live
/// viewing the unseekable-stream complaint is non-fatal (see
/// the library comment); everything else is fatal, as before.
bool playerErrorIsFatal(String error, {required bool live}) =>
    !(live && isUnseekableStreamError(error));
