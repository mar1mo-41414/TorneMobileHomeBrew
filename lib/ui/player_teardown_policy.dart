/// Player teardown policy (plan 104): how leaving the player
/// screen runs its teardown steps.
///
/// Leaving the screen owes several independent things: cancel
/// the timers, release the wakelock, cancel the player's
/// stream subscriptions, stop and dispose the player, stop
/// the session, and (for a recording) report the resume
/// position. None of them may depend on another having
/// succeeded — a leaving that stops halfway leaves the audio
/// playing on the list screen, which is the field failure
/// this policy exists to prevent: plan 102's resume report
/// ran first in dispose and read the diagnostics log through
/// ref; Riverpod 3 throws for ref once the widget is
/// deactivating, so the StateError aborted dispose before
/// the player was disposed and the session stopped at all,
/// and mpv kept playing behind the list. (Live viewing
/// escaped only because it has no report to send, so the
/// read was never reached.)
///
/// [runTeardownSteps] is the whole policy: steps run in the
/// order given, a step that throws is reported through
/// `onFailure` and dropped, a failure of the report itself
/// is dropped too, and the remaining steps always run.
library;

/// One step of a teardown: a [name] for the failure report
/// and the [run] that does the work.
typedef TeardownStep = ({String name, void Function() run});

/// Runs [steps] in order, isolating failures (plan 104; see
/// the library note). [onFailure] receives the name and the
/// error of each failed step; it is the caller's logging,
/// and its own failure never interrupts the sequence.
void runTeardownSteps(
  List<TeardownStep> steps, {
  required void Function(String name, Object error) onFailure,
}) {
  for (final step in steps) {
    try {
      step.run();
    } catch (e) {
      try {
        onFailure(step.name, e);
      } catch (_) {
        // The report is a courtesy; teardown continues.
      }
    }
  }
}
