import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:async';
import 'package:video_player/video_player.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mappls_gl/mappls_gl.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize MapmyIndia (Mappls) API Key
  MapplsAccountManager.setMapSDKKey('61cb0cffdca67fce832bcc83259aaad7');
  MapplsAccountManager.setRestAPIKey('61cb0cffdca67fce832bcc83259aaad7');
  MapplsAccountManager.setAtlasClientId('96dHZVzsAutaTno2lUch1XMHlBmuZKDim-9F0mKAaOynucoJEdWoqyOdRa5bQRqvxwT4i01btKKei45SoSZ4_PhxBLRTq785'); 
  MapplsAccountManager.setAtlasClientSecret('lrFxI-iSEg9JWugB3ipnaxJBFtfAXsNsg-XiolwskiuM5eykqhfe6DVQ-UIpSVHu4TH6OSWvuG4_Up-Am2RH4w_ILfmmznWHLnDVwFMWgHc=');

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
        fontFamily: 'Benguiat', 
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

    canvas.drawCircle(center, radius * 0.33, paint);
    canvas.drawCircle(center, radius * 0.66, paint);
    canvas.drawCircle(center, radius, paint);
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), paint);
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), paint);

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
// HIGH PRECISION MAP & SENSOR EXTRACTION WIDGET
// ==========================================
class LiveGameMap extends StatefulWidget {
  const LiveGameMap({super.key});

  @override
  State<LiveGameMap> createState() => _LiveGameMapState();
}

class _LiveGameMapState extends State<LiveGameMap> {
  // GPS State
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  String _locationStatus = "ACQUIRING SENSORS...";

  // Pedometer State
  String _pedestrianStatus = 'UNKNOWN';
  int _initialSteps = -1; // To calculate steps taken this session
  int _currentSessionSteps = 0;
  late StreamSubscription<StepCount> _stepCountStream;
  late StreamSubscription<PedestrianStatus> _pedestrianStatusStream;

  @override
  void initState() {
    super.initState();
    _initAllSensors();
  }

  Future<void> _initAllSensors() async {
    // 1. Request Physical Activity Permissions (for Pedometer)
    if (await Permission.activityRecognition.request().isGranted) {
      _initPedometer();
    } else {
      if (mounted) setState(() => _locationStatus = "PHYSICAL SENSOR PERMISSION DENIED");
    }

    // 2. Initialize Ultra-High Precision GPS Stream
    _startPreciseLocationStream();
  }

  void _initPedometer() {
    _pedestrianStatusStream = Pedometer.pedestrianStatusStream.listen((status) {
      if (mounted) setState(() => _pedestrianStatus = status.status.toUpperCase());
    });

    _stepCountStream = Pedometer.stepCountStream.listen((event) {
      if (mounted) {
        setState(() {
          if (_initialSteps == -1) {
            _initialSteps = event.steps; // Capture baseline steps at game start
          }
          _currentSessionSteps = event.steps - _initialSteps;
        });
      }
    });
  }

  Future<void> _startPreciseLocationStream() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) setState(() => _locationStatus = "ERROR: GPS SERVICES DISABLED");
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) setState(() => _locationStatus = "ERROR: LOCATION PERMISSION DENIED");
        return;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      if (mounted) setState(() => _locationStatus = "ERROR: PERMISSIONS PERMANENTLY DENIED");
      return;
    } 

    if (mounted) setState(() => _locationStatus = "CALIBRATING HIGH PRECISION (< 1m)...");
    
    // CONSTANT STREAM FOR MILITARY PRECISION (distanceFilter: 0 updates on every micro-movement)
    LocationSettings locationSettings = const LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation, 
      distanceFilter: 0, 
    );

    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings)
      .listen((Position position) {
        if (mounted) {
          setState(() {
            _currentPosition = position;
          });
        }
      });
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _stepCountStream.cancel();
    _pedestrianStatusStream.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_currentPosition == null) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Colors.redAccent),
              const SizedBox(height: 16),
              Text(
                _locationStatus,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent, fontFamily: 'Benguiat', fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        // THE MAP LAYER
        MapplsMap(
          initialCameraPosition: CameraPosition(
            target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
            zoom: 18.0, 
          ),
          myLocationEnabled: true,
          compassEnabled: false,
        ),

        // HARDWARE SENSOR HUD OVERLAY
        Positioned(
          top: 100, // Lowered to avoid overlapping top UI elements
          left: 10,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black87,
              border: Border.all(color: const Color(0xFF333333), width: 2),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10)],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("SYS // SENSOR TELEMETRY", style: TextStyle(color: Colors.white54, fontSize: 8, fontFamily: 'Courier')),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text("GPS ACCURACY: ", style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'Courier')),
                    Text("${_currentPosition!.accuracy.toStringAsFixed(1)}m", 
                      style: TextStyle(color: _currentPosition!.accuracy < 5 ? Colors.greenAccent : Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
                  ],
                ),
                Row(
                  children: [
                    Text("PLAYER STATE: ", style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'Courier')),
                    Text(_pedestrianStatus, 
                      style: TextStyle(color: _pedestrianStatus == 'WALKING' ? Colors.greenAccent : Colors.yellowAccent, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
                  ],
                ),
                Row(
                  children: [
                    Text("MOVES DETECTED: ", style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'Courier')),
                    Text("$_currentSessionSteps", style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ==========================================
// FEAR METER COMPONENT 
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
      width: 6, 
      height: segmentHeights[index],
      margin: const EdgeInsets.symmetric(horizontal: 1), 
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
      width: 130, 
      padding: const EdgeInsets.all(8), 
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF121212), Color(0xFF1A1A1A)],
        ),
        border: Border.all(color: const Color(0xFF444444), width: 1.5), 
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
            padding: const EdgeInsets.only(bottom: 4), 
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white24)),
            ),
            child: const Text(
              "FEAR METER",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10, 
                fontWeight: FontWeight.bold,
                letterSpacing: 1, 
                color: Colors.white,
                shadows: [Shadow(color: Colors.black, blurRadius: 1, offset: Offset(0.5, 0.5))],
              ),
            ),
          ),
          const SizedBox(height: 8), 
          SizedBox(
            width: 110, 
            height: 40, 
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
          const SizedBox(height: 4), 
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("STATUS", style: TextStyle(color: Colors.white70, fontSize: 6)),
                  Text("LOW", style: TextStyle(color: Colors.greenAccent, fontSize: 8, fontWeight: FontWeight.bold)),
                ],
              ),
              Container(width: 0.5, height: 12, color: Colors.white24), 
              const Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text("THRESHOLD", style: TextStyle(color: Colors.white70, fontSize: 6)),
                  Text("HIGH", style: TextStyle(color: Colors.grey, fontSize: 8, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8), 
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 3), 
            decoration: BoxDecoration(
              color: Colors.black45,
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  "SIGNAL: ",
                  style: TextStyle(color: Colors.white60, fontSize: 8),
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
      ..strokeWidth = 1; 

    final path = Path();
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

// 1. OPENING SCREEN
class OpeningScreen extends StatelessWidget {
  const OpeningScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          Image.asset(
            'assets/opening_screen_bg.png',
            fit: BoxFit.cover,
            color: Colors.black.withOpacity(0.3),
            colorBlendMode: BlendMode.darken,
          ),
          const RadarView(radarColor: Colors.greenAccent),
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
              const SizedBox(height: 200), 
              NeonButton(
                text: "START ONLINE",
                color: Colors.grey, 
                isFilled: false,
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Online Matchmaking Server Offline. Try 'Play with Friends'.", style: TextStyle(fontFamily: 'Benguiat')),
                      backgroundColor: Colors.redAccent,
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              NeonButton(
                text: "PLAY WITH FRIENDS",
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
  late VideoPlayerController _videoController;

  @override
  void initState() {
    super.initState();
    _videoController = VideoPlayerController.asset('assets/interface1.mp4')
      ..initialize().then((_) {
        _videoController.setLooping(true);
        _videoController.play();
        setState(() {}); 
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
          Container(color: Colors.black.withOpacity(0.5)),
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

class _RoleRevealScreenState extends State<RoleRevealScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _flipAnimation;
  
  bool _showFront = false; 
  String _statusText = "ESTABLISHING NEURAL LINK...";
  Color _statusColor = Colors.grey;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500), 
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 2), 
      end: Offset.zero,          
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOutBack),
    ));

    _flipAnimation = Tween<double>(
      begin: 0,
      end: pi, 
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.5, 0.9, curve: Curves.easeInOut),
    ));

    _flipAnimation.addListener(() {
      if (_flipAnimation.value >= pi / 2 && !_showFront) {
        setState(() {
          _showFront = true;
          _statusText = widget.isDemogorgon ? "STATUS: ACTIVE // HUNT" : "STATUS: ACTIVE // DEFEND";
          _statusColor = widget.isDemogorgon ? Colors.redAccent : Colors.blueAccent;
        });
      }
    });

    _controller.forward();

    Timer(const Duration(milliseconds: 4500), () {
      if (mounted) {
        if (widget.isDemogorgon) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DemogorgonScreen()));
        } else {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const SecurityScreen()));
        }
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String cardBackAsset = 'assets/card_back.jpeg'; 
    final String cardFrontAsset = widget.isDemogorgon 
        ? 'assets/Demogorgan.png' 
        : 'assets/Hawkins lab security.png';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Opacity(
            opacity: 0.2,
            child: Image.asset('assets/opening_screen_bg.png', fit: BoxFit.cover),
          ),
          
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SlideTransition(
                position: _slideAnimation,
                child: Column(
                  children: [
                    const Text(
                      "HAWKINS NATIONAL LABORATORY // PROJECT O.S.",
                      style: TextStyle(color: Colors.white24, fontSize: 10, letterSpacing: 1),
                    ),
                    const SizedBox(height: 20),
                    
                    AnimatedBuilder(
                      animation: _flipAnimation,
                      builder: (context, child) {
                        final Matrix4 transform = Matrix4.identity()
                          ..setEntry(3, 2, 0.001) 
                          ..rotateY(_flipAnimation.value);

                        return Transform(
                          transform: transform,
                          alignment: Alignment.center,
                          child: child,
                        );
                      },
                      child: Container(
                        width: 250, 
                        height: 350,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A1A),
                          border: Border.all(color: _showFront ? _statusColor : Colors.white24, width: 3),
                          boxShadow: [
                            BoxShadow(color: _showFront ? _statusColor.withOpacity(0.5) : Colors.black54, blurRadius: 20, spreadRadius: 5)
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: _showFront 
                            ? Transform(
                                alignment: Alignment.center,
                                transform: Matrix4.rotationY(pi), 
                                child: Image.asset(
                                  cardFrontAsset,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : Image.asset(
                                cardBackAsset,
                                fit: BoxFit.cover,
                              ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 40),
                    
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 300),
                      style: TextStyle(
                        color: _statusColor,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                        shadows: _showFront ? [Shadow(color: _statusColor, blurRadius: 10)] : null,
                      ),
                      child: Text(_statusText),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
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
        fit: StackFit.expand,
        children: [
          // 1. BOTTOM LAYER: The Live High-Precision MapmyIndia Map
          const LiveGameMap(),

          // 2. DIMMING LAYER: To maintain the spooky, dark UI vibe
          Container(
            color: Colors.black.withOpacity(0.5),
          ),

          // 3. RADAR LAYER: Sweeping over the real-world map
          const RadarView(radarColor: Colors.greenAccent),
          
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
        fit: StackFit.expand,
        children: [
          // 1. BOTTOM LAYER: The Live High-Precision MapmyIndia Map
          const LiveGameMap(),

          // 2. DIMMING LAYER: To maintain the spooky, dark UI vibe
          Container(
            color: Colors.black.withOpacity(0.5),
          ),

          // 3. RADAR LAYER: Sweeping over the real-world map
          const RadarView(radarColor: Colors.redAccent),

          Positioned(
            top: 60,
            right: 20,
            child: NeonButton(text: "SABOTAGE", color: Colors.grey, onPressed: () {}),
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