import 'package:flutter/material.dart';

import '../models/app_settings.dart';
import '../services/image_processing_service.dart';

/// Kameranın üstüne çizilen vesikalık / biyometrik maske.
///
/// * **e-Okul & Yaka Kartı**: yarı saydam karartma + 3:4 çerçeve + nişanlar.
/// * **Biyometrik**: aynı maskeye ek olarak animasyonlu (nefes alan) kafa
///   elipsi, neon göz hizası bandı, tepe/çene sınırları, dikey simetri
///   ekseni ve artı hedefi.
///
/// Çerçeve geometrisi [GuideGeometry] ile hesaplanır — kırpma da aynı
/// fonksiyonu kullandığı için ekranda görünen alan birebir kaydedilir.
class GuideOverlay extends StatefulWidget {
  final String? instruction;
  final CaptureMode mode;

  const GuideOverlay({
    super.key,
    this.instruction,
    this.mode = CaptureMode.eokul,
  });

  @override
  State<GuideOverlay> createState() => _GuideOverlayState();
}

class _GuideOverlayState extends State<GuideOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    if (widget.mode == CaptureMode.biometric) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant GuideOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.mode == CaptureMode.biometric) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  double get _aspect {
    switch (widget.mode) {
      case CaptureMode.biometric:
        return 5 / 6;
      case CaptureMode.eokul:
      case CaptureMode.badge:
        return 3 / 4;
    }
  }

  @override
  Widget build(BuildContext context) {
    final biometric = widget.mode == CaptureMode.biometric;

    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = Rect.fromLTWH(
          0,
          0,
          constraints.maxWidth,
          constraints.maxHeight,
        );
        final frame = GuideGeometry.frameInside(screen, aspect: _aspect);

        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _ScrimPainter(frame: frame)),
            ),
            Positioned.fromRect(
              rect: frame,
              child: biometric
                  ? AnimatedBuilder(
                      animation: _pulse,
                      builder: (context, _) => CustomPaint(
                        painter: _BiometricFramePainter(
                          progress: _pulse.value,
                        ),
                      ),
                    )
                  : const CustomPaint(painter: _FramePainter()),
            ),
            // Etiketler (yalnızca e-Okul / Yaka Kartı).
            if (!biometric) ...[
              Positioned(
                left: frame.left,
                top: frame.top + frame.height * 0.18 - 9,
                child: const _LineLabel(text: 'Baş üstü'),
              ),
              Positioned(
                left: frame.left,
                top: frame.top + frame.height * 0.72 - 9,
                child: const _LineLabel(text: 'Çene'),
              ),
            ],
            if (widget.instruction != null)
              Positioned(
                left: 24,
                right: 24,
                top: frame.bottom + 18,
                child: Text(
                  widget.instruction!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Ortak çizimler
// -----------------------------------------------------------------------------

class _LineLabel extends StatelessWidget {
  final String text;

  const _LineLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

void _dashed(
  Canvas canvas,
  Offset from,
  Offset to,
  Paint paint, {
  double dash = 7,
  double gap = 6,
}) {
  final total = (to - from).distance;
  if (total <= 0) return;
  final dir = (to - from) / total;

  var travelled = 0.0;
  while (travelled < total) {
    final end = (travelled + dash).clamp(0.0, total);
    canvas.drawLine(from + dir * travelled, from + dir * end, paint);
    travelled += dash + gap;
  }
}

/// Çerçevenin dışı karartılır.
class _ScrimPainter extends CustomPainter {
  final Rect frame;

  _ScrimPainter({required this.frame});

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(frame, const Radius.circular(20)))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(
      scrim,
      Paint()..color = Colors.black.withValues(alpha: 0.58),
    );
  }

  @override
  bool shouldRepaint(covariant _ScrimPainter oldDelegate) =>
      oldDelegate.frame != frame;
}

void _cornerMarks(Canvas canvas, Size size, double r, double len, Paint p) {
  canvas.drawLine(Offset(0, r + len), Offset(0, r), p);
  canvas.drawLine(Offset(r, 0), Offset(r + len, 0), p);

  canvas.drawLine(Offset(size.width - r - len, 0), Offset(size.width - r, 0), p);
  canvas.drawLine(Offset(size.width, r), Offset(size.width, r + len), p);

  canvas.drawLine(
      Offset(0, size.height - r - len), Offset(0, size.height - r), p);
  canvas.drawLine(Offset(r, size.height), Offset(r + len, size.height), p);

  canvas.drawLine(Offset(size.width - r - len, size.height),
      Offset(size.width - r, size.height), p);
  canvas.drawLine(Offset(size.width, size.height - r - len),
      Offset(size.width, size.height - r), p);
}

/// e-Okul / Yaka Kartı çerçevesi: çerçeve + nişanlar + yüz hizaları.
class _FramePainter extends CustomPainter {
  const _FramePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(20)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = Colors.white.withValues(alpha: 0.85),
    );

    final corner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = Colors.white;
    _cornerMarks(canvas, size, 20, 26, corner);

    final guide = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;

    _dashed(
      canvas,
      Offset(0, size.height * 0.18),
      Offset(size.width, size.height * 0.18),
      guide,
    );
    _dashed(
      canvas,
      Offset(0, size.height * 0.72),
      Offset(size.width, size.height * 0.72),
      guide,
    );
    _dashed(
      canvas,
      Offset(size.width * 0.10, size.height * 0.86),
      Offset(size.width * 0.90, size.height * 0.86),
      guide..color = Colors.white.withValues(alpha: 0.35),
    );

    // Yüzü öneren soluk oval.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height * 0.45),
        width: size.width * 0.52,
        height: size.height * 0.54,
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Colors.white.withValues(alpha: 0.18),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Biyometrik stüdyo çerçevesi: nefes alan kafa elipsi, neon göz bandı,
/// tepe/çene sınırları, simetri ekseni ve artı hedefi.
class _BiometricFramePainter extends CustomPainter {
  /// Animasyon durumu 0..1 (nefes).
  final double progress;

  const _BiometricFramePainter({required this.progress});

  static const Color neon = Color(0xFF3DFFB0);
  static const Color cyan = Color(0xFF4FC3FF);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    // Dış çerçeve.
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(20)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..color = cyan.withValues(alpha: 0.95),
    );

    final corner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = neon;
    _cornerMarks(canvas, size, 20, 28, corner);

    final cx = size.width / 2;

    // --- Nefes alan kafa elipsi ------------------------------------------
    // progress 0..1 → ölçek 0.985..1.015 aralığında yumuşak salınım.
    final breathe = 0.985 + 0.03 * progress;

    final headW = size.width * 0.62;
    final headH = size.height * 0.62;
    final headCenter = Offset(cx, size.height * 0.42);

    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..color = neon.withValues(alpha: 0.10 * (0.6 + 0.4 * progress));
    final headRect = Rect.fromCenter(
      center: headCenter,
      width: headW * breathe,
      height: headH * breathe,
    );

    canvas.drawOval(headRect, glow);
    canvas.drawOval(
      headRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..color = neon.withValues(alpha: 0.9),
    );

    // --- Omuz kılavuzu ----------------------------------------------------
    final shoulderY = size.height * 0.88;
    final shoulderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..color = cyan.withValues(alpha: 0.85);

    canvas.drawPath(
      Path()
        ..moveTo(size.width * 0.12, shoulderY)
        ..cubicTo(
          size.width * 0.28,
          shoulderY - size.height * 0.10,
          size.width * 0.38,
          shoulderY - size.height * 0.14,
          cx,
          shoulderY - size.height * 0.14,
        )
        ..cubicTo(
          size.width * 0.62,
          shoulderY - size.height * 0.14,
          size.width * 0.72,
          shoulderY - size.height * 0.10,
          size.width * 0.88,
          shoulderY,
        ),
      shoulderPaint,
    );

    // --- Göz hizası bandı (neon şerit) ------------------------------------
    // ICAO'da gözler yüzün yaklaşık %42-45'inde; çerçeve içinde %38'de.
    final bandTop = size.height * 0.36;
    final bandHeight = size.height * 0.075;

    final bandRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(size.width * 0.06, bandTop, size.width * 0.88, bandHeight),
      const Radius.circular(8),
    );

    canvas.drawRRect(
      bandRect,
      Paint()..color = neon.withValues(alpha: 0.16 + 0.08 * progress),
    );
    canvas.drawRRect(
      bandRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = neon.withValues(alpha: 0.95),
    );

    _tag(
      canvas,
      text: 'GÖZ HİZASI',
      at: Offset(size.width * 0.06 + 6, bandTop - 20),
      color: neon,
    );

    // --- Tepe / çene sınırları (kesikli) ----------------------------------
    final dashedThin = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.75);

    final crownY = size.height * 0.16;
    final chinY = size.height * 0.66;

    _dashed(
      canvas,
      Offset(size.width * 0.16, crownY),
      Offset(size.width * 0.84, crownY),
      dashedThin,
    );
    _dashed(
      canvas,
      Offset(size.width * 0.16, chinY),
      Offset(size.width * 0.84, chinY),
      dashedThin,
    );

    _tag(
      canvas,
      text: 'TEPE',
      at: Offset(size.width * 0.16, crownY - 22),
      color: Colors.white70,
    );
    _tag(
      canvas,
      text: 'ÇENE',
      at: Offset(size.width * 0.16, chinY + 6),
      color: Colors.white70,
    );

    // --- Dikey simetri ekseni ---------------------------------------------
    _dashed(
      canvas,
      Offset(cx, size.height * 0.10),
      Offset(cx, size.height * 0.72),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..strokeCap = StrokeCap.round
        ..color = cyan.withValues(alpha: 0.6),
      dash: 6,
      gap: 7,
    );

    // --- Artı (+) hedefi (yüz merkezi) ------------------------------------
    final target = Offset(cx, size.height * 0.44);
    final arm = 12.0;
    final plusPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = neon;

    canvas.drawLine(
        target - Offset(arm, 0), target + Offset(arm, 0), plusPaint);
    canvas.drawLine(
        target - Offset(0, arm), target + Offset(0, arm), plusPaint);
    canvas.drawCircle(target, arm + 5, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = neon.withValues(alpha: 0.5));
  }

  void _tag(
    Canvas canvas, {
    required String text,
    required Offset at,
    required Color color,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          shadows: const [
            Shadow(blurRadius: 6, color: Colors.black87),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(covariant _BiometricFramePainter oldDelegate) =>
      oldDelegate.progress != progress;
}
