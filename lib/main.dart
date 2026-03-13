import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:async';

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
// SCREENS
// ==========================================

// 1. OPENING SCREEN
class OpeningScreen extends StatelessWidget {
  const OpeningScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        alignment: Alignment.center,
        children: [
          const RadarView(radarColor: Colors.greenAccent),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                "ENTERING THE UPSIDE DOWN...",
                style: TextStyle(color: Colors.redAccent, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 40),
              NeonButton(
                text: "START GAME",
                color: Colors.redAccent,
                isFilled: true,
                onPressed: () {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LobbyScreen()));
                },
              ),
            ],
          )
        ],
      ),
    );
  }
}

// 2. LOBBY SCREEN
class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  // Mock logic to simulate starting the match and assigning roles
  void _startMatch() {
    // 1 in 5 chance to be the Demogorgon (or 50/50 for testing)
    final bool isDemogorgon = Random().nextBool(); 

    Navigator.pushReplacement(
      context, 
      MaterialPageRoute(builder: (_) => RoleRevealScreen(isDemogorgon: isDemogorgon))
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("THE DEMOGORGON - RADAR", style: TextStyle(color: Colors.redAccent)),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: Padding(
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
              decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
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
                decoration: BoxDecoration(border: Border.all(color: Colors.grey)),
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
    );
  }
}

// 3. ROLE REVEAL SCREEN (Transition)
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
    // Show role for 3 seconds, then navigate to actual gameplay UI
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
class SecurityScreen extends StatelessWidget {
  const SecurityScreen({super.key});

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
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                color: Colors.black87,
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("FEAR METER", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  SizedBox(height: 10),
                  Row(children: [Text("LOW ", style: TextStyle(color: Colors.greenAccent)), Text(" HIGH", style: TextStyle(color: Colors.redAccent))]),
                ],
              ),
            ),
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