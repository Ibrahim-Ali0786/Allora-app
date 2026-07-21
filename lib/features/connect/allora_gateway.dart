import 'dart:math';

import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class AlloraGateway extends StatefulWidget {
  final VoidCallback onComplete;

  const AlloraGateway({super.key, required this.onComplete});

  @override
  State<AlloraGateway> createState() => _AlloraGatewayState();
}

class _AlloraGatewayState extends State<AlloraGateway> with SingleTickerProviderStateMixin {
  late final AnimationController _master;

  static const _platformIcons = [
    _PlatformDef('assets/images/whatsapp.png', Color(0xFF25D366), 0.0),
    _PlatformDef(null, Color(0xFF2AABEE), 1.0),
    _PlatformDef('assets/images/instagram.png', Color(0xFFE1306C), 2.0),
    _PlatformDef('assets/images/messenger.png', Color(0xFF0084FF), 3.0),
  ];

  @override
  void initState() {
    super.initState();
    _master = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6000),
    );
    _master.forward();
    _master.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete();
      }
    });
  }

  @override
  void dispose() {
    _master.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.allora;
    
    // We want the final background to be exactly c.canvas to seamlessly reveal
    // the ConnectNetworksScreen behind it.
    final finalCanvasColor = c.canvas;
    
    return Material(
      color: const Color(0xFF07080C), // Deep space black background
      child: AnimatedBuilder(
        animation: _master,
        builder: (context, _) {
          final t = _master.value;
          return Stack(
            fit: StackFit.expand,
            children: [
              // 1. Starfield / deep space particles
              if (t < 0.9) _buildSpaceParticles(t, c.accent),
              
              // 2. The Portal (scales massively as we enter)
              if (t > 0.15 && t < 1.0) _buildPortal(t, c, finalCanvasColor),
              
              // 3. Light Spill when opening (floods the screen before entry)
              if (t > 0.50 && t < 0.85) _buildLightSpill(t, c.accent),
              
              // 4. Icons flying in
              if (t > 0.30 && t < 0.65) _buildIcons(t),
              
              // 5. Welcome Text (Scene 1)
              if (t < 0.35) _buildWelcome(t, c),
              
              // 6. Preparing Text
              if (t > 0.20 && t < 0.60) _buildPreparingText(t, c),
              
              // 7. Warp Lines (Scene 5 - entering lightspeed)
              if (t > 0.65 && t < 0.95) _buildWarpLines(t, c.accent),
              
              // 8. Final Solid Fade (Just in case the scale doesn't perfectly cover)
              if (t > 0.85) _buildFinalFade(t, finalCanvasColor),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWelcome(double t, AlloraColors c) {
    final opacity = (t < 0.15) 
        ? (t / 0.15).clamp(0.0, 1.0) 
        : (1.0 - ((t - 0.15) / 0.20)).clamp(0.0, 1.0);
        
    return Positioned.fill(
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: c.accent.withValues(alpha: 0.5),
                      blurRadius: 40,
                      spreadRadius: 10,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Image.asset('assets/images/app_icon.png', fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Welcome to Allora',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your conversations, beautifully connected.',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreparingText(double t, AlloraColors c) {
    final opacity = (t < 0.30)
        ? ((t - 0.20) / 0.10).clamp(0.0, 1.0)
        : (1.0 - ((t - 0.50) / 0.10)).clamp(0.0, 1.0);
        
    final isConnecting = t > 0.40;
    
    return Positioned(
      bottom: MediaQuery.of(context).size.height * 0.15,
      left: 0,
      right: 0,
      child: Opacity(
        opacity: opacity,
        child: Column(
          children: [
            Text(
              isConnecting ? 'Connecting your conversations' : 'Preparing your workspace',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isConnecting ? 'Bringing everything together...' : 'Securing everything for you...',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPortal(double t, AlloraColors c, Color finalCanvasColor) {
    final fadeIn = ((t - 0.15) / 0.15).clamp(0.0, 1.0);
    final openProgress = ((t - 0.50) / 0.15).clamp(0.0, 1.0);
    
    // Scale starts at 1.0, then exponentially zooms in as we enter the portal
    final scaleProgress = ((t - 0.65) / 0.25).clamp(0.0, 1.0);
    // At scale 40.0, the opening of the door expands to be larger than the physical screen.
    final scale = 1.0 + (scaleProgress * scaleProgress * scaleProgress * 40.0);
    
    return Center(
      child: Transform.scale(
        scale: scale,
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.85,
          height: MediaQuery.of(context).size.height * 0.65,
          child: CustomPaint(
            painter: _NewGatewayPainter(
              opacity: fadeIn,
              openProgress: openProgress,
              accent: c.accent,
              insideColor: finalCanvasColor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLightSpill(double t, Color accent) {
    final openProgress = ((t - 0.50) / 0.15).clamp(0.0, 1.0);
    final scaleProgress = ((t - 0.65) / 0.20).clamp(0.0, 1.0);
    final spillOpacity = (openProgress * (1.0 - scaleProgress)).clamp(0.0, 1.0);
    
    return Positioned.fill(
      child: Center(
        child: Container(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              colors: [
                Colors.white.withValues(alpha: spillOpacity * 0.8),
                accent.withValues(alpha: spillOpacity * 0.4),
                Colors.transparent,
              ],
              radius: 0.6 + (openProgress * 0.4),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcons(double t) {
    // Icons appear at 0.30, converge, and disappear into the portal by 0.65
    final progress = ((t - 0.30) / 0.35).clamp(0.0, 1.0);
    
    return Stack(
      children: List.generate(_platformIcons.length, (i) {
        final def = _platformIcons[i];
        final delay = i * 0.1;
        final iconP = ((progress - delay) / (1.0 - delay)).clamp(0.0, 1.0);
        
        // Ease-in so they accelerate into the portal
        final eased = Curves.easeInQuint.transform(iconP);
        
        final startOffsets = [
          const Offset(-150, -200),
          const Offset(150, -200),
          const Offset(-150, 200),
          const Offset(150, 200),
        ];
        final start = startOffsets[i];
        final current = Offset(
          start.dx * (1 - eased),
          start.dy * (1 - eased),
        );
        
        // Fade out rapidly as they reach the center
        final opacity = (1.0 - (eased * 1.5)).clamp(0.0, 1.0);
        
        return Center(
          child: Transform.translate(
            offset: current,
            child: Opacity(
              opacity: opacity,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: def.color.withValues(alpha: 0.6), blurRadius: 20)
                  ],
                ),
                child: def.asset != null
                    ? ClipOval(
                        child: Image.asset(
                          def.asset!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _iconFallback(def.color, Icons.send_rounded),
                        ),
                      )
                    : _iconFallback(def.color, Icons.send_rounded),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _iconFallback(Color color, IconData icon) {
    return Container(
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(icon, color: Colors.white, size: 24),
    );
  }

  Widget _buildWarpLines(double t, Color accent) {
    final progress = ((t - 0.65) / 0.30).clamp(0.0, 1.0);
    return Positioned.fill(
      child: CustomPaint(
        painter: _WarpPainter(
          progress: progress,
          color: Colors.white, // bright white lines for warp speed
        ),
      ),
    );
  }

  Widget _buildFinalFade(double t, Color finalCanvasColor) {
    final progress = ((t - 0.85) / 0.15).clamp(0.0, 1.0);
    return Positioned.fill(
      child: Container(
        color: finalCanvasColor.withValues(alpha: progress),
      ),
    );
  }

  Widget _buildSpaceParticles(double t, Color accent) {
    return Positioned.fill(
      child: CustomPaint(
        painter: _SpacePainter(progress: t, color: accent),
      ),
    );
  }
}

class _PlatformDef {
  final String? asset;
  final Color color;
  final double index;
  const _PlatformDef(this.asset, this.color, this.index);
}

class _NewGatewayPainter extends CustomPainter {
  final double opacity;
  final double openProgress;
  final Color accent;
  final Color insideColor;

  _NewGatewayPainter({
    required this.opacity,
    required this.openProgress,
    required this.accent,
    required this.insideColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final archPath = Path();
    archPath.moveTo(0, size.height);
    archPath.lineTo(0, size.width / 2);
    archPath.arcToPoint(
      Offset(size.width, size.width / 2),
      radius: Radius.circular(size.width / 2),
      clockwise: true,
    );
    archPath.lineTo(size.width, size.height);
    archPath.close();

    canvas.save();
    canvas.clipPath(archPath);

    // 1. Draw the inside of the portal
    final insidePaint = Paint()..color = insideColor.withValues(alpha: opacity);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), insidePaint);

    // 2. Draw doors
    // Left and right doors split from the center outwards
    final doorWidth = (size.width / 2) * (1.0 - openProgress);
    if (doorWidth > 0.5) {
      final doorPaint = Paint()..color = const Color(0xFF12141D).withValues(alpha: opacity);
      
      // Left door
      canvas.drawRect(Rect.fromLTWH(0, 0, doorWidth, size.height), doorPaint);
      // Right door
      canvas.drawRect(Rect.fromLTWH(size.width - doorWidth, 0, doorWidth, size.height), doorPaint);

      // Glowing split edges where the doors meet
      final edgePaint = Paint()
        ..color = accent.withValues(alpha: opacity * (1.0 - openProgress))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
      canvas.drawLine(Offset(doorWidth, 0), Offset(doorWidth, size.height), edgePaint);
      canvas.drawLine(Offset(size.width - doorWidth, 0), Offset(size.width - doorWidth, size.height), edgePaint);
    }

    canvas.restore();

    // 3. Draw Arch frame
    final framePaint = Paint()
      ..color = accent.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;
    canvas.drawPath(archPath, framePaint);

    // 4. Outer glow (using thick low-alpha stroke for high FPS instead of heavy MaskFilter)
    final glowPaint = Paint()
      ..color = accent.withValues(alpha: opacity * 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16.0;
    canvas.drawPath(archPath, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _NewGatewayPainter old) => true;
}

class _WarpPainter extends CustomPainter {
  final double progress;
  final Color color;

  _WarpPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0 || progress >= 1) return;
    
    final cx = size.width / 2;
    final cy = size.height / 2;
    
    // Fade in rapidly, then out
    final opacity = (progress < 0.2 ? progress / 0.2 : (1 - progress) / 0.8).clamp(0.0, 1.0);
    
    final paint = Paint()
      ..color = color.withValues(alpha: opacity)
      ..style = PaintingStyle.stroke;

    // Use a fixed seed for stable, consistent lines
    final random = Random(42); 
    for (int i = 0; i < 80; i++) {
      final angle = random.nextDouble() * 2 * pi;
      
      // Distance from center
      final distOffset = random.nextDouble() * 300;
      final length = random.nextDouble() * 200 + 100;
      
      // Speed multiplier
      final speed = random.nextDouble() * 2.0 + 1.0;
      
      // R shoots outward rapidly based on progress
      final r = distOffset + (progress * 2000 * speed); 
      
      final p1 = Offset(cx + cos(angle) * r, cy + sin(angle) * r);
      final p2 = Offset(cx + cos(angle) * (r + length), cy + sin(angle) * (r + length));
      
      paint.strokeWidth = random.nextDouble() * 3 + 1;
      canvas.drawLine(p1, p2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _WarpPainter old) => true;
}

class _SpacePainter extends CustomPainter {
  final double progress;
  final Color color;
  
  _SpacePainter({required this.progress, required this.color});
  
  @override
  void paint(Canvas canvas, Size size) {
    final random = Random(123); // Static seed
    final paint = Paint();
    
    for (int i = 0; i < 50; i++) {
      final x = random.nextDouble() * size.width;
      // move downwards slowly
      final y = (random.nextDouble() * size.height + (progress * 200)) % size.height;
      final radius = random.nextDouble() * 2 + 0.5;
      final alpha = random.nextDouble() * 0.5 + 0.1;
      
      paint.color = color.withValues(alpha: alpha);
      canvas.drawCircle(Offset(x, y), radius, paint);
    }
  }
  
  @override
  bool shouldRepaint(covariant _SpacePainter old) => true;
}
