import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'neo.dart';

/// Read a sync token from a QR code shown on another device.
///
/// Returns the scanned text, or null if the sheet was dismissed. The caller
/// still validates it — this only saves the typing, it does not vouch for what
/// was scanned.
///
/// Phone only. The web build keeps paste: this plugin fetches a decoder from a
/// CDN on web, which the PWA's cross-origin-isolation headers refuse, and
/// bundling a wasm decoder is a lot of payload for a field you can paste into.
Future<String?> scanSyncToken(BuildContext context) {
  return showNeoSheet<String>(context, (_) => const _ScanSheet());
}

class _ScanSheet extends StatefulWidget {
  const _ScanSheet();

  @override
  State<_ScanSheet> createState() => _ScanSheetState();
}

class _ScanSheetState extends State<_ScanSheet> {
  final _controller = MobileScannerController(
    // One format, and only the first result: this is a token, not a barcode
    // reader.
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _handled = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    // The camera keeps firing after a hit; without this the sheet pops twice
    // and the second pop closes whatever opened next.
    if (_handled) return;
    final value = capture.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.trim().isNotEmpty, orElse: () => null);
    if (value == null) return;
    _handled = true;
    Navigator.pop(context, value.trim());
  }

  @override
  Widget build(BuildContext context) {
    final t = neo(context);
    return Container(
      margin: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.bg,
        border: Border.all(color: t.line, width: 3),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              NeoChip('Scan token'),
              const Spacer(),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Text('✕', style: mono(context, size: 18, weight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(border: Border.all(color: t.line, width: 3)),
              child: MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
                errorBuilder: (context, error) {
                  // Permission refused, or no camera. Say so rather than showing
                  // a black rectangle — the way out is the paste field behind
                  // this sheet.
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'no camera available — paste the token instead',
                        textAlign: TextAlign.center,
                        style: mono(context, size: 12, weight: FontWeight.w700, color: t.muted),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _error ?? 'Point at the code on your other device',
            textAlign: TextAlign.center,
            style: mono(context, size: 12, color: t.muted),
          ),
        ],
      ),
    );
  }
}
