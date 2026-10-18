import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Brief, full-screen-overlay confetti burst.
///
/// Drop it as a `Positioned.fill` child of a `Stack` and rebuild with a new
/// [trigger] value (e.g. `ValueKey(_completed)`) when you want a fresh burst.
/// Particles fall under gravity, rotate, and fade. Cheap — one
/// AnimationController and a CustomPaint per active burst.
class ConfettiBurst extends StatefulWidget {
  /// Changing this value restarts the burst.
  final Object trigger;

  /// Number of particles. ~80 looks generous without dropping frames.
  final int count;

  /// Total burst duration including fade-out.
  final Duration duration;

  /// Colors picked from for each particle.
  final List<Color> colors;

  const ConfettiBurst({
    super.key,
    required this.trigger,
    this.count = 90,
    this.duration = const Duration(milliseconds: 2400),
    this.colors = const [
      Color(0xFFAF4C00),
      Color(0xFFD65C00),
      Color(0xFFF59E0B),
      Color(0xFF10B981),
      Color(0xFFFFFFFF),
      Color(0xFFFFC9A1),
    ],
  });

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late List<_Particle> _particles;
  final _rand = math.Random();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _spawn();
    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant ConfettiBurst old) {
    super.didUpdateWidget(old);
    if (old.trigger != widget.trigger) {
      _spawn();
      _controller
        ..reset()
        ..forward();
    }
  }

  void _spawn() {
    _particles = List.generate(widget.count, (_) {
      // Particles burst from the upper-third of the screen, spraying out
      // mostly downward with a slight horizontal spread.
      final originX = 0.5 + (_rand.nextDouble() - 0.5) * 0.25;
      final originY = 0.18 + (_rand.nextDouble() - 0.5) * 0.06;
      final angle = (-math.pi / 2) + (_rand.nextDouble() - 0.5) * math.pi;
      final speed = 0.7 + _rand.nextDouble() * 0.9;
      return _Particle(
        startX: originX,
        startY: originY,
        velocityX: math.cos(angle) * speed,
        velocityY: math.sin(angle) * speed,
        rotation: _rand.nextDouble() * 2 * math.pi,
        rotationSpeed: (_rand.nextDouble() - 0.5) * 6,
        size: 6.0 + _rand.nextDouble() * 6.0,
        color: widget.colors[_rand.nextInt(widget.colors.length)],
        shape: _rand.nextBool() ? _Shape.rect : _Shape.circle,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      // RepaintBoundary so the per-frame paint stays isolated from the
      // editor underneath.
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _ConfettiPainter(
              particles: _particles,
              t: _controller.value,
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

enum _Shape { rect, circle }

class _Particle {
  // All positions are in 0..1 of the canvas size, scaled at paint time.
  final double startX;
  final double startY;
  final double velocityX;
  final double velocityY;
  final double rotation;
  final double rotationSpeed;
  final double size;
  final Color color;
  final _Shape shape;
  _Particle({
    required this.startX,
    required this.startY,
    required this.velocityX,
    required this.velocityY,
    required this.rotation,
    required this.rotationSpeed,
    required this.size,
    required this.color,
    required this.shape,
  });
}

class _ConfettiPainter extends CustomPainter {
  final List<_Particle> particles;
  final double t; // 0..1

  _ConfettiPainter({required this.particles, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    if (t >= 1) return;
    // Gravity accelerates Y over time; fade after halfway.
    final gravity = 1.6 * t * t;
    final opacity = t < 0.7 ? 1.0 : (1.0 - (t - 0.7) / 0.3).clamp(0.0, 1.0);

    for (final p in particles) {
      final dx = (p.startX + p.velocityX * t) * size.width;
      final dy = (p.startY + p.velocityY * t + gravity) * size.height;
      if (dx < -20 || dx > size.width + 20 || dy > size.height + 40) continue;

      final paint = Paint()
        ..color = p.color.withOpacity(opacity)
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(p.rotation + p.rotationSpeed * t);

      if (p.shape == _Shape.circle) {
        canvas.drawCircle(Offset.zero, p.size * 0.5, paint);
      } else {
        final r = Rect.fromCenter(
          center: Offset.zero,
          width: p.size,
          height: p.size * 0.6,
        );
        canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(1.5)), paint);
      }

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) {
    return old.t != t || old.particles != particles;
  }
}
