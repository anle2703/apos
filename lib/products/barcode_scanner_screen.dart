import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:audioplayers/audioplayers.dart';

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isScanning = true;

  @override
  void dispose() {
    _scannerController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _playBeep() async {
    await _audioPlayer.play(AssetSource('beep.mp3'));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quét mã vạch')),
      body: MobileScanner(
        controller: _scannerController,
        onDetect: (capture) async {
          if (_isScanning) {
            final List<Barcode> barcodes = capture.barcodes;
            if (barcodes.isNotEmpty) {
              final String? code = barcodes.first.rawValue;
              if (code != null) {
                _isScanning = false;
                await _playBeep();
                if (!context.mounted) return;
                Navigator.of(context).pop(code);
              }
            }
          }
        },
      ),
    );
  }
}
