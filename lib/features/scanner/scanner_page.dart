import 'package:field_ops/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Camera barcode scanner that returns the first code read. Manual entry is
/// always available — labels get damaged, and simulators have no camera.
class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.ean13, BarcodeFormat.code128]);
  final _manual = TextEditingController();
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    _manual.dispose();
    super.dispose();
  }

  void _finish(String code) {
    if (_done || code.trim().isEmpty) return;
    _done = true;
    context.pop(code.trim());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.scanTitle)),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              controller: _controller,
              onDetect: (capture) {
                final value = capture.barcodes.firstOrNull?.rawValue;
                if (value != null) _finish(value);
              },
              errorBuilder: (context, _) => const Center(child: Icon(Icons.no_photography_outlined, size: 48)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              key: const Key('manual-barcode'),
              controller: _manual,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.enterManually,
                suffixIcon: IconButton(icon: const Icon(Icons.check), onPressed: () => _finish(_manual.text)),
              ),
              onSubmitted: _finish,
            ),
          ),
        ],
      ),
    );
  }
}
