import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

List<CameraDescription> cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NutriScan',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A0F),
        primaryColor: const Color(0xFF00E5A0),
      ),
      home: const ScannerScreen(),
    );
  }
}

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> with TickerProviderStateMixin {
  CameraController? _cameraController;
  bool _isCameraInitialized = false;
  bool _isScanning = false;
  bool _isProcessing = false;

  late AnimationController _pulseController;
  late AnimationController _scanLineController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _scanLineAnimation;

  final BarcodeScanner _barcodeScanner = BarcodeScanner(formats: [BarcodeFormat.ean13]);

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat(reverse: true);
    _scanLineController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat();

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    _scanLineAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _scanLineController, curve: Curves.linear));

    _initCamera();
  }

  Future<void> _initCamera() async {
    if (cameras.isEmpty) return;
    _cameraController = CameraController(cameras[0], ResolutionPreset.high, enableAudio: false);
    await _cameraController!.initialize();
    if (mounted) setState(() => _isCameraInitialized = true);
  }

  Future<void> _captureAndScanBarcode() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized || _isProcessing) return;

    setState(() => _isProcessing = true);

    try {
      final XFile imageFile = await _cameraController!.takePicture();
      final InputImage inputImage = InputImage.fromFilePath(imageFile.path);

      final List<Barcode> barcodes = await _barcodeScanner.processImage(inputImage);

      if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
        final String barcode = barcodes.first.rawValue!;
        await _fetchProductInfo(barcode);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Código de barras não detectado')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao escanear código de barras')));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _fetchProductInfo(String barcode) async {
    try {
      final response = await http.get(Uri.parse('https://world.openfoodfacts.org/api/v0/product/$barcode.json'));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['status'] == 1 && data['product'] != null) {
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ProductResultScreen(productData: data['product'])),
            );
          }
          return;
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Produto não encontrado')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erro ao buscar informações')));
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _scanLineController.dispose();
    _cameraController?.dispose();
    _barcodeScanner.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_isCameraInitialized && _cameraController != null)
            _buildCameraPreview()
          else
            _buildLoadingState(),
          _buildTopGradient(),
          _buildBottomGradient(),
          _buildTopBar(),
          _buildScanOverlay(),
          _buildBottomControls(),
          if (_isProcessing) _buildProcessingOverlay(),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _cameraController!.value.previewSize!.height,
          height: _cameraController!.value.previewSize!.width,
          child: CameraPreview(_cameraController!),
        ),
      ),
    );
  }

  Widget _buildLoadingState() => const Center(child: CircularProgressIndicator(color: Color(0xFF00E5A0)));

  Widget _buildTopGradient() => Positioned(top: 0, left: 0, right: 0, height: 180, child: Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [const Color(0xFF0A0A0F).withOpacity(0.95), Colors.transparent]))));

  Widget _buildBottomGradient() => Positioned(bottom: 0, left: 0, right: 0, height: 240, child: Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [const Color(0xFF0A0A0F).withOpacity(0.98), Colors.transparent]))));

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('SCANNER', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 4)),
                  const SizedBox(height: 4),
                  Container(width: 32, height: 2, decoration: BoxDecoration(color: const Color(0xFF00E5A0), borderRadius: BorderRadius.circular(1))),
                ],
              ),
              GestureDetector(
                onTap: () {
                  final mode = _cameraController?.value.flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
                  _cameraController?.setFlashMode(mode);
                  setState(() {});
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white.withOpacity(0.1))),
                  child: Icon(_cameraController?.value.flashMode == FlashMode.torch ? Icons.flash_on_rounded : Icons.flash_off_rounded, color: _cameraController?.value.flashMode == FlashMode.torch ? const Color(0xFF00E5A0) : Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScanOverlay() {
    return Center(
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Transform.scale(scale: _isScanning ? _pulseAnimation.value : 1.0, child: child);
        },
        child: SizedBox(
          width: 280,
          height: 280,
          child: Stack(
            children: [
              CustomPaint(size: const Size(280, 280), painter: _CornerPainter(color: _isScanning ? const Color(0xFF00E5A0) : Colors.white.withOpacity(0.6), isActive: _isScanning)),
              if (_isScanning)
                AnimatedBuilder(
                  animation: _scanLineAnimation,
                  builder: (context, child) {
                    return Positioned(
                      top: _scanLineAnimation.value * 260,
                      left: 10,
                      right: 10,
                      child: Container(height: 2, decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, const Color(0xFF00E5A0).withOpacity(0.8), const Color(0xFF00E5A0), const Color(0xFF00E5A0).withOpacity(0.8), Colors.transparent]))),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  _isScanning ? 'Posicione o código de barras na área' : 'Aponte para o código de barras do produto',
                  key: ValueKey(_isScanning),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _isScanning ? const Color(0xFF00E5A0) : Colors.white.withOpacity(0.5), fontSize: 13, letterSpacing: 0.5),
                ),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isScanning)
                    _buildSecondaryButton(icon: Icons.close_rounded, onTap: () => setState(() => _isScanning = false)),
                  if (_isScanning) const SizedBox(width: 24),
                  _buildMainButton(),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainButton() {
    return GestureDetector(
      onTap: () {
        if (!_isCameraInitialized) return;
        if (_isScanning) {
          _captureAndScanBarcode();
        } else {
          setState(() => _isScanning = true);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: _isScanning ? 72 : 220,
        height: 60,
        decoration: BoxDecoration(
          color: const Color(0xFF00E5A0),
          borderRadius: BorderRadius.circular(30),
          boxShadow: [BoxShadow(color: const Color(0xFF00E5A0).withOpacity(0.4), blurRadius: 24, offset: const Offset(0, 8))],
        ),
        child: Center(
          child: _isScanning
              ? const Icon(Icons.camera_alt_rounded, color: Color(0xFF0A0A0F), size: 26)
              : const Text('Escanear Código', style: TextStyle(color: Color(0xFF0A0A0F), fontSize: 15, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  Widget _buildSecondaryButton({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white.withOpacity(0.12))),
        child: Icon(icon, color: Colors.white.withOpacity(0.7), size: 22),
      ),
    );
  }

  Widget _buildProcessingOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.7),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF00E5A0)),
            SizedBox(height: 20),
            Text('Buscando produto...', style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final bool isActive;

  _CornerPainter({required this.color, required this.isActive});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = isActive ? 3.5 : 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const cornerLength = 32.0;
    const cornerRadius = 12.0;
    const padding = 8.0;

    final topL = Path();
    topL.moveTo(padding, padding + cornerLength);
    topL.lineTo(padding, padding + cornerRadius);
    topL.arcToPoint(const Offset(padding + cornerRadius, padding), radius: const Radius.circular(cornerRadius), clockwise: true);
    topL.lineTo(padding + cornerLength, padding);
    canvas.drawPath(topL, paint);

    final topR = Path();
    topR.moveTo(size.width - padding - cornerLength, padding);
    topR.lineTo(size.width - padding - cornerRadius, padding);
    topR.arcToPoint(Offset(size.width - padding, padding + cornerRadius), radius: const Radius.circular(cornerRadius), clockwise: true);
    topR.lineTo(size.width - padding, padding + cornerLength);
    canvas.drawPath(topR, paint);

    final botL = Path();
    botL.moveTo(padding, size.height - padding - cornerLength);
    botL.lineTo(padding, size.height - padding - cornerRadius);
    botL.arcToPoint(Offset(padding + cornerRadius, size.height - padding), radius: const Radius.circular(cornerRadius), clockwise: false);
    botL.lineTo(padding + cornerLength, size.height - padding);
    canvas.drawPath(botL, paint);

    final botR = Path();
    botR.moveTo(size.width - padding - cornerLength, size.height - padding);
    botR.lineTo(size.width - padding - cornerRadius, size.height - padding);
    botR.arcToPoint(Offset(size.width - padding, size.height - padding - cornerRadius), radius: const Radius.circular(cornerRadius), clockwise: false);
    botR.lineTo(size.width - padding, size.height - padding - cornerLength);
    canvas.drawPath(botR, paint);
  }

  @override
  bool shouldRepaint(_CornerPainter oldDelegate) => oldDelegate.color != color || oldDelegate.isActive != isActive;
}

class ProductResultScreen extends StatelessWidget {
  final Map<String, dynamic> productData;

  const ProductResultScreen({super.key, required this.productData});

  @override
  Widget build(BuildContext context) {
    final nutriments = productData['nutriments'] ?? {};
    final name = productData['product_name_pt'] ?? productData['product_name'] ?? 'Produto não identificado';

    return Scaffold(
      appBar: AppBar(title: const Text('Informações Nutricionais')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 30),
            _buildInfo('Calorias', '${nutriments['energy-kcal_100g'] ?? '-'} kcal'),
            _buildInfo('Carboidratos', '${nutriments['carbohydrates_100g'] ?? '-'} g'),
            _buildInfo('Proteínas', '${nutriments['proteins_100g'] ?? '-'} g'),
            _buildInfo('Gorduras', '${nutriments['fat_100g'] ?? '-'} g'),
            _buildInfo('Fibras', '${nutriments['fiber_100g'] ?? '-'} g'),
            _buildInfo('Sódio', '${nutriments['sodium_100g'] ?? '-'} mg'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfo(String label, String value) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(title: Text(label), trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
    );
  }
}