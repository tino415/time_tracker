import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sync_service.dart';
import 'sync_transport.dart';

/// Whether a sync the user asked for is in flight, and what the last one came
/// to.
typedef ManualSyncState = ({bool running, String? status});

/// The first [Notifier] here, and the reason is the second way in.
///
/// Every other piece of mutable state in this app is a [StateProvider] over a
/// primitive or a plain [Provider] holding a hand-written controller, because a
/// controller owns *work* and the value belongs to whoever asked for it. This
/// owns a value — it lived in the sync button's own State until a keyboard
/// shortcut needed the same action, and a key handler has no widget to call
/// setState on. Both ways in now report one outcome.
class ManualSync extends Notifier<ManualSyncState> {
  @override
  ManualSyncState build() => (running: false, status: null);

  /// Silent without an account, and while one is already running: a second run
  /// would collapse inside [SyncService.syncNow] and come back '↑0 ↓0', writing
  /// over the result still on screen.
  ///
  /// Returns whether the server was reached — answered, not necessarily
  /// agreeably. The watch reads it to decide whether to ask the phone to sync
  /// instead; the phone has nowhere to fall back to and ignores it.
  Future<bool> run() async {
    final service = ref.read(syncServiceProvider);
    if (service == null || state.running) return false;

    state = (running: true, status: null);
    String? status;
    var reached = false;
    try {
      final result = await service.syncNow();
      status =
          '↑${result.pushed} ↓${result.pulled}'
          '${result.rejected > 0 ? " · ${result.rejected} superseded" : ""}';
      reached = true;
    } on SyncException catch (e) {
      // Being offline is the normal state for this app, not a failure worth
      // alarming about; a bad token is worth naming, because only the user
      // can fix it.
      status = e.unauthorized ? 'token rejected' : 'offline';
      // A refusal is an answer. Handing that to the other device would only
      // have it refused again, by the account both of them share.
      reached = e.unauthorized;
    } finally {
      state = (running: false, status: status);
    }
    return reached;
  }
}

final manualSyncProvider = NotifierProvider<ManualSync, ManualSyncState>(ManualSync.new);
