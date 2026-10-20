import 'package:flutter/material.dart';

const _previewBg = Color(0xFF0D1118);
const _previewNeon = Color(0xFFB36BFF);

/// Renderiza entidades inteiramente fictícias para testar o desenho do overlay.
/// Não lê a tela, memória, processos nem dados do jogo.
class EspDemoPreview extends StatelessWidget {
  const EspDemoPreview({
    super.key,
    required this.enabled,
    required this.showLine,
    required this.showBox,
    required this.showHealth,
    required this.showName,
    required this.showDistance,
  });

  final bool enabled;
  final bool showLine;
  final bool showBox;
  final bool showHealth;
  final bool showName;
  final bool showDistance;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _previewBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF302A3D)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                Icon(Icons.preview_rounded, color: _previewNeon, size: 17),
                SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'PRÉVIA FICTÍCIA',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                Text(
                  'DEMO',
                  style: TextStyle(
                    color: _previewNeon,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 176,
            child: CustomPaint(
              painter: _EspDemoPainter(
                enabled: enabled,
                showLine: showLine,
                showBox: showBox,
                showHealth: showHealth,
                showName: showName,
                showDistance: showDistance,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(9),
            child: Text(
              enabled
                  ? 'Desenho de exemplo — nenhuma entidade real é detectada.'
                  : 'Ative “ESP” para testar os elementos desenhados.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF9694A8), fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }
}

class _EspDemoPainter extends CustomPainter {
  const _EspDemoPainter({
    required this.enabled,
    required this.showLine,
    required this.showBox,
    required this.showHealth,
    required this.showName,
    required this.showDistance,
  });

  final bool enabled;
  final bool showLine;
  final bool showBox;
  final bool showHealth;
  final bool showName;
  final bool showDistance;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = _previewBg;
    canvas.drawRect(Offset.zero & size, background);

    final gridPaint = Paint()
      ..color = const Color(0xFF202633)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y < size.height; y += 24) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final centerPaint = Paint()
      ..color = const Color(0xFF454052)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(size.width / 2, 0),
      Offset(size.width / 2, size.height),
      centerPaint,
    );

    if (!enabled) {
      _drawText(
        canvas,
        'DEMO DESATIVADA',
        Offset(size.width / 2, size.height / 2),
        color: const Color(0xFF9694A8),
        fontSize: 11,
        centered: true,
      );
      return;
    }

    // Coordenadas fixas de demonstração; não são calculadas a partir do jogo.
    final targets = <_DemoTarget>[
      _DemoTarget(
        rect: Rect.fromLTWH(size.width * .19, size.height * .24, 38, 74),
        name: 'BOT A',
        distance: '12 m',
        health: .78,
      ),
      _DemoTarget(
        rect: Rect.fromLTWH(size.width * .64, size.height * .34, 34, 66),
        name: 'BOT B',
        distance: '24 m',
        health: .42,
      ),
    ];

    final linePaint = Paint()
      ..color = const Color(0xFF65F5B8)
      ..strokeWidth = 1.3;
    final boxPaint = Paint()
      ..color = const Color(0xFF65F5B8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;

    for (final target in targets) {
      if (showLine) {
        canvas.drawLine(
          Offset(size.width / 2, size.height - 2),
          Offset(target.rect.center.dx, target.rect.bottom),
          linePaint,
        );
      }
      if (showBox) {
        canvas.drawRect(target.rect, boxPaint);
      }
      if (showHealth) {
        final healthTrack = Rect.fromLTWH(
          target.rect.left - 6,
          target.rect.top,
          3,
          target.rect.height,
        );
        canvas.drawRect(
          healthTrack,
          Paint()..color = const Color(0xFF454052),
        );
        final healthHeight = healthTrack.height * target.health;
        canvas.drawRect(
          Rect.fromLTWH(
            healthTrack.left,
            healthTrack.bottom - healthHeight,
            healthTrack.width,
            healthHeight,
          ),
          Paint()..color = const Color(0xFF65F5B8),
        );
      }
      if (showName) {
        _drawText(
          canvas,
          target.name,
          Offset(target.rect.center.dx, target.rect.top - 9),
          color: const Color(0xFF65F5B8),
          fontSize: 9,
          centered: true,
        );
      }
      if (showDistance) {
        _drawText(
          canvas,
          target.distance,
          Offset(target.rect.center.dx, target.rect.bottom + 10),
          color: Colors.white,
          fontSize: 9,
          centered: true,
        );
      }
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset position, {
    required Color color,
    required double fontSize,
    bool centered = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      centered
          ? Offset(position.dx - painter.width / 2, position.dy - painter.height / 2)
          : position,
    );
  }

  @override
  bool shouldRepaint(covariant _EspDemoPainter oldDelegate) =>
      enabled != oldDelegate.enabled ||
      showLine != oldDelegate.showLine ||
      showBox != oldDelegate.showBox ||
      showHealth != oldDelegate.showHealth ||
      showName != oldDelegate.showName ||
      showDistance != oldDelegate.showDistance;
}

class _DemoTarget {
  const _DemoTarget({
    required this.rect,
    required this.name,
    required this.distance,
    required this.health,
  });

  final Rect rect;
  final String name;
  final String distance;
  final double health;
}
