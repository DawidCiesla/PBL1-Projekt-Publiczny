import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScanSheet extends StatefulWidget {
  const QrScanSheet({super.key});

  @override
  State<QrScanSheet> createState() => _QrScanSheetState();
}

class _QrScanSheetState extends State<QrScanSheet> {
  final controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  bool _handled = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Material(
        color: Colors.black,
        child: Stack(
          children: [
            MobileScanner(
              controller: controller,
              onDetect: (capture) {
                if (_handled) return;
                final barcodes = capture.barcodes;
                final raw = barcodes.isNotEmpty ? barcodes.first.rawValue : null;
                if (raw == null || raw.trim().isEmpty) return;

                _handled = true;
                Navigator.of(context).pop(raw);
              },
            ),
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Zeskanuj kod QR',
                        style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      onPressed: () => controller.toggleTorch(),
                      icon: const Icon(Icons.flash_on_rounded, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),

            Center(
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white70, width: 2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}