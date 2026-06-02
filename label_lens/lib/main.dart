import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:http/http.dart' as http;

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
        await _fetchProductInfo(barcodes.first.rawValue!);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Código de barras não detectado. Tente novamente.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao escanear código de barras.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _fetchProductInfo(String barcode) async {
    try {
      final response = await http.get(
        Uri.parse('https://world.openfoodfacts.org/api/v0/product/$barcode.json'),
      );

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Produto não encontrado na base de dados.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao buscar informações do produto.')),
        );
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

  Widget _buildLoadingState() {
    return Container(
      color: const Color(0xFF0A0A0F),
      child: const Center(
        child: CircularProgressIndicator(color: Color(0xFF00E5A0)),
      ),
    );
  }

  Widget _buildTopGradient() => Positioned(
    top: 0, left: 0, right: 0, height: 180,
    child: Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0xFF0A0A0F).withOpacity(0.95), Colors.transparent],
        ),
      ),
    ),
  );

  Widget _buildBottomGradient() => Positioned(
    bottom: 0, left: 0, right: 0, height: 240,
    child: Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [const Color(0xFF0A0A0F).withOpacity(0.98), Colors.transparent],
        ),
      ),
    ),
  );

  Widget _buildTopBar() {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('NUTRISCAN', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 4)),
                const SizedBox(height: 4),
                Container(width: 40, height: 2, decoration: BoxDecoration(color: const Color(0xFF00E5A0), borderRadius: BorderRadius.circular(1))),
              ]),
              GestureDetector(
                onTap: () {
                  final mode = _cameraController?.value.flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
                  _cameraController?.setFlashMode(mode);
                  setState(() {});
                },
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Icon(
                    _cameraController?.value.flashMode == FlashMode.torch ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                    color: _cameraController?.value.flashMode == FlashMode.torch ? const Color(0xFF00E5A0) : Colors.white,
                  ),
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
        builder: (context, child) => Transform.scale(
          scale: _isScanning ? _pulseAnimation.value : 1.0,
          child: child,
        ),
        child: SizedBox(
          width: 280, height: 160,
          child: Stack(children: [
            CustomPaint(
              size: const Size(280, 160),
              painter: _CornerPainter(
                color: _isScanning ? const Color(0xFF00E5A0) : Colors.white.withOpacity(0.6),
                isActive: _isScanning,
              ),
            ),
            if (_isScanning)
              AnimatedBuilder(
                animation: _scanLineAnimation,
                builder: (context, child) => Positioned(
                  top: _scanLineAnimation.value * 140,
                  left: 10, right: 10,
                  child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        Colors.transparent,
                        const Color(0xFF00E5A0).withOpacity(0.8),
                        const Color(0xFF00E5A0),
                        const Color(0xFF00E5A0).withOpacity(0.8),
                        Colors.transparent,
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    return Positioned(
      bottom: 0, left: 0, right: 0,
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
                  style: TextStyle(
                    color: _isScanning ? const Color(0xFF00E5A0) : Colors.white.withOpacity(0.5),
                    fontSize: 13, letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isScanning) ...[
                    _buildSecondaryButton(icon: Icons.close_rounded, onTap: () => setState(() => _isScanning = false)),
                    const SizedBox(width: 24),
                  ],
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
        width: 60, height: 60,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withOpacity(0.12)),
        ),
        child: Icon(icon, color: Colors.white.withOpacity(0.7), size: 22),
      ),
    );
  }

  Widget _buildProcessingOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.7),
      child: const Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(color: Color(0xFF00E5A0)),
          SizedBox(height: 20),
          Text('Buscando produto...', style: TextStyle(color: Colors.white, fontSize: 14, letterSpacing: 0.5)),
        ]),
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

    const cornerLength = 28.0;
    const cornerRadius = 10.0;
    const padding = 6.0;

    final topL = Path();
    topL.moveTo(padding, padding + cornerLength);
    topL.lineTo(padding, padding + cornerRadius);
    topL.arcToPoint(Offset(padding + cornerRadius, padding), radius: const Radius.circular(cornerRadius), clockwise: true);
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
  bool shouldRepaint(_CornerPainter old) => old.color != color || old.isActive != isActive;
}

class ProductResultScreen extends StatefulWidget {
  final Map<String, dynamic> productData;

  const ProductResultScreen({super.key, required this.productData});

  @override
  State<ProductResultScreen> createState() => _ProductResultScreenState();
}

class _ProductResultScreenState extends State<ProductResultScreen>
    with TickerProviderStateMixin {
  late AnimationController _headerController;
  late AnimationController _cardsController;
  late AnimationController _scoreController;
  late Animation<double> _headerFade;
  late Animation<Offset> _headerSlide;
  late Animation<double> _scoreFill;

  final ScrollController _scrollController = ScrollController();
  bool _isScrolled = false;

  static const Map<String, _AllergenMeta> _allergenMap = {
    'en:milk':        _AllergenMeta(label: 'Leite',        icon: Icons.water_drop_rounded,     color: Color(0xFF60A5FA)),
    'en:eggs':        _AllergenMeta(label: 'Ovos',         icon: Icons.egg_rounded,             color: Color(0xFFFBBF24)),
    'en:gluten':      _AllergenMeta(label: 'Glúten',       icon: Icons.grain_rounded,           color: Color(0xFFF97316)),
    'en:wheat':       _AllergenMeta(label: 'Trigo',        icon: Icons.grass_rounded,           color: Color(0xFFF97316)),
    'en:peanuts':     _AllergenMeta(label: 'Amendoim',     icon: Icons.spa_rounded,             color: Color(0xFFEF4444)),
    'en:nuts':        _AllergenMeta(label: 'Oleaginosas',  icon: Icons.eco_rounded,             color: Color(0xFFEF4444)),
    'en:soybeans':    _AllergenMeta(label: 'Soja',         icon: Icons.circle_rounded,          color: Color(0xFF84CC16)),
    'en:fish':        _AllergenMeta(label: 'Peixe',        icon: Icons.set_meal_rounded,        color: Color(0xFF22D3EE)),
    'en:crustaceans': _AllergenMeta(label: 'Crustáceos',                                        color: Color(0xFFFF6B6B)),
    'en:molluscs':    _AllergenMeta(label: 'Moluscos',                                          color: Color(0xFFFF6B6B)),
    'en:celery':      _AllergenMeta(label: 'Salsão',       icon: Icons.grass_rounded,           color: Color(0xFF4ADE80)),
    'en:mustard':     _AllergenMeta(label: 'Mostarda',     icon: Icons.circle_rounded,          color: Color(0xFFEAB308)),
    'en:sesame-seeds':_AllergenMeta(label: 'Gergelim',     icon: Icons.grain_rounded,           color: Color(0xFFFBBF24)),
    'en:sulphur-dioxide-and-sulphites': _AllergenMeta(label: 'Sulfitos', icon: Icons.science_rounded, color: Color(0xFFA78BFA)),
    'en:lupin':       _AllergenMeta(label: 'Tremoço',      icon: Icons.local_florist_rounded,   color: Color(0xFFFB923C)),
  };

  List<_AllergenMeta> _contains = [];
  List<_AllergenMeta> _traces = [];

  late String _productName;
  late Map<String, dynamic> _nutriments;
  late int _healthScore;
  late List<_NutrientRow> _nutrientRows;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    _parseProductData();
    _setupAnimations();

    _scrollController.addListener(() {
      final scrolled = _scrollController.offset > 80;
      if (scrolled != _isScrolled) setState(() => _isScrolled = scrolled);
    });

    Future.delayed(const Duration(milliseconds: 100), () {
      _headerController.forward();
      _scoreController.forward();
      Future.delayed(const Duration(milliseconds: 200), _cardsController.forward);
    });
  }

  void _parseProductData() {
    _productName = widget.productData['product_name_pt'] ??
        widget.productData['product_name'] ??
        'Produto não identificado';

    _nutriments = widget.productData['nutriments'] ?? {};

    final allergenTags = List<String>.from(widget.productData['allergens_tags'] ?? []);
    final tracesTags = List<String>.from(widget.productData['traces_tags'] ?? []);

    _contains = allergenTags.map((t) => _allergenMap[t]).whereType<_AllergenMeta>().toList();
    _traces = tracesTags.map((t) => _allergenMap[t]).whereType<_AllergenMeta>().toList();

    _nutrientRows = [
      _NutrientRow('Calorias',          _fmt(_nutriments['energy-kcal_100g']),      'kcal', _pct(_nutriments['energy-kcal_100g'], 2000),       const Color(0xFFFF6B6B)),
      _NutrientRow('Carboidratos',       _fmt(_nutriments['carbohydrates_100g']),    'g',    _pct(_nutriments['carbohydrates_100g'], 300),        const Color(0xFFFFB347)),
      _NutrientRow('Proteínas',          _fmt(_nutriments['proteins_100g']),         'g',    _pct(_nutriments['proteins_100g'], 75),              const Color(0xFF00E5A0)),
      _NutrientRow('Gorduras Totais',    _fmt(_nutriments['fat_100g']),              'g',    _pct(_nutriments['fat_100g'], 65),                   const Color(0xFFFF6B9D)),
      _NutrientRow('Gorduras Saturadas', _fmt(_nutriments['saturated-fat_100g']),    'g',    _pct(_nutriments['saturated-fat_100g'], 20),         const Color(0xFFFF8E53)),
      _NutrientRow('Gorduras Trans',     _fmt(_nutriments['trans-fat_100g']),        'g',    _pct(_nutriments['trans-fat_100g'], 2),              const Color(0xFFFF4444)),
      _NutrientRow('Fibras',             _fmt(_nutriments['fiber_100g']),            'g',    _pct(_nutriments['fiber_100g'], 25),                 const Color(0xFF4ECDC4)),
      _NutrientRow('Açúcares',           _fmt(_nutriments['sugars_100g']),           'g',    _pct(_nutriments['sugars_100g'], 50),                const Color(0xFFFFD93D)),
      _NutrientRow('Sódio',              _fmt(_nutriments['sodium_100g'] != null ? (_nutriments['sodium_100g'] * 1000) : null), 'mg',
          _pct(_nutriments['sodium_100g'] != null ? (_nutriments['sodium_100g'] * 1000) : null, 2300), const Color(0xFFB8A9FF)),
    ];

    final score = widget.productData['nutriscore_score'];
    _healthScore = (100 - (score + 15).clamp(0, 100)).clamp(0, 100).toInt();
  }

  String _fmt(dynamic val) {
    if (val == null) return '-';
    if (val is int) return val.toString();
    if (val is double) return val.toStringAsFixed(1);
    return val.toString();
  }

  double _pct(dynamic val, double max) {
    if (val == null) return 0;
    final v = val is String ? double.tryParse(val) ?? 0 : (val as num).toDouble();
    return (v / max).clamp(0.0, 1.0);
  }

  void _setupAnimations() {
    _headerController = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _cardsController  = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    _scoreController  = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

    _headerFade  = CurvedAnimation(parent: _headerController, curve: Curves.easeOut);
    _headerSlide = Tween<Offset>(begin: const Offset(0, -0.3), end: Offset.zero)
        .animate(CurvedAnimation(parent: _headerController, curve: Curves.easeOut));
    _scoreFill   = Tween<double>(begin: 0, end: _healthScore / 100)
        .animate(CurvedAnimation(parent: _scoreController, curve: Curves.easeOutCubic));
  }

  Color get _scoreColor {
    if (_healthScore >= 70) return const Color(0xFF00E5A0);
    if (_healthScore >= 40) return const Color(0xFFFFB347);
    return const Color(0xFFFF6B6B);
  }

  String get _scoreLabel {
    if (_healthScore >= 70) return 'Saudável';
    if (_healthScore >= 40) return 'Moderado';
    return 'Atenção';
  }

  @override
  void dispose() {
    _headerController.dispose();
    _cardsController.dispose();
    _scoreController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D16),
      body: Stack(
        children: [
          _buildBgGlow(),
          CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _buildHeader()),
              SliverToBoxAdapter(child: _buildScoreCard()),
              if (_contains.isNotEmpty || _traces.isNotEmpty)
                SliverToBoxAdapter(child: _buildAllergenSection()),
              SliverToBoxAdapter(child: _buildSectionTitle('Composição Nutricional', 'por 100g')),
              _buildNutrientList(),
              SliverToBoxAdapter(child: _buildServingInfoRow()),
              const SliverToBoxAdapter(child: SizedBox(height: 48)),
            ],
          ),
          if (_isScrolled) _buildCollapsedBar(),
        ],
      ),
    );
  }

  Widget _buildBgGlow() {
    return Positioned(
      top: -80, right: -60,
      child: Container(
        width: 320, height: 320,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [_scoreColor.withOpacity(0.07), Colors.transparent]),
        ),
      ),
    );
  }

  Widget _buildCollapsedBar() {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0D0D16).withOpacity(0.96),
          border: Border(bottom: BorderSide(color: Colors.white.withOpacity(0.06))),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(children: [
              _backBtn(),
              const SizedBox(width: 14),
              Expanded(
                child: Text(_productName,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return SafeArea(
      child: FadeTransition(
        opacity: _headerFade,
        child: SlideTransition(
          position: _headerSlide,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                _backBtn(),
                _scoreChip(),
              ]),
              const SizedBox(height: 24),
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                ),
                child: const Icon(Icons.inventory_2_rounded, color: Colors.white, size: 24),
              ),
              const SizedBox(height: 14),
              Text(_productName,
                style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700, height: 1.2, letterSpacing: -0.5),
              ),
              const SizedBox(height: 6),
              Text('Tabela nutricional · 100g',
                style: TextStyle(color: Colors.white.withOpacity(0.38), fontSize: 13),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _backBtn() {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Container(
        width: 42, height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: Colors.white.withOpacity(0.09)),
        ),
        child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 17),
      ),
    );
  }

  Widget _scoreChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: _scoreColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _scoreColor.withOpacity(0.25)),
      ),
      child: Row(children: [
        Icon(
          _healthScore >= 70 ? Icons.check_circle_rounded : _healthScore >= 40 ? Icons.info_rounded : Icons.warning_rounded,
          color: _scoreColor, size: 14,
        ),
        const SizedBox(width: 6),
        Text(_scoreLabel, style: TextStyle(color: _scoreColor, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
      ]),
    );
  }

  Widget _buildScoreCard() {
    final kcal = _fmt(_nutriments['energy-kcal_100g']);
    final prot = _fmt(_nutriments['proteins_100g']);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Row(children: [
          SizedBox(
            width: 88, height: 88,
            child: AnimatedBuilder(
              animation: _scoreFill,
              builder: (context, _) => CustomPaint(
                painter: _RingPainter(progress: _scoreFill.value, color: _scoreColor),
                child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('${(_scoreFill.value * 100).toInt()}',
                    style: TextStyle(color: _scoreColor, fontSize: 24, fontWeight: FontWeight.w800, height: 1),
                  ),
                  Text('/100', style: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 10)),
                ])),
              ),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Índice Nutricional',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text('Perfil $_scoreLabel baseado na composição nutricional por 100g.',
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12.5, height: 1.5),
            ),
            const SizedBox(height: 12),
            Row(children: [
              _miniTag('$kcal kcal', const Color(0xFFFF6B6B)),
              const SizedBox(width: 8),
              _miniTag('${prot}g prot.', const Color(0xFF00E5A0)),
            ]),
          ])),
        ]),
      ),
    );
  }

  Widget _miniTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildAllergenSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_contains.isNotEmpty) ...[
          _allergenBlock(
            title: 'CONTÉM',
            subtitle: 'Alérgenos presentes neste produto',
            items: _contains,
            color: const Color(0xFFEF4444),
            icon: Icons.warning_rounded,
          ),
          const SizedBox(height: 12),
        ],
        if (_traces.isNotEmpty)
          _allergenBlock(
            title: 'PODE CONTER TRAÇOS',
            subtitle: 'Possível contaminação cruzada',
            items: _traces,
            color: const Color(0xFFFFB347),
            icon: Icons.info_rounded,
          ),
      ]),
    );
  }

  Widget _allergenBlock({
    required String title,
    required String subtitle,
    required List<_AllergenMeta> items,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
            Text(subtitle, style: TextStyle(color: color.withOpacity(0.7), fontSize: 11.5)),
          ]),
        ]),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8, runSpacing: 8,
          children: items.map((a) {
            final c = a.color ?? color;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: c.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.withOpacity(0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (a.icon != null) ...[Icon(a.icon, color: c, size: 14), const SizedBox(width: 6)],
                Text(a.label, style: TextStyle(color: c, fontSize: 12.5, fontWeight: FontWeight.w600)),
              ]),
            );
          }).toList(),
        ),
      ]),
    );
  }

  Widget _buildSectionTitle(String title, String sub) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
        Text(sub, style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 12)),
      ]),
    );
  }

  SliverList _buildNutrientList() {
    return SliverList(
      delegate: SliverChildBuilderDelegate(
            (context, i) {
          final row = _nutrientRows[i];
          return AnimatedBuilder(
            animation: _cardsController,
            builder: (context, child) {
              final delay = i * 0.08;
              final v = Curves.easeOutCubic.transform(
                ((_cardsController.value - delay) / (1.0 - delay)).clamp(0.0, 1.0),
              );
              return Opacity(opacity: v, child: Transform.translate(offset: Offset(0, 18 * (1 - v)), child: child));
            },
            child: _buildNutrientRow(row),
          );
        },
        childCount: _nutrientRows.length,
      ),
    );
  }

  Widget _buildNutrientRow(_NutrientRow row) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              color: row.color, shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: row.color.withOpacity(0.5), blurRadius: 6, spreadRadius: 1)],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(row.label, style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w500)),
              Row(children: [
                Text(row.value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(width: 3),
                Text(row.unit, style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 11)),
                const SizedBox(width: 10),
                if (row.value != '-')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: row.color.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                    child: Text('${(row.percentage * 100).toInt()}%',
                      style: TextStyle(color: row.color, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
              ]),
            ]),
            if (row.value != '-') ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: AnimatedBuilder(
                  animation: _cardsController,
                  builder: (_, __) => LinearProgressIndicator(
                    value: _cardsController.value * row.percentage,
                    minHeight: 5,
                    backgroundColor: Colors.white.withOpacity(0.06),
                    valueColor: AlwaysStoppedAnimation<Color>(row.color),
                  ),
                ),
              ),
            ],
          ])),
        ]),
      ),
    );
  }

  Widget _buildServingInfoRow() {
    final servingSize = widget.productData['serving_size'] ?? '100g';
    final servings = widget.productData['servings_per_container'] ?? '-';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Row(children: [
        _infoTile('Porção', servingSize.toString(), Icons.scale_rounded),
        const SizedBox(width: 12),
        _infoTile('Por embalagem', servings.toString(), Icons.layers_rounded),
        const SizedBox(width: 12),
        _infoTile('VD%', 'base 2000 kcal', Icons.person_rounded),
      ]),
    );
  }

  Widget _infoTile(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.07)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: Colors.white.withOpacity(0.3), size: 16),
          const SizedBox(height: 8),
          Text(value,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 10)),
        ]),
      ),
    );
  }
}

class _AllergenMeta {
  final String label;
  final IconData? icon;
  final Color? color;

  const _AllergenMeta({required this.label, this.icon, this.color});
}

class _NutrientRow {
  final String label;
  final String value;
  final String unit;
  final double percentage;
  final Color color;

  const _NutrientRow(this.label, this.value, this.unit, this.percentage, this.color);
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;

  _RingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 8;
    const stroke = 6.0;

    canvas.drawCircle(center, radius, Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..strokeWidth = stroke
      ..style = PaintingStyle.stroke);

    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -3.14159 / 2, 2 * 3.14159 * progress, false,
        Paint()
          ..color = color
          ..strokeWidth = stroke
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -3.14159 / 2, 2 * 3.14159 * progress, false,
        Paint()
          ..color = color.withOpacity(0.3)
          ..strokeWidth = stroke + 4
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.color != color;
}