import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:isolate';
import 'package:file_picker/file_picker.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:pdf/widgets.dart' as pw;


const int kMaxEncodedChars = 5000;


int _encodedLengthFor(Uint8List bytes, String fileName, String mimeType) {
  final payload = <String, dynamic>{
    'version': 1,
    'name': fileName,
    'mime': mimeType,
    'data': base64Encode(bytes),
  };
  return jsonEncode(payload).length;
}

String _compressedFileName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot <= 0) return '${fileName}_compressed.jpg';
  return '${fileName.substring(0, dot)}_compressed.jpg';
}

Map<String, dynamic> _runCompressionCore({
  required Uint8List originalBytes,
  required String originalName,
  SendPort? progressPort,
}) {
  final compressedName = _compressedFileName(originalName);
  const compressedMime = 'image/jpeg';
  final decoded = img.decodeImage(originalBytes);
  if (decoded == null) {
    final fallback = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 1, height: 1), quality: 1));
    return {
      'compressedBytes': fallback,
      'compressedEncodedLength':
          _encodedLengthFor(fallback, compressedName, compressedMime),
      'compressedName': compressedName,
      'compressedMime': compressedMime,
      'compressedWidth': 1,
      'compressedHeight': 1,
      'compressedQuality': 1,
    };
  }
  final source = img.bakeOrientation(decoded);
  final int minOriginalSide = source.width < source.height ? source.width : source.height;
  final double originalArea = (source.width * source.height).toDouble();

  Uint8List smallestBytes = Uint8List.fromList(img.encodeJpg(source, quality: 70));
  int smallestLen = _encodedLengthFor(smallestBytes, compressedName, compressedMime);
  int smallestWidth = source.width;
  int smallestHeight = source.height;
  int smallestQuality = 70;

  Uint8List? bestReadableBytes;
  int? bestReadableLen;
  int? bestReadableWidth;
  int? bestReadableHeight;
  int? bestReadableQuality;
  double bestReadableScore = -1;

  const scales = <double>[
    1.00,
    0.90,
    0.80,
    0.72,
    0.64,
    0.56,
    0.48,
    0.40,
    0.34,
    0.28,
    0.22,
    0.18,
    0.14,
    0.10,
    0.08,
    0.06,
  ];
  const minQuality = 18;
  const maxQuality = 92;

  img.Image buildCandidateFrame(int width, int height) {
    final resized = img.copyResize(
      source,
      width: width,
      height: height,
      interpolation: img.Interpolation.linear,
    );
    final minSide = width < height ? width : height;
    if (minSide <= 220) {
      img.contrast(resized, contrast: 110);
      img.convolution(
        resized,
        filter: const <num>[0, -1, 0, -1, 5, -1, 0, -1, 0],
        amount: 0.20,
      );
    }
    return resized;
  }

  bool shouldStopEarly = false;
  for (final scale in scales) {
    if (shouldStopEarly) {
      break;
    }

    final width = (source.width * scale).round().clamp(1, source.width);
    final height = (source.height * scale).round().clamp(1, source.height);
    final minSide = width < height ? width : height;

    final working = buildCandidateFrame(width, height);

    Uint8List? scaleBestBytes;
    int? scaleBestLen;
    int? scaleBestQuality;
    

    // Adaptive quality search: find highest quality that still fits.
    var low = minQuality;
    var high = maxQuality;
    while (low <= high) {
      final quality = ((low + high) ~/ 2);
      // JPEG encoder internally applies color space conversion, DCT,
      // quantization, and entropy coding for each candidate.
      final encoded = Uint8List.fromList(img.encodeJpg(working, quality: quality));
      final length = _encodedLengthFor(encoded, compressedName, compressedMime);

      progressPort?.send(<String, dynamic>{
        'type': 'progress',
        'encodedLength': length,
      });

      if (length < smallestLen) {
        smallestLen = length;
        smallestBytes = encoded;
        smallestWidth = width;
        smallestHeight = height;
        smallestQuality = quality;
      }

      if (length <= kMaxEncodedChars) {
        scaleBestBytes = encoded;
        scaleBestLen = length;
        scaleBestQuality = quality;
        low = quality + 1;
      } else {
        high = quality - 1;
      }
    }

    if (scaleBestBytes != null && scaleBestLen != null && scaleBestQuality != null) {
      final areaRatio = (width * height) / originalArea;
      final sideRatio = minOriginalSide <= 0 ? 0.0 : (minSide / minOriginalSide);
      final qualityRatio = scaleBestQuality / 100.0;
      final qualityPower = qualityRatio * qualityRatio;
      final utilization = scaleBestLen / kMaxEncodedChars;

      final score =
          (sideRatio * 0.42) +
          (areaRatio * 0.20) +
          (qualityPower * 0.30) +
          (utilization * 0.08);

      if (score > bestReadableScore) {
        bestReadableScore = score;
        bestReadableBytes = scaleBestBytes;
        bestReadableLen = scaleBestLen;
        bestReadableWidth = width;
        bestReadableHeight = height;
        bestReadableQuality = scaleBestQuality;
        
      }

      // Good enough candidate reached: stop expensive further search.
      if (sideRatio >= 0.45 && qualityRatio >= 0.45 && utilization >= 0.95) {
        shouldStopEarly = true;
      }
    }
  }

  if (bestReadableBytes != null && bestReadableLen != null) {
    return {
      'compressedBytes': bestReadableBytes,
      'compressedEncodedLength': bestReadableLen,
      'compressedName': compressedName,
      'compressedMime': compressedMime,
      'compressedWidth': bestReadableWidth,
      'compressedHeight': bestReadableHeight,
      'compressedQuality': bestReadableQuality,
    };
  }

  // Additional readability-oriented fallback: prioritize keeping JPEG quality
  // higher by reducing dimensions first.
  const targetMaxSides = <int>[240, 200, 168, 140, 118, 98, 82, 68, 56, 44, 32, 24, 16, 12, 8, 4, 2, 1];
  const fallbackQualities = <int>[24, 20, 16, 12, 10, 8, 6, 4, 2, 1];

  for (final maxSide in targetMaxSides) {
    final scale = source.width >= source.height
        ? (maxSide / source.width)
        : (maxSide / source.height);
    final width = (source.width * scale).round().clamp(1, source.width);
    final height = (source.height * scale).round().clamp(1, source.height);
    final resized = buildCandidateFrame(width, height);

    for (final quality in fallbackQualities) {
      final encoded = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
      final length = _encodedLengthFor(encoded, compressedName, compressedMime);

      progressPort?.send(<String, dynamic>{
        'type': 'progress',
        'encodedLength': length,
      });

      if (length <= kMaxEncodedChars) {
        return {
          'compressedBytes': encoded,
          'compressedEncodedLength': length,
          'compressedName': compressedName,
          'compressedMime': compressedMime,
          'compressedWidth': width,
          'compressedHeight': height,
          'compressedQuality': quality,
        };
      }
    }
  }

  final emergency = Uint8List.fromList(
      img.encodeJpg(img.Image(width: 1, height: 1), quality: 1));
  final emergencyLen =
      _encodedLengthFor(emergency, compressedName, compressedMime);
  if (emergencyLen <= kMaxEncodedChars) {
    return {
      'compressedBytes': emergency,
      'compressedEncodedLength': emergencyLen,
      'compressedName': compressedName,
      'compressedMime': compressedMime,
      'compressedWidth': 1,
      'compressedHeight': 1,
      'compressedQuality': 1,
    };
  }
  return {
    'compressedBytes': smallestBytes,
    'compressedEncodedLength': smallestLen,
    'compressedName': compressedName,
    'compressedMime': compressedMime,
    'compressedWidth': smallestWidth,
    'compressedHeight': smallestHeight,
    'compressedQuality': smallestQuality,
  };
}

void _compressImageWithProgressIsolate(Map<String, dynamic> args) {
  final sendPort = args['sendPort'] as SendPort;
  try {
    final result = _runCompressionCore(
      originalBytes: args['imageBytes'] as Uint8List,
      originalName: args['fileName'] as String,
      progressPort: sendPort,
    );
    sendPort.send(<String, dynamic>{
      'type': 'result',
      'result': result,
    });
  } catch (e) {
    sendPort.send(<String, dynamic>{
      'type': 'error',
      'error': e.toString(),
    });
  }
}

void main() {
  runApp(const MyApp());
}

// ─── Theme ────────────────────────────────────────────────────────────────────
class AppColors {
  static const bg = Color(0xFF0D0F14);
  static const surface = Color(0xFF161920);
  static const card = Color(0xFF1E2128);
  static const accent = Color(0xFF6C63FF);
  static const accentAlt = Color(0xFF00D4AA);
  static const textPrimary = Color(0xFFF1F3F8);
  static const textSecondary = Color(0xFF8B90A0);
  static const border = Color(0xFF2A2D38);
  static const success = Color(0xFF22C55E);
  static const warning = Color(0xFFF59E0B);
  static const danger = Color(0xFFEF4444);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PixelText Studio',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: AppColors.bg,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.accent,
          secondary: AppColors.accentAlt,
          surface: AppColors.surface,
        ),
      ),
      home: const HomePage(),
    );
  }
}

// ─── Home Page ────────────────────────────────────────────────────────────────
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with TickerProviderStateMixin {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  Uint8List? _previewBytes;
  Uint8List? _originalBytes;
  String? _fileName;
  String? _originalName;
  String? _originalExtension;
  String? _generatedText;
  String? _statusMessage;
  bool _isBusy = false;
  bool _isSuccess = false;
  bool _showCopiedBadge = false;
  int _liveCharCount = 0;
  int _imageQualityPercent = 100;
  int _imageSizePercent = 100;
  Timer? _previewDebounce;

  late final AnimationController _pulseController;
  late final AnimationController _fadeController;
  late final AnimationController _slideController;
  late final Animation<double> _pulseAnim;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _liveCharCount = _textController.text.length;
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _fadeAnim = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
      
    );
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    _pulseController.dispose();
    _fadeController.dispose();
    _slideController.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _animateIn() {
    _fadeController.forward(from: 0);
    _slideController.forward(from: 0);
  }

  void _setStatus(String msg, {bool success = false}) {
    setState(() {
      _statusMessage = msg;
      _isSuccess = success;
    });
  }

  void _resetAll() {
    setState(() {
      _previewBytes = null;
      _originalBytes = null;
      _originalName = null;
      _originalExtension = null;
      _fileName = null;
      _generatedText = null;
      _statusMessage = 'Workspace refreshed. Ready for a new image.';
      _isSuccess = true;
      _showCopiedBadge = false;
      _isBusy = false;
      _textController.clear();
      _liveCharCount = 0;
    });
  }

  // ── Encode ──────────────────────────────────────────────────────────────────
  Future<void> _pickImageAndEncode() async {
    setState(() {
      _isBusy = true;
      _statusMessage = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        setState(() => _isBusy = false);
        return;
      }

      final file = result.files.single;
      final originalBytes = file.bytes;
      if (originalBytes == null || originalBytes.isEmpty) {
        setState(() => _isBusy = false);
        _setStatus('Failed to read file.');
        return;
      }

      // Keep original bytes so slider changes can re-generate previews.
      _originalBytes = originalBytes;
      _originalName = file.name;
      _originalExtension = file.extension;

      final prepared = _prepareImageForEncoding(
        originalBytes: originalBytes,
        originalName: file.name,
        extension: file.extension,
      );
      final encodedBytes = prepared['bytes'] as Uint8List;
      final encodedName = prepared['name'] as String;
      final encodedMime = prepared['mime'] as String;

      final payload = <String, dynamic>{
        'version': 1,
        'name': encodedName,
        'mime': encodedMime,
        'data': base64Encode(encodedBytes),
      };
      final encodedText = jsonEncode(payload);

      setState(() {
        _previewBytes = encodedBytes;
        _fileName = encodedName;
        _generatedText = encodedText;
        _textController.text = encodedText;
        _liveCharCount = encodedText.length;
        _isBusy = false;
      });
      _setStatus(
        'Image encoded - ${encodedText.length} chars (quality ${_imageQualityPercent}%, size ${_imageSizePercent}%).',
        success: true,
      );
      _animateIn();
    } catch (e) {
      setState(() => _isBusy = false);
      _setStatus('Error: $e');
    }
  }

  void _queuePreviewUpdate() {
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 180), () {
      _regeneratePreviewFromOriginal();
    });
  }

  void _onQualityChanged(int value) {
    setState(() => _imageQualityPercent = value);
    _queuePreviewUpdate();
  }

  void _onSizeChanged(int value) {
    setState(() => _imageSizePercent = value);
    _queuePreviewUpdate();
  }

  Future<void> _regeneratePreviewFromOriginal() async {
    final original = _originalBytes;
    final name = _originalName;
    final ext = _originalExtension;
    if (original == null || name == null) return;
    setState(() {
      _isBusy = true;
      _statusMessage = null;
    });
    try {
      await Future.delayed(const Duration(milliseconds: 8));
      final prepared = _prepareImageForEncoding(
        originalBytes: original,
        originalName: name,
        extension: ext,
      );
      final encodedBytes = prepared['bytes'] as Uint8List;
      final encodedName = prepared['name'] as String;
      final encodedMime = prepared['mime'] as String;

      final payload = <String, dynamic>{
        'version': 1,
        'name': encodedName,
        'mime': encodedMime,
        'data': base64Encode(encodedBytes),
      };
      final encodedText = jsonEncode(payload);

      if (!mounted) return;
      setState(() {
        _previewBytes = encodedBytes;
        _fileName = encodedName;
        _generatedText = encodedText;
        _textController.text = encodedText;
        _liveCharCount = encodedText.length;
        _isBusy = false;
      });
      _setStatus(
        'Preview updated - ${encodedText.length} chars (quality ${_imageQualityPercent}%, size ${_imageSizePercent}%).',
        success: true,
      );
      _animateIn();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      _setStatus('Preview update failed: $e');
    }
  }

  List<String> _splitTextIntoBlocks(String text, int blockSize) {
    final List<String> out = [];
    for (var i = 0; i < text.length; i += blockSize) {
      final end = (i + blockSize < text.length) ? i + blockSize : text.length;
      out.add(text.substring(i, end));
    }
    return out;
  }

  // ── Compression ─────────────────────────────────────────────────────────────
  Future<void> _showCompressionDialog({
    required Uint8List originalBytes,
    required String fileName,
    required String fileExtension,
    required int originalEncodedLength,
  }) async {
    if (!mounted) return;
    _showOverlaySheet(
      child: _CompressionSheet(
        originalBytes: originalBytes,
        fileName: fileName,
        fileExtension: fileExtension,
        originalEncodedLength: originalEncodedLength,
        guessMime: _guessMimeType,
        onResult: (previewBytes, name, text, msg) {
          Navigator.pop(context);
          setState(() {
            _previewBytes = previewBytes;
            _fileName = name;
            _generatedText = text;
            _textController.text = text;
            _liveCharCount = text.length;
            _isBusy = false;
          });
          _setStatus(msg, success: true);
          _animateIn();
        },
        onCancel: () {
          Navigator.pop(context);
          setState(() => _isBusy = false);
        },
      ),
    );
  }

  void _showOverlaySheet({required Widget child}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => child,
    );
  }

  // ── Decode ──────────────────────────────────────────────────────────────────
  Future<void> _decodeTextToImage() async {
    final input = _textController.text.trim();
    if (input.isEmpty) {
      _setStatus('Paste encoded text first.');
      return;
    }
    setState(() {
      _isBusy = true;
      _statusMessage = null;
    });
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      final bytes = _decodeImageBytes(input);
      final name = _extractName(input);
      setState(() {
        _previewBytes = bytes;
        _fileName = name;
        _generatedText = input;
        _liveCharCount = _textController.text.length;
        _isBusy = false;
      });
      _setStatus('Image restored successfully!', success: true);
      _animateIn();
    } catch (e) {
      setState(() => _isBusy = false);
      _setStatus('Decode failed: $e');
    }
  }

  // ── Copy ────────────────────────────────────────────────────────────────────
  Future<void> _copyEncodedText() async {
    final text = _generatedText;
    if (text == null || text.isEmpty) {
      _setStatus('Nothing to copy yet.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    setState(() => _showCopiedBadge = true);
    Future.delayed(const Duration(seconds: 2),
        () => setState(() => _showCopiedBadge = false));
  }

  // ── Save PDF ─────────────────────────────────────────────────────────────────
  Future<void> _saveEncodedTextAsFile() async {
    final text = (_generatedText ?? _textController.text).trim();
    if (text.isEmpty) {
      _setStatus('Generate or paste encoded text first.');
      return;
    }
    final baseName = (_fileName ?? 'image').replaceAll(RegExp(r'\.[^.]+$'), '');
    final safeBase = baseName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final suggestedName = '${safeBase}_encoded.pdf';

    setState(() => _isBusy = true);
    try {
      final chunked = _chunkTextForPdf(text, chunkSize: 150);
      final pdfDoc = pw.Document();
      final textChunks = <String>[];
      for (var i = 0; i < chunked.length; i += 4000) {
        textChunks.add(chunked.substring(
            i, i + 4000 > chunked.length ? chunked.length : i + 4000));
      }
      pdfDoc.addPage(pw.Page(
        build: (c) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Encoded Image Text',
                style: pw.TextStyle(
                    fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Text('Characters: ${text.length}',
                style: const pw.TextStyle(fontSize: 8)),
            pw.SizedBox(height: 8),
            pw.Text(textChunks[0], style: const pw.TextStyle(fontSize: 6)),
          ],
        ),
      ));
      for (var i = 1; i < textChunks.length; i++) {
        pdfDoc.addPage(pw.Page(
          build: (c) =>
              pw.Text(textChunks[i], style: const pw.TextStyle(fontSize: 6)),
        ));
      }
      final pdfBytes = await pdfDoc.save();
      final dir = await FilePicker.platform
          .getDirectoryPath(dialogTitle: 'Choose save folder');
      String? savedPath;
      if (dir != null && dir.isNotEmpty) {
        final f = File('$dir/$suggestedName');
        await f.writeAsBytes(pdfBytes, flush: true);
        savedPath = f.path;
      }
      if (!mounted) return;
      setState(() => _isBusy = false);
      _setStatus(
          savedPath == null
              ? 'Save cancelled.'
              : 'PDF saved → $savedPath',
          success: savedPath != null);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      _setStatus('PDF error: $e');
    }
  }

  // ── Download Restored Image ────────────────────────────────────────────────
  Future<void> _downloadRestoredImage() async {
    Uint8List? bytes = _previewBytes;
    final sourceText = (_generatedText ?? _textController.text).trim();

    if ((bytes == null || bytes.isEmpty) && sourceText.isNotEmpty) {
      try {
        bytes = _decodeImageBytes(sourceText);
      } catch (_) {
        // Keep null and handle as no image below.
      }
    }

    if (bytes == null || bytes.isEmpty) {
      _setStatus('No restored image available to download.');
      return;
    }

    final currentName = _fileName ?? _extractName(sourceText) ?? 'restored_image';
    final hasExt = RegExp(r'\.[^.]+$').hasMatch(currentName);
    final baseName = currentName.replaceAll(RegExp(r'\.[^.]+$'), '');
    final safeBase = baseName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final mime = _extractMime(sourceText);
    final extension = hasExt
        ? currentName.substring(currentName.lastIndexOf('.') + 1)
        : _extensionFromMime(mime);
    final suggestedName = '${safeBase}_restored.$extension';

    setState(() => _isBusy = true);
    try {
      final dir = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Choose folder to save restored image',
      );

      String? savedPath;
      if (dir != null && dir.isNotEmpty) {
        final output = File('$dir/$suggestedName');
        await output.writeAsBytes(bytes, flush: true);
        savedPath = output.path;
      }

      if (!mounted) return;
      setState(() => _isBusy = false);
      _setStatus(
        savedPath == null ? 'Download cancelled.' : 'Image saved → $savedPath',
        success: savedPath != null,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isBusy = false);
      _setStatus('Image download error: $e');
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────
  String _chunkTextForPdf(String input, {int chunkSize = 100}) {
    if (input.isEmpty || chunkSize <= 0) return input;
    final buf = StringBuffer();
    for (var i = 0; i < input.length; i += chunkSize) {
      final end = (i + chunkSize < input.length) ? i + chunkSize : input.length;
      buf.writeln(input.substring(i, end));
    }
    return buf.toString();
  }

  Map<String, dynamic> _prepareImageForEncoding({
    required Uint8List originalBytes,
    required String originalName,
    required String? extension,
  }) {
    final int qualityPercent = _imageQualityPercent.clamp(0, 100).toInt();
    final int sizePercent = _imageSizePercent.clamp(1, 100).toInt();
    final bool shouldTransform = qualityPercent < 100 || sizePercent < 100;

    if (!shouldTransform) {
      return {
        'bytes': originalBytes,
        'name': originalName,
        'mime': _guessMimeType(extension),
      };
    }

    final decoded = img.decodeImage(originalBytes);
    if (decoded == null) {
      return {
        'bytes': originalBytes,
        'name': originalName,
        'mime': _guessMimeType(extension),
      };
    }

    img.Image working = img.bakeOrientation(decoded);
    if (sizePercent < 100) {
      final double scale = sizePercent / 100.0;
      final int width = (working.width * scale).round().clamp(1, working.width);
      final int height = (working.height * scale).round().clamp(1, working.height);
      working = img.copyResize(
        working,
        width: width,
        height: height,
        interpolation: img.Interpolation.linear,
      );
    }

    final transformedBytes = Uint8List.fromList(
      img.encodeJpg(working, quality: qualityPercent),
    );
    final baseName = originalName.replaceAll(RegExp(r'\.[^.]+$'), '');

    return {
      'bytes': transformedBytes,
      'name': '${baseName}_q${qualityPercent}_s${sizePercent}.jpg',
      'mime': 'image/jpeg',
    };
  }

  Uint8List _decodeImageBytes(String input) {
    return base64Decode(_normalizeEncodedText(input));
  }

  String _normalizeEncodedText(String input) {
    final t = input.trim();
    if (t.startsWith('data:') && t.contains(',')) {
      return t.split(',').last.trim();
    }
    if (t.startsWith('{')) {
      final d = jsonDecode(t);
      if (d is Map<String, dynamic> && d['data'] is String) {
        return d['data'] as String;
      }
    }
    return t;
  }

  String? _extractName(String input) {
    try {
      final d = jsonDecode(input.trim());
      if (d is Map<String, dynamic>) {
        final n = d['name'];
        if (n is String && n.isNotEmpty) return n;
      }
    } catch (_) {}
    return null;
  }

  String? _extractMime(String input) {
    try {
      final d = jsonDecode(input.trim());
      if (d is Map<String, dynamic>) {
        final m = d['mime'];
        if (m is String && m.isNotEmpty) return m;
      }
    } catch (_) {}
    return null;
  }

  String _extensionFromMime(String? mime) {
    switch (mime?.toLowerCase()) {
      case 'image/jpeg':
        return 'jpg';
      case 'image/png':
        return 'png';
      case 'image/gif':
        return 'gif';
      case 'image/webp':
        return 'webp';
      case 'image/bmp':
        return 'bmp';
      case 'image/heic':
        return 'heic';
      default:
        return 'png';
    }
  }

  String _guessMimeType(String? ext) {
    switch (ext?.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'bmp':
        return 'image/bmp';
      case 'heic':
        return 'image/heic';
      default:
        return 'application/octet-stream';
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          // Ambient glow blobs
          Positioned(
            top: -120,
            left: -80,
            child: _GlowBlob(
              color: AppColors.accent.withValues(alpha: 0.15),
              size: 420,
            ),
          ),
          Positioned(
            bottom: -100,
            right: -60,
            child: _GlowBlob(
              color: AppColors.accentAlt.withValues(alpha: 0.12),
              size: 360,
            ),
          ),
          // Main content
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _TopBar(isBusy: _isBusy),
                            const SizedBox(height: 32),
                            _HeroBanner(
                              isBusy: _isBusy,
                              pulseAnim: _pulseAnim,
                              onPickImage: _pickImageAndEncode,
                              onDecode: _decodeTextToImage,
                              onCopy: _copyEncodedText,
                              onSavePdf: _saveEncodedTextAsFile,
                              onDownloadImage: _downloadRestoredImage,
                              onRefresh: _resetAll,
                              showCopied: _showCopiedBadge,
                            ),
                            const SizedBox(height: 18),
                            _EncodingControlsCard(
                              isBusy: _isBusy,
                              qualityPercent: _imageQualityPercent,
                              sizePercent: _imageSizePercent,
                              onQualityChanged: (value) => _onQualityChanged(value),
                              onSizeChanged: (value) => _onSizeChanged(value),
                            ),
                            const SizedBox(height: 28),
                            _StatusBar(
                              message: _statusMessage,
                              isSuccess: _isSuccess,
                              textLength: _liveCharCount,
                              fileName: _fileName,
                            ),
                            const SizedBox(height: 28),
                            LayoutBuilder(builder: (ctx, constraints) {
                              final wide = constraints.maxWidth >= 760;
                              final imgPanel = _ImagePreviewCard(
                                previewBytes: _previewBytes,
                                fadeAnim: _fadeAnim,
                                slideAnim: _slideAnim,
                              );
                              final fullText = (_generatedText ?? _textController.text).trim();
                              final blocks = fullText.length > kMaxEncodedChars
                                  ? _splitTextIntoBlocks(fullText, kMaxEncodedChars)
                                  : <String>[];

                              final textPanel = _TextEditorCard(
                                controller: _textController,
                                charCount: _liveCharCount,
                                splitBlocks: blocks,
                                onCopyBlock: (index) {
                                  final block = blocks[index];
                                  Clipboard.setData(ClipboardData(text: block));
                                  setState(() => _showCopiedBadge = true);
                                  Future.delayed(const Duration(seconds: 2),
                                      () => setState(() => _showCopiedBadge = false));
                                },
                                onChanged: (value) {
                                  setState(() {
                                    _liveCharCount = value.length;
                                    if (_generatedText != null &&
                                        value != _generatedText) {
                                      _generatedText = null;
                                    }
                                  });
                                },
                              );
                              if (wide) {
                                return IntrinsicHeight(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          children: [
                                            imgPanel,
                                            const SizedBox(height: 12),
                                            const _BlockSendingInstructions(),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 20),
                                      Expanded(child: textPanel),
                                    ],
                                  ),
                                );
                              }
                              return Column(children: [
                                imgPanel,
                                const SizedBox(height: 12),
                                const _BlockSendingInstructions(),
                                const SizedBox(height: 20),
                                textPanel,
                              ]);
                            }),
                            const SizedBox(height: 28),
                            const _HowItWorks(),
                            const SizedBox(height: 40),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Top Bar ──────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  const _TopBar({required this.isBusy});
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: const LinearGradient(
              colors: [AppColors.accent, AppColors.accentAlt],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Icon(Icons.photo_filter_rounded,
              color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PixelText Studio',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
            Text(
              'Image ↔ Text Encoder',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const Spacer(),
        if (isBusy)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.accent,
            ),
          ),
        
      ],
    );
  }
}

// ─── Hero Banner ─────────────────────────────────────────────────────────────
class _HeroBanner extends StatelessWidget {
  const _HeroBanner({
    required this.isBusy,
    required this.pulseAnim,
    required this.onPickImage,
    required this.onDecode,
    required this.onCopy,
    required this.onSavePdf,
    required this.onDownloadImage,
    required this.onRefresh,
    required this.showCopied,
  });

  final bool isBusy;
  final Animation<double> pulseAnim;
  final VoidCallback onPickImage;
  final VoidCallback onDecode;
  final VoidCallback onCopy;
  final VoidCallback onSavePdf;
  
  final VoidCallback onDownloadImage;
  final VoidCallback onRefresh;
  final bool showCopied;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.08),
            blurRadius: 40,
            
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          
          // Title row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [AppColors.accent, AppColors.accentAlt],
                      ).createShader(bounds),
                      child: const Text(
                        'Transform Images\nInto Portable Text',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Encode any image into a JSON text string. Copy it anywhere — email, chat, docs. Paste it back to restore the exact pixels.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        height: 1.55,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              ScaleTransition(
                scale: pulseAnim,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        AppColors.accent.withValues(alpha: 0.25),
                        AppColors.accentAlt.withValues(alpha: 0.15),
                      ],
                    ),
                    border: Border.all(
                        color: AppColors.accent.withValues(alpha: 0.4),
                        width: 1.5),
                  ),
                  child: const Icon(
                    Icons.swap_horiz_rounded,
                    color: AppColors.accent,
                    size: 32,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          // Divider
          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  AppColors.accent.withValues(alpha: 0.3),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Action buttons
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _ActionButton(
                label: 'Pick Image',
                icon: Icons.upload_rounded,
                gradient: const LinearGradient(
                  colors: [AppColors.accent, Color(0xFF9C77FF)],
                ),
                onTap: isBusy ? null : onPickImage,
              ),
              _ActionButton(
                label: 'Decode Text',
                icon: Icons.settings_backup_restore_rounded,
                gradient: const LinearGradient(
                  colors: [AppColors.accentAlt, Color(0xFF00A8A8)],
                ),
                onTap: isBusy ? null : onDecode,
              ),
              _ActionButton(
                label: showCopied ? 'Copied!' : 'Copy Text',
                icon: showCopied
                    ? Icons.check_circle_outline
                    : Icons.copy_rounded,
                gradient: LinearGradient(
                  colors: showCopied
                      ? [AppColors.success, const Color(0xFF16A34A)]
                      : [AppColors.card, AppColors.card],
                ),
                borderColor: showCopied ? null : AppColors.border,
                onTap: isBusy ? null : onCopy,
              ),
              _ActionButton(
                label: 'Save PDF',
                icon: Icons.picture_as_pdf_rounded,
                gradient: const LinearGradient(
                  colors: [AppColors.card, AppColors.card],
                ),
                borderColor: AppColors.border,
                onTap: isBusy ? null : onSavePdf,
              ),
              _ActionButton(
                label: 'Download Image',
                icon: Icons.download_rounded,
                gradient: const LinearGradient(
                  colors: [AppColors.card, AppColors.card],
                ),
                borderColor: AppColors.border,
                onTap: isBusy ? null : onDownloadImage,
              ),
              _ActionButton(
                label: 'Refresh',
                icon: Icons.refresh_rounded,
                gradient: const LinearGradient(
                  colors: [AppColors.card, AppColors.card],
                ),
                borderColor: AppColors.border,
                onTap: isBusy ? null : onRefresh,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.gradient,
    required this.onTap,
    this.borderColor,
  });

  final String label;
  final IconData icon;
  final Gradient gradient;
  final VoidCallback? onTap;
  final Color? borderColor;

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween<double>(begin: 1, end: 0.94).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: GestureDetector(
        onTapDown: (_) => _ctrl.forward(),
        onTapUp: (_) {
          _ctrl.reverse();
          widget.onTap?.call();
        },
        onTapCancel: () => _ctrl.reverse(),
        child: AnimatedOpacity(
          opacity: widget.onTap == null ? 0.4 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
            decoration: BoxDecoration(
              gradient: widget.gradient,
              borderRadius: BorderRadius.circular(14),
              border: widget.borderColor != null
                  ? Border.all(color: widget.borderColor!)
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 16, color: AppColors.textPrimary),
                const SizedBox(width: 8),
                Text(
                  widget.label,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Status Bar ───────────────────────────────────────────────────────────────
class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.message,
    required this.isSuccess,
    required this.textLength,
    required this.fileName,
  });

  final String? message;
  final bool isSuccess;
  final int textLength;
  final String? fileName;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _StatChip(
                  icon: Icons.text_fields_rounded,
                  label: '$textLength chars',
                  color: AppColors.accentAlt,
                ),
                _StatChip(
                  icon: Icons.insert_drive_file_rounded,
                  label: fileName ?? 'No file',
                  color: AppColors.accent,
                  maxLabelWidth: 230,
                ),
              ],
            ),
            if (message != null) ...[
              const SizedBox(height: 10),
              Container(
                height: 1,
                color: AppColors.border,
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    isSuccess
                        ? Icons.check_circle_rounded
                        : Icons.info_outline_rounded,
                    size: 15,
                    color: isSuccess
                        ? AppColors.success
                        : AppColors.warning,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      message!,
                      style: TextStyle(
                        color: isSuccess
                            ? AppColors.accentAlt
                            : AppColors.textSecondary,
                        fontSize: 12.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip(
      {required this.icon,
      required this.label,
      required this.color,
      this.maxLabelWidth});
  final IconData icon;
  final String label;
  final Color color;
  final double? maxLabelWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxLabelWidth ?? double.infinity,
            ),
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                  color: color,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Image Preview Card ───────────────────────────────────────────────────────
class _ImagePreviewCard extends StatelessWidget {
  const _ImagePreviewCard({
    required this.previewBytes,
    required this.fadeAnim,
    required this.slideAnim,
  });

  final Uint8List? previewBytes;
  final Animation<double> fadeAnim;
  final Animation<Offset> slideAnim;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Row(
              children: [
                const Icon(Icons.image_rounded,
                    size: 16, color: AppColors.accent),
                const SizedBox(width: 8),
                const Text(
                  'Image Preview',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                if (previewBytes != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Loaded',
                      style: TextStyle(
                          color: AppColors.success, fontSize: 11),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            height: 340,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: previewBytes == null
                  ? const _DropZonePlaceholder()
                  : FadeTransition(
                      opacity: fadeAnim,
                      child: SlideTransition(
                        position: slideAnim,
                        child: Image.memory(
                          previewBytes!,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                          width: double.infinity,
                          height: double.infinity,
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DropZonePlaceholder extends StatefulWidget {
  const _DropZonePlaceholder();

  @override
  State<_DropZonePlaceholder> createState() => _DropZonePlaceholderState();
}

class _DropZonePlaceholderState extends State<_DropZonePlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.6, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FadeTransition(
        opacity: _anim,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accent.withValues(alpha: 0.1),
                border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.3),
                    width: 1.5),
              ),
              child: const Icon(Icons.add_photo_alternate_outlined,
                  size: 32, color: AppColors.accent),
            ),
            const SizedBox(height: 16),
            const Text(
              'No image loaded',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            const Text(
              'Pick an image or decode encoded text',
              style: TextStyle(
                  color: AppColors.textSecondary, fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Text Editor Card ─────────────────────────────────────────────────────────
class _TextEditorCard extends StatelessWidget {
  const _TextEditorCard({
    required this.controller,
    required this.charCount,
    required this.onChanged,
    this.splitBlocks,
    this.onCopyBlock,
  });

  final TextEditingController controller;
  final int charCount;
  final ValueChanged<String> onChanged;
  final List<String>? splitBlocks;
  final ValueChanged<int>? onCopyBlock;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
            child: Row(
              children: [
                const Icon(Icons.code_rounded,
                    size: 16, color: AppColors.accentAlt),
                const SizedBox(width: 8),
                const Text(
                  'Encoded Text',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.accentAlt.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '$charCount chars',
                    style: TextStyle(
                      color: AppColors.accentAlt,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: TextField(
                controller: controller,
                minLines: 13,
                maxLines: 18,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 12,
                  fontFamily: 'monospace',
                  height: 1.6,
                ),
                decoration: InputDecoration(
                  hintText:
                      'Select an image to generate encoded text,\nor paste encoded JSON here to restore an image.',
                  hintStyle: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(16),
                ),
                onChanged: onChanged,
              ),
            ),
          ),
          if (splitBlocks != null && splitBlocks!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < splitBlocks!.length; i++)
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Text('Block ${i + 1}',
                                  style: const TextStyle(
                                      color: AppColors.accentAlt,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700)),
                              const Spacer(),
                              Text('${splitBlocks![i].length} chars',
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 12)),
                              const SizedBox(width: 8),
                              IconButton(
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                icon: const Icon(Icons.copy_rounded,
                                    size: 18, color: AppColors.accentAlt),
                                onPressed: onCopyBlock == null
                                    ? null
                                    : () => onCopyBlock!(i),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            splitBlocks![i],
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 11,
                              fontFamily: 'monospace',
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── How It Works ─────────────────────────────────────────────────────────────
class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    size: 16, color: AppColors.accent),
              ),
              const SizedBox(width: 10),
              const Text(
                'How It Works',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: _HowStep(
                  step: '01',
                  icon: Icons.upload_file_rounded,
                  title: 'Pick Image',
                  desc: 'Raw bytes are read from your local image file.',
                  color: AppColors.accent,
                ),
              ),
              const _StepArrow(),
              Expanded(
                child: _HowStep(
                  step: '02',
                  icon: Icons.data_object_rounded,
                  title: 'Encode',
                  desc: 'Bytes are base64-encoded inside a JSON payload.',
                  color: AppColors.accentAlt,
                ),
              ),
              const _StepArrow(),
              Expanded(
                child: _HowStep(
                  step: '03',
                  icon: Icons.restore_rounded,
                  title: 'Restore',
                  desc: 'Paste the text back to reconstruct the image exactly.',
                  color: const Color(0xFFF59E0B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HowStep extends StatelessWidget {
  const _HowStep({
    required this.step,
    required this.icon,
    required this.title,
    required this.desc,
    required this.color,
  });

  final String step;
  final IconData icon;
  final String title;
  final String desc;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(
                color: color.withValues(alpha: 0.35), width: 1.5),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(height: 10),
        Text(
          step,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          desc,
          style: const TextStyle(
              color: AppColors.textSecondary, fontSize: 11.5, height: 1.4),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _StepArrow extends StatelessWidget {
  const _StepArrow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Icon(Icons.arrow_forward_ios_rounded,
          color: AppColors.border, size: 16),
    );
  }
}

// ─── Glow Blob ────────────────────────────────────────────────────────────────
class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }
}

// ─── Compression Bottom Sheet ─────────────────────────────────────────────────
class _CompressionSheet extends StatefulWidget {
  const _CompressionSheet({
    required this.originalBytes,
    required this.fileName,
    required this.fileExtension,
    required this.originalEncodedLength,
    required this.guessMime,
    required this.onResult,
    required this.onCancel,
  });

  final Uint8List originalBytes;
  final String fileName;
  final String fileExtension;
  final int originalEncodedLength;
  final String Function(String?) guessMime;
  final void Function(Uint8List, String, String, String) onResult;
  final VoidCallback onCancel;

  @override
  State<_CompressionSheet> createState() => _CompressionSheetState();
}

class _CompressionSheetState extends State<_CompressionSheet> {
  bool _compressing = true;
  Map<String, dynamic>? _result;
  Timer? _ticker;
  int _tickCount = 0;
  int? _currentEncodedLength;
  ReceivePort? _receivePort;
  Isolate? _workerIsolate;

  static const List<String> _loadingStages = <String>[
    'Analyzing image bytes',
    'Optimizing quality settings',
    'Balancing size and clarity',
    'Preparing encoded payload',
  ];

  @override
  void initState() {
    super.initState();
    _startTicker();
    _runCompression();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _receivePort?.close();
    _workerIsolate?.kill(priority: Isolate.immediate);
    super.dispose();
  }

  void _startTicker() {
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (timer) {
      if (!mounted || !_compressing) {
        timer.cancel();
        return;
      }
      setState(() => _tickCount++);
    });
  }

  Future<void> _runCompression() async {
    _currentEncodedLength = widget.originalEncodedLength;
    _receivePort = ReceivePort();

    _receivePort!.listen((message) {
      if (!mounted || message is! Map) return;
      final type = message['type'];

      if (type == 'progress') {
        final nextLen = message['encodedLength'];
        if (nextLen is int) {
          setState(() => _currentEncodedLength = nextLen);
        }
        return;
      }

      if (type == 'result') {
        final res = message['result'];
        if (res is Map<String, dynamic>) {
          setState(() {
            _result = res;
            _compressing = false;
            _ticker?.cancel();
          });
        } else {
          setState(() {
            _compressing = false;
            _ticker?.cancel();
          });
        }
        _receivePort?.close();
        _receivePort = null;
        _workerIsolate?.kill(priority: Isolate.immediate);
        _workerIsolate = null;
        return;
      }

      if (type == 'error') {
        setState(() {
          _compressing = false;
          _ticker?.cancel();
        });
        _receivePort?.close();
        _receivePort = null;
        _workerIsolate?.kill(priority: Isolate.immediate);
        _workerIsolate = null;
      }
    });

    try {
      _workerIsolate = await Isolate.spawn(
        _compressImageWithProgressIsolate,
        {
          'sendPort': _receivePort!.sendPort,
          'imageBytes': widget.originalBytes,
          'fileName': widget.fileName,
        },
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _compressing = false;
          _ticker?.cancel();
        });
      }
      _receivePort?.close();
      _receivePort = null;
      _workerIsolate?.kill(priority: Isolate.immediate);
      _workerIsolate = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.compress_rounded,
                    color: AppColors.warning, size: 18),
              ),
              const SizedBox(width: 12),
              const Text(
                'Image Too Large',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'The image exceeds the 5,000-character limit when encoded. Choose an option below.',
            style: TextStyle(
                color: AppColors.textSecondary, fontSize: 13, height: 1.45),
          ),
          const SizedBox(height: 24),
          if (_compressing) ...[
            Center(
              child: Column(
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.92, end: 1.05),
                    duration: const Duration(milliseconds: 900),
                    curve: Curves.easeInOut,
                    builder: (context, value, child) {
                      return Transform.scale(scale: value, child: child);
                    },
                    child: Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            AppColors.accent.withValues(alpha: 0.25),
                            AppColors.accentAlt.withValues(alpha: 0.15),
                          ],
                        ),
                        border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.4),
                          width: 1.3,
                        ),
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(
                            color: AppColors.accentAlt,
                            strokeWidth: 3,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _loadingStages[(_tickCount ~/ 6) % _loadingStages.length],
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      _StatChip(
                        icon: Icons.text_fields_rounded,
                        label: 'Current: ${_currentEncodedLength ?? widget.originalEncodedLength} chars',
                        color: AppColors.warning,
                      ),
                      const _StatChip(
                        icon: Icons.flag_rounded,
                        label: 'Target: <= $kMaxEncodedChars chars',
                        color: AppColors.accentAlt,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: AnimatedFractionallySizedBox(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                        alignment: Alignment.centerLeft,
                        widthFactor: ((_tickCount % 32) + 1) / 32,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [AppColors.accent, AppColors.accentAlt],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Elapsed: ${(_tickCount * 0.25).toStringAsFixed(1)}s',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ] else if (_result != null) ...[
            // Info cards
            Row(
              children: [
                Expanded(
                  child: _InfoTile(
                    label: 'Original',
                    size: '${widget.originalBytes.length ~/ 1024} KB',
                    encoded: '${widget.originalEncodedLength} chars',
                    over: true,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _InfoTile(
                    label: 'Compressed',
                    size:
                        '${(_result!['compressedBytes'] as Uint8List).length ~/ 1024} KB',
                    encoded:
                        '${_result!['compressedEncodedLength']} chars',
                    over: (_result!['compressedEncodedLength'] as int) >
                        kMaxEncodedChars,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Options
            _SheetButton(
              label: 'Use Compressed Version',
              sub: (_result!['compressedEncodedLength'] as int) <=
                      kMaxEncodedChars
                  ? 'Fits within the 5,000-character limit ✓'
                  : 'Still exceeds limit, use with caution',
              icon: Icons.compress_rounded,
              color: AppColors.accentAlt,
              onTap: () {
                final cb =
                    _result!['compressedBytes'] as Uint8List;
                final cn = _result!['compressedName'] as String;
                final cm = _result!['compressedMime'] as String;
                final cLen =
                    _result!['compressedEncodedLength'] as int;
                final cWidth = (_result!['compressedWidth'] as int?) ?? 0;
                final cHeight = (_result!['compressedHeight'] as int?) ?? 0;
                final cQuality = (_result!['compressedQuality'] as int?) ?? 0;
                final compressedPayload = jsonEncode(<String, dynamic>{
                  'version': 1,
                  'name': cn,
                  'mime': cm,
                  'data': base64Encode(cb),
                });
                widget.onResult(
                  cb,
                  cn,
                  compressedPayload,
                  'Compressed to $cLen characters at ${cWidth}x$cHeight, quality $cQuality.',
                );
              },
            ),
            const SizedBox(height: 10),
            _SheetButton(
              label: 'Use Full Resolution',
              sub: 'Encoded text will be very long',
              icon: Icons.photo_rounded,
              color: AppColors.accent,
              onTap: () {
                final payload = jsonEncode(<String, dynamic>{
                  'version': 1,
                  'name': widget.fileName,
                  'mime': widget.guessMime(widget.fileExtension),
                  'data': base64Encode(widget.originalBytes),
                });
                widget.onResult(
                  widget.originalBytes,
                  widget.fileName,
                  payload,
                  'Full resolution — ${widget.originalEncodedLength} characters.',
                );
              },
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: widget.onCancel,
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.label,
    required this.size,
    required this.encoded,
    required this.over,
  });

  final String label;
  final String size;
  final String encoded;
  final bool over;

  @override
  Widget build(BuildContext context) {
    final color = over ? AppColors.danger : AppColors.success;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5)),
          const SizedBox(height: 6),
          Text(size,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700)),
          Text(encoded,
              style: TextStyle(color: color, fontSize: 11.5)),
        ],
      ),
    );
  }
}

class _SheetButton extends StatefulWidget {
  const _SheetButton({
    required this.label,
    required this.sub,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final String sub;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_SheetButton> createState() => _SheetButtonState();
}

class _SheetButtonState extends State<_SheetButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));
    _scale = Tween<double>(begin: 1, end: 0.96)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: GestureDetector(
        onTapDown: (_) => _ctrl.forward(),
        onTapUp: (_) {
          _ctrl.reverse();
          widget.onTap();
        },
        onTapCancel: () => _ctrl.reverse(),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: widget.color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: widget.color.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(widget.icon,
                    color: widget.color, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.label,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      widget.sub,
                      style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: widget.color, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _EncodingControlsCard extends StatelessWidget {
  const _EncodingControlsCard({
    required this.isBusy,
    required this.qualityPercent,
    required this.sizePercent,
    required this.onQualityChanged,
    required this.onSizeChanged,
  });

  final bool isBusy;
  final int qualityPercent;
  final int sizePercent;
  final ValueChanged<int> onQualityChanged;
  final ValueChanged<int> onSizeChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.tune_rounded, size: 16, color: AppColors.accentAlt),
              SizedBox(width: 8),
              Text(
                'Manual Encode Controls',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Lower quality or size to reduce encoded text character count.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
          ),
          const SizedBox(height: 14),
          _SliderRow(
            label: 'Image Quality',
            valueText: '$qualityPercent%',
            min: 0,
            max: 100,
            divisions: 100,
            value: qualityPercent.toDouble(),
            enabled: !isBusy,
            onChanged: (v) => onQualityChanged(v.round()),
          ),
          const SizedBox(height: 8),
          _SliderRow(
            label: 'Image Size',
            valueText: '$sizePercent%',
            min: 1,
            max: 100,
            divisions: 99,
            value: sizePercent.toDouble(),
            enabled: !isBusy,
            onChanged: (v) => onSizeChanged(v.round()),
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.valueText,
    required this.min,
    required this.max,
    required this.divisions,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final String valueText;
  final double min;
  final double max;
  final int divisions;
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              valueText,
              style: const TextStyle(
                color: AppColors.accentAlt,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: AppColors.accentAlt,
            inactiveTrackColor: AppColors.border,
            thumbColor: AppColors.accentAlt,
            overlayColor: AppColors.accentAlt.withValues(alpha: 0.15),
            trackHeight: 3,
          ),
          child: Slider(
            min: min,
            max: max,
            divisions: divisions,
            value: value,
            label: valueText,
            onChanged: enabled ? onChanged : null,
          ),
        ),
      ],
    );
  }
}

// ─── Block Sending Instructions ─────────────────────────────────────────────
class _BlockSendingInstructions extends StatelessWidget {
  const _BlockSendingInstructions();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.symmetric(horizontal: 0),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text('How to send encoded text in messenger:',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
          SizedBox(height: 8),
          Text('• The app splits the full encoded JSON into blocks of up to 5,000 characters each.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          SizedBox(height: 6),
          Text('• Label each block with its index (e.g. "Block 2/6") so the receiver can reassemble in order.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          SizedBox(height: 6),
          Text('• Use the copy icon for each block and paste/send them sequentially (1 → 2 → 3 …).',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          SizedBox(height: 6),
          Text('• After changing sliders, the blocks are re-generated — re-copy & resend the updated blocks.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}
