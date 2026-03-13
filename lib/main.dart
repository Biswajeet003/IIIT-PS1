import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:async';
import 'package:video_player/video_player.dart';

void main() {
  runApp(const DemogorgonGameApp());
}

class DemogorgonGameApp extends StatelessWidget {
  const DemogorgonGameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'The Demogorgon Radar',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0A0A),
        fontFamily: 'Courier', 
      ),
      home: const OpeningScreen(),
    );
  }
}

// ==========================================
// REUSABLE COMPONENTS
// ==========================================

class NeonButton extends StatelessWidget {
  final String text;
  final Color color;
  final VoidCallback onPressed;
  final bool isFilled;

  const NeonButton({
    super.key,
    required this.text,
    required this.color,
    required this.onPressed,
    this.isFilled = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: isFilled ? color.withOpacity(0.2) : Colors.transparent,
          border: Border.all(color: color, width: 2),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.5),
              blurRadius: 10,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Text(
          text.toUpperCase(),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            shadows: [Shadow(color: color, blurRadius: 8)],
          ),
        ),
      ),
    );
  }
}

class RadarView extends StatefulWidget {
  final Color radarColor;
  const RadarView({super.key, required this.radarColor});

  @override
  State<RadarView> createState() => _RadarViewState();
}

class _RadarViewState extends State<RadarView> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: RadarPainter(
            sweepAngle: _controller.value * 2 * pi,
            color: widget.radarColor,
          ),
          child: Container(),
        );
      },
    );
  }
}

class RadarPainter extends CustomPainter {
  final double sweepAngle;
  final Color color;

  RadarPainter({required this.sweepAngle, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width / 2, size.height / 2);
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    // Draw Grid & Circles
    canvas.drawCircle(center, radius * 0.33, paint);
    canvas.drawCircle(center, radius * 0.66, paint);
    canvas.drawCircle(center, radius, paint);
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), paint);
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), paint);

    // Draw Sweep
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        colors: [Colors.transparent, color.withOpacity(0.6)],
        stops: const [0.8, 1.0],
        transform: GradientRotation(sweepAngle - pi / 2),
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, sweepPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ==========================================
// FEAR METER COMPONENT (SCALED TO 50%)
// ==========================================

class FearMeter extends StatefulWidget {
  final int currentFearLevel; 

  const FearMeter({super.key, required this.currentFearLevel});

  @override
  State<FearMeter> createState() => _FearMeterState();
}

class _FearMeterState extends State<FearMeter> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  // Heights halved from [18, 26, 34, 40, 44, 44, 40, 34, 26, 18]
  final List<double> segmentHeights = [9, 13, 17, 20, 22, 22, 20, 17, 13, 9];

  Widget _buildSegment(int index) {
    bool isActive = index < widget.currentFearLevel;
    Color baseColor;
    
    if (index < 3) {
      baseColor = const Color(0xFF22C55E); 
    } else if (index < 5) {
      baseColor = const Color(0xFFEAB308); 
    } else {
      baseColor = const Color(0xFFEF4444); 
    }

    return Container(
      width: 6, // Halved from 12
      height: segmentHeights[index],
      margin: const EdgeInsets.symmetric(horizontal: 1), // Halved from 2
      decoration: BoxDecoration(
        color: isActive ? baseColor : const Color(0xFF333333).withOpacity(0.3),
        border: Border.all(color: Colors.white.withOpacity(0.1), width: 0.5),
        boxShadow: isActive ? [BoxShadow(color: baseColor, blurRadius: index > 4 ? 4 : 2)] : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 130, // Halved from 260
      padding: const EdgeInsets.all(8), // Halved from 16
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF121212), Color(0xFF1A1A1A)],
        ),
        border: Border.all(color: const Color(0xFF444444), width: 1.5), // Halved from 3
        boxShadow: [
          const BoxShadow(color: Colors.black, blurRadius: 5, offset: Offset(0, 0)), 
          BoxShadow(color: Colors.black.withOpacity(0.7), blurRadius: 7.5, offset: const Offset(0, 2.5)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(bottom: 4), // Halved from 8
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white24)),
            ),
            child: const Text(
              "FEAR METER",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Courier',
                fontSize: 10, // Halved from 20
                fontWeight: FontWeight.bold,
                letterSpacing: 1, // Halved from 2
                color: Colors.white,
                shadows: [Shadow(color: Colors.black, blurRadius: 1, offset: Offset(0.5, 0.5))],
              ),
            ),
          ),
          const SizedBox(height: 8), // Halved from 16
          SizedBox(
            width: 110, // Halved from 220
            height: 40, // Halved from 80
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(10, (index) => _buildSegment(index)),
                  ),
                ),
                Positioned.fill(
                  child: CustomPaint(
                    painter: ArchPainter(),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4), // Halved from 8
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("STATUS", style: TextStyle(color: Colors.white70, fontSize: 6, fontFamily: 'Courier')),
                  Text("LOW", style: TextStyle(color: Colors.greenAccent, fontSize: 8, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
                ],
              ),
              Container(width: 0.5, height: 12, color: Colors.white24), // Halved from 24
              const Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text("THRESHOLD", style: TextStyle(color: Colors.white70, fontSize: 6, fontFamily: 'Courier')),
                  Text("HIGH", style: TextStyle(color: Colors.grey, fontSize: 8, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8), // Halved from 16
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 3), // Halved from 6
            decoration: BoxDecoration(
              color: Colors.black45,
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  "SIGNAL: ",
                  style: TextStyle(color: Colors.white60, fontSize: 8, fontFamily: 'Courier'),
                ),
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Opacity(
                      opacity: widget.currentFearLevel > 7 ? (0.3 + (_pulseController.value * 0.7)) : 0.3,
                      child: Text(
                        widget.currentFearLevel > 7 ? "UNSTABLE" : "STABLE",
                        style: TextStyle(
                          color: widget.currentFearLevel > 7 ? Colors.redAccent : Colors.greenAccent, 
                          fontSize: 8, 
                          fontWeight: FontWeight.bold, 
                          fontFamily: 'Courier'
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ArchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1; // Halved from 2

    final path = Path();
    // Path coordinates halved to match the new 110x40 scale
    path.moveTo(5, 35);
    path.quadraticBezierTo(size.width / 2, -5, size.width - 5, 35);
    
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ==========================================
// SCREENS
// ==========================================

// 1. OPENING SCREEN (Image + Radar + Text)
class OpeningScreen extends StatelessWidget {
  const OpeningScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          // 1. Bottom Layer: Static Background Image
          Image.asset(
            'assets/opening_screen_bg.png',
            fit: BoxFit.cover,
            color: Colors.black.withOpacity(0.3),
            colorBlendMode: BlendMode.darken,
          ),
          
          // 2. Middle Layer: Green Radar Sweep
          const RadarView(radarColor: Colors.greenAccent),
          
          // 3. Top Layer: Text & Buttons
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 60), 
              const Text(
                "ENTERING THE UPSIDE DOWN...",
                style: TextStyle(
                  color: Colors.redAccent, 
                  fontSize: 18, 
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(color: Colors.black, blurRadius: 10)]
                ),
              ),
              const SizedBox(height: 250), 
              NeonButton(
                text: "START GAME",
                color: Colors.redAccent,
                isFilled: true,
                onPressed: () {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LobbyScreen()));
                },
              ),
              const SizedBox(height: 20),
              const Text(
                "3... 2... 1...",
                style: TextStyle(
                  color: Colors.redAccent, 
                  fontSize: 24, 
                  fontWeight: FontWeight.bold,
                   shadows: [Shadow(color: Colors.black, blurRadius: 10)]
                ),
              ),
            ],
          )
        ],
      ),
    );
  }
}

// 2. LOBBY SCREEN (Video Player)
class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  late VideoPlayerController _videoController;

  @override
  void initState() {
    super.initState();
    _videoController = VideoPlayerController.asset('assets/interface1.mp4')
      ..initialize().then((_) {
        _videoController.setLooping(true);
        _videoController.play();
        setState(() {}); // Trigger rebuild once video is loaded
      });
  }

  @override
  void dispose() {
    _videoController.dispose();
    super.dispose();
  }

  void _startMatch() {
    final bool isDemogorgon = Random().nextBool(); 
    Navigator.pushReplacement(
      context, 
      MaterialPageRoute(builder: (_) => RoleRevealScreen(isDemogorgon: isDemogorgon))
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true, 
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("THE DEMOGORGON - RADAR", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Bottom Layer: Video Player
          if (_videoController.value.isInitialized)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _videoController.value.size.width,
                height: _videoController.value.size.height,
                child: VideoPlayer(_videoController),
              ),
            )
          else
            const Center(child: CircularProgressIndicator(color: Colors.redAccent)),

          // 2. Middle Layer: Dark Overlay for Readability
          Container(color: Colors.black.withOpacity(0.5)),

          // 3. Top Layer: Lobby UI
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Expanded(child: NeonButton(text: "CREATE GAME", color: Colors.redAccent, onPressed: () {})),
                      const SizedBox(width: 10),
                      Expanded(child: NeonButton(text: "JOIN GAME", color: Colors.grey, onPressed: () {})),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(border: Border.all(color: Colors.white54), color: Colors.black45),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text("ENTER CODE: _ _", style: TextStyle(fontSize: 18, color: Colors.white)),
                        SizedBox(width: 20),
                        Text("JOIN", style: TextStyle(fontSize: 18, color: Colors.grey)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(border: Border.all(color: Colors.white54), color: Colors.black45),
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: const [
                          Text("LOBBY", textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          Divider(color: Colors.grey),
                          ListTile(title: Text("1. YOU"), trailing: Text("HOST", style: TextStyle(color: Colors.greenAccent))),
                          ListTile(title: Text("2. PLAYER 2"), trailing: Text("READY", style: TextStyle(color: Colors.greenAccent))),
                          ListTile(title: Text("3. PLAYER 3"), trailing: Text("READY", style: TextStyle(color: Colors.greenAccent))),
                          ListTile(title: Text("4. PLAYER 4"), trailing: Text("READY", style: TextStyle(color: Colors.greenAccent))),
                          ListTile(title: Text("5. PLAYER 5"), trailing: Text("READY", style: TextStyle(color: Colors.greenAccent))),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: NeonButton(
                      text: "START MATCH",
                      color: Colors.redAccent,
                      isFilled: true,
                      onPressed: _startMatch,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 3. ROLE REVEAL SCREEN
class RoleRevealScreen extends StatefulWidget {
  final bool isDemogorgon;
  const RoleRevealScreen({super.key, required this.isDemogorgon});

  @override
  State<RoleRevealScreen> createState() => _RoleRevealScreenState();
}

class _RoleRevealScreenState extends State<RoleRevealScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 3), () {
      if (widget.isDemogorgon) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DemogorgonScreen()));
      } else {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SecurityScreen()));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              widget.isDemogorgon ? "YOU ARE THE DEMOGORGON" : "HAWKINS LAB SECURITY",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: widget.isDemogorgon ? Colors.redAccent : Colors.blueAccent,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              widget.isDemogorgon ? "► HUNT & KILL\n► SABOTAGE RADAR" : "► PLACE TRAPS\n► SURVIVE & CAPTURE",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }
}

// 4. SECURITY VIEW
class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  int _simulatedFearLevel = 0;
  late Timer _fearTimer;
  bool _isIncreasing = true;

  @override
  void initState() {
    super.initState();
    _fearTimer = Timer.periodic(const Duration(milliseconds: 600), (timer) {
      if (mounted) {
        setState(() {
          if (_isIncreasing) {
            _simulatedFearLevel++;
            if (_simulatedFearLevel >= 10) _isIncreasing = false;
          } else {
            _simulatedFearLevel--;
            if (_simulatedFearLevel <= 0) _isIncreasing = true;
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _fearTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const RadarView(radarColor: Colors.greenAccent),
          const Center(
            child: Text(
              "HAWKINS LAB",
              style: TextStyle(
                color: Colors.white54,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                backgroundColor: Colors.black45,
              ),
            ),
          ),
          if (_simulatedFearLevel > 7)
            Positioned(
              top: 60,
              left: 20,
              right: 20,
              child: Container(
                color: Colors.red.withOpacity(0.8),
                padding: const EdgeInsets.all(8),
                child: const Text(
                  "!! DEMOGORGON NEARBY !!",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          Positioned(
            bottom: 40,
            left: 20,
            child: FearMeter(currentFearLevel: _simulatedFearLevel), 
          ),
          Positioned(
            bottom: 40,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                NeonButton(text: "COLLECT TRAP", color: Colors.grey, onPressed: () {}),
                const SizedBox(height: 10),
                NeonButton(text: "PLACE TRAP", color: Colors.blueGrey, onPressed: () {}),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// 5. DEMOGORGON VIEW
class DemogorgonScreen extends StatelessWidget {
  const DemogorgonScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const RadarView(radarColor: Colors.redAccent),
          Positioned(
            top: 60,
            right: 20,
            child: NeonButton(text: "SABOTAGE", color: Colors.grey, onPressed: () {}),
          ),
          Center(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black87,
                border: Border.all(color: Colors.white54)
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: const Text(
                "GO TO RECOVERY POINT!",
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          Positioned(
            bottom: 40,
            right: 20,
            child: NeonButton(text: "HUNT MODE", color: Colors.redAccent, isFilled: true, onPressed: () {}),
          ),
        ],
      ),
    );
  }
}