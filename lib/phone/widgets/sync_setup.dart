import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/sync_account.dart';
import '../../data/sync_transport.dart';
import '../../theme/tokens.dart';
import '../screens/now_screen.dart' show DottedField;
import 'neo.dart';
import 'scan_token.dart';

/// Setting up, showing, or leaving a sync account.
///
/// The token *is* the account. On the first device you generate one; on the
/// others you enter that same token to join. There is no username and no reset:
/// the token is the only thing to keep, which is why this screen's real job is
/// making it easy to copy and hard to lose.
Future<void> showSyncSetup(BuildContext context, WidgetRef ref) {
  return showNeoSheet<void>(context, (_) => const _SyncSetupSheet());
}

class _SyncSetupSheet extends ConsumerStatefulWidget {
  const _SyncSetupSheet();

  @override
  ConsumerState<_SyncSetupSheet> createState() => _SyncSetupSheetState();
}

class _SyncSetupSheetState extends ConsumerState<_SyncSetupSheet> {
  final _entry = TextEditingController();
  bool _busy = false;
  bool _entering = false;
  String? _error;
  String? _justCreated;

  @override
  void dispose() {
    _entry.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      ref.invalidate(syncTokenProvider);
    } on SyncException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    final token = ref.watch(syncTokenProvider).valueOrNull;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        margin: const EdgeInsets.all(10),
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        decoration: BoxDecoration(color: t.bg, border: Border.all(color: t.line, width: 3)),
        padding: const EdgeInsets.all(14),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                NeoChip(token == null ? 'Set up sync' : 'Sync account'),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Text('✕', style: mono(context, size: 18, weight: FontWeight.w800)),
                ),
              ]),
              const SizedBox(height: 14),
              if (token == null) ..._setup(context, t) else ..._connected(context, t, token),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: mono(context, size: 12, weight: FontWeight.w700, color: t.brand)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _setup(BuildContext context, NeoTokens t) {
    return [
      Text(
        'Sync keeps your devices in step. Everything already works without it — '
        'this only adds a copy on the server.',
        style: mono(context, size: 12, color: t.muted),
      ),
      const SizedBox(height: 14),
      if (!_entering) ...[
        NeoButton(
          label: _busy ? 'working…' : '＋ new account',
          primary: true,
          onTap: _busy ? null : () => _run(() async {
            final created = await ref.read(syncAccountProvider).createAccount();
            if (mounted) setState(() => _justCreated = created);
          }),
        ),
        const SizedBox(height: 10),
        NeoButton(
          label: 'i have a token',
          onTap: _busy ? null : () => setState(() => _entering = true),
        ),
      ] else ...[
        Text('Scan the code on your other device, or paste its token',
            style: mono(context, size: 12, color: t.muted)),
        const SizedBox(height: 8),
        // Camera on the phone only — the web build has no decoder, see
        // scan_token.dart.
        if (!kIsWeb) ...[
          NeoButton(
            label: '⛶ scan qr',
            onTap: _busy
                ? null
                : () async {
                    final scanned = await scanSyncToken(context);
                    if (scanned == null || !mounted) return;
                    _entry.text = scanned;
                    // Straight through: having scanned it, being made to press
                    // "join" as well would be pure ceremony.
                    await _run(() => ref.read(syncAccountProvider).joinAccount(scanned));
                  },
          ),
          const SizedBox(height: 10),
        ],
        DottedField(controller: _entry, hint: 'sync token'),
        const SizedBox(height: 10),
        NeoButton(
          label: _busy ? 'joining…' : 'join',
          primary: true,
          onTap: _busy
              ? null
              : () => _run(() => ref.read(syncAccountProvider).joinAccount(_entry.text)),
        ),
        const SizedBox(height: 10),
        NeoButton(label: 'back', onTap: _busy ? null : () => setState(() => _entering = false)),
      ],
    ];
  }

  List<Widget> _connected(BuildContext context, NeoTokens t, String token) {
    return [
      if (_justCreated != null) ...[
        Text(
          'Save this token. It is the only way onto this account — there is no '
          'reset, and it is not stored anywhere you can read it back.',
          style: mono(context, size: 12, weight: FontWeight.w700, color: t.brand),
        ),
        const SizedBox(height: 12),
      ],
      Center(
        child: Container(
          // Always light, whatever the theme: scanners expect dark modules on a
          // light field, and an inverted code is a coin toss across readers.
          decoration: BoxDecoration(
            color: const Color(0xFFFFFFFF),
            border: Border.all(color: t.line, width: 3),
          ),
          padding: const EdgeInsets.all(12),
          child: QrImageView(
            data: token,
            size: 180,
            // Lowest correction level: the payload is short and this is read
            // from a screen at arm's length, not off a creased label, so the
            // redundancy would only make the modules smaller.
            errorCorrectionLevel: QrErrorCorrectLevel.L,
            backgroundColor: const Color(0xFFFFFFFF),
            eyeStyle: const QrEyeStyle(
              eyeShape: QrEyeShape.square,
              color: Color(0xFF000000),
            ),
            dataModuleStyle: const QrDataModuleStyle(
              dataModuleShape: QrDataModuleShape.square,
              color: Color(0xFF000000),
            ),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Text('TOKEN', style: mono(context, size: 10, weight: FontWeight.w800, spacing: 1, color: t.muted)),
      const SizedBox(height: 6),
      Container(
        decoration: BoxDecoration(color: t.surface2, border: Border.all(color: t.line, width: 2)),
        padding: const EdgeInsets.all(10),
        child: SelectableText(token, style: mono(context, size: 13, weight: FontWeight.w700)),
      ),
      const SizedBox(height: 10),
      NeoButton(
        label: '⧉ copy',
        primary: true,
        onTap: () async {
          await Clipboard.setData(ClipboardData(text: token));
          if (context.mounted) Navigator.pop(context);
        },
      ),
      const SizedBox(height: 10),
      Text('Scan the code with another device, or copy the token and paste it there.',
          style: mono(context, size: 12, color: t.muted)),
      const SizedBox(height: 16),
      NeoButton(
        label: 'disconnect',
        onTap: _busy
            ? null
            : () => _run(() async {
                  // Deliberately does not touch the local database: that is the
                  // authoritative copy, and disconnecting is not deleting.
                  await ref.read(syncAccountProvider).forget();
                }),
      ),
    ];
  }
}
