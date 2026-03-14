import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'dart:math';
import 'dart:async';
import 'package:video_player/video_player.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mappls_gl/mappls_gl.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:vibration/vibration.dart'; // DIRECT MOTOR CONTROL

// ==========================================
// 1. THE GAME ENGINE (REAL-TIME GPS LOGIC)
// ==========================================
class GameEngine extends ChangeNotifier {
  bool isSabotageActive = false;
  
  Position? demogorgonPosition;
  Position? securityPosition;
  double distanceToMonster = 999.0; 
  int currentFearLevel = 0; 
  Timer? _heartbeatTimer; 

  int demogorgonSteps = 0; 
  bool isHuntModeActive = false;
  int huntActiveTime = 0;
  int huntCooldownTime = 0;
  bool blinkState = false; 

  bool isSabotageActiveState = false;
  int sabotageActiveTime = 0;
  int sabotageCooldownTime = 0;

  bool isRecoveryPhase = false; 

  int securitySteps = 0;
  int trapsInventory = 0;
  List<String> secureChatMessages = [
    "SYS: ENCRYPTED CHANNEL OPEN",
    "HQ: Find the supply crates."
  ];

  Position? arenaCenter;
  final double arenaRadius = 50.0; 
  bool isOutOfBounds = false;
  int outOfBoundsTimer = 60;
  Timer? deathTimer;
  
  bool isDead = false;
  String deathReason = ""; 

  List<LatLng> trapSpawnPoints = [];
  List<LatLng> activeTraps = []; 
  int trapInRangeIndex = -1; 

  // ========================================
  // REAL MULTIPLAYER LOBBY STATE
  // ========================================
  String currentRoomCode = "";
  List<String> lobbyPlayers = [];
  bool isHost = false;

  void hostGame() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    Random rnd = Random();
    currentRoomCode = String.fromCharCodes(Iterable.generate(4, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))));
    lobbyPlayers = ["1. YOU (HOST)"];
    isHost = true;
    notifyListeners();
  }

  void joinGame(String code) {
    if (code.isNotEmpty) {
      currentRoomCode = code.toUpperCase();
      lobbyPlayers = ["1. HOST", "2. YOU (READY)"]; 
      isHost = false;
      notifyListeners();
    }
  }

  void clearLobby() {
    currentRoomCode = "";
    lobbyPlayers = [];
    isHost = false;
    notifyListeners();
  }

  // ========================================
  // GEOFENCE & TRAP LOGIC
  // ========================================
  void initializeArena(Position center) {
    if (arenaCenter != null) return; 
    arenaCenter = center;

    trapSpawnPoints.add(LatLng(center.latitude, center.longitude));

    final random = Random();
    for (int i = 0; i < 49; i++) {
      double r = (50.0 / 111320.0) * sqrt(random.nextDouble());
      double theta = random.nextDouble() * 2 * pi;
      double latOffset = r * cos(theta);
      double lngOffset = r * sin(theta) / cos(center.latitude * pi / 180.0);

      trapSpawnPoints.add(LatLng(center.latitude + latOffset, center.longitude + lngOffset));
    }
    notifyListeners();
  }

  void _checkOutOfBounds(Position pos) {
    if (arenaCenter == null || isDead) return;

    double dist = Geolocator.distanceBetween(
        pos.latitude, pos.longitude, arenaCenter!.latitude, arenaCenter!.longitude);

    if (dist > arenaRadius) {
      if (!isOutOfBounds) {
        isOutOfBounds = true;
        outOfBoundsTimer = 60;
        
        // MOTOR CONTROL: Out of bounds warning
        Vibration.vibrate(pattern: [0, 500, 200, 500]);
        SystemSound.play(SystemSoundType.alert);

        deathTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          outOfBoundsTimer--;
          if (outOfBoundsTimer <= 0) {
            _triggerDeath("OUT OF BOUNDS");
            timer.cancel();
          }
          notifyListeners();
        });
      }
    } else {
      if (isOutOfBounds) {
        isOutOfBounds = false;
        deathTimer?.cancel();
        outOfBoundsTimer = 60;
        notifyListeners();
      }
    }
  }

  void _checkTrapProximity(Position pos) {
    int previousIndex = trapInRangeIndex;
    trapInRangeIndex = -1;
    
    for (int i = 0; i < trapSpawnPoints.length; i++) {
      double d = Geolocator.distanceBetween(
          pos.latitude, pos.longitude, trapSpawnPoints[i].latitude, trapSpawnPoints[i].longitude);
      if (d <= 5.0) {
        trapInRangeIndex = i;
        break;
      }
    }

    // MOTOR CONTROL: Double pulse when near a trap
    if (trapInRangeIndex != -1 && previousIndex == -1) {
      Vibration.vibrate(pattern: [0, 150, 100, 150]);
    }

    notifyListeners();
  }

  void collectTrap() {
    if (trapInRangeIndex != -1) {
      trapsInventory++;
      secureChatMessages.add("SYS: TRAP ACQUIRED");
      trapSpawnPoints.removeAt(trapInRangeIndex); 
      trapInRangeIndex = -1;
      
      // MOTOR CONTROL: Quick tap
      Vibration.vibrate(duration: 50);
      SystemSound.play(SystemSoundType.click);
      
      notifyListeners();
    }
  }

  void placeTrap() {
    if (trapsInventory > 0 && securityPosition != null) {
      trapsInventory--;
      activeTraps.add(LatLng(securityPosition!.latitude, securityPosition!.longitude));
      
      if (activeTraps.length > 2) {
        activeTraps.removeAt(0); 
      }
      
      secureChatMessages.add("SYS: TRAP DEPLOYED AT CURRENT GPS");
      
      // MOTOR CONTROL: Heavy thud
      Vibration.vibrate(duration: 300);
      
      notifyListeners();
    }
  }

  void updatePlayerPosition(Position pos, bool isDemogorgon) {
    if (arenaCenter == null) {
      initializeArena(pos); 
    }

    if (isDemogorgon) {
      demogorgonPosition = pos;
    } else {
      securityPosition = pos;
      _checkTrapProximity(pos); 
    }
    
    _checkOutOfBounds(pos);
    _calculateDistanceAndFear();
  }

  void spawnGhostPlayerForTesting(bool isDemogorgonView) {
    if (isDemogorgonView && demogorgonPosition != null) {
      double latOffset = 15 / 111320; 
      securityPosition = Position(
        latitude: demogorgonPosition!.latitude + latOffset,
        longitude: demogorgonPosition!.longitude,
        timestamp: DateTime.now(), accuracy: 1, altitude: 0, heading: 0, speed: 0, speedAccuracy: 0, altitudeAccuracy: 0, headingAccuracy: 0,
      );
      _calculateDistanceAndFear();
    } else if (!isDemogorgonView && securityPosition != null) {
      double latOffset = 80 / 111320; 
      demogorgonPosition = Position(
        latitude: securityPosition!.latitude + latOffset,
        longitude: securityPosition!.longitude,
        timestamp: DateTime.now(), accuracy: 1, altitude: 0, heading: 0, speed: 0, speedAccuracy: 0, altitudeAccuracy: 0, headingAccuracy: 0,
      );
      _calculateDistanceAndFear();
      sendChatMessage("SYS: DEV MOCK DEMOGORGON SPAWNED 80M NORTH");
    }
  }

  void _triggerDeath(String reason) {
    isDead = true;
    deathReason = reason;
    isHuntModeActive = false;
    huntActiveTime = 0;
    _heartbeatTimer?.cancel();
    
    // MOTOR CONTROL: Massive failure vibration
    Vibration.vibrate(pattern: [0, 1000, 500, 1000]);
    SystemSound.play(SystemSoundType.alert);
    
    notifyListeners();
  }

  void _calculateDistanceAndFear() {
    if (demogorgonPosition != null && securityPosition != null) {
      distanceToMonster = Geolocator.distanceBetween(
        securityPosition!.latitude,
        securityPosition!.longitude,
        demogorgonPosition!.latitude,
        demogorgonPosition!.longitude,
      );

      int previousFearLevel = currentFearLevel;

      if (distanceToMonster > 100) {
        currentFearLevel = 0; 
      } else if (distanceToMonster <= 10) {
        currentFearLevel = 10; 
      } else {
        currentFearLevel = 10 - ((distanceToMonster - 10) / 10).floor();
        currentFearLevel = currentFearLevel.clamp(0, 10);
      }

      // MOTOR CONTROL: THE FEAR HEARTBEAT
      if (currentFearLevel != previousFearLevel && !isDead) {
        _heartbeatTimer?.cancel();
        
        if (currentFearLevel > 0) {
          int pulseDelay = 1500 - (currentFearLevel * 120);
          pulseDelay = pulseDelay.clamp(300, 1500);

          _heartbeatTimer = Timer.periodic(Duration(milliseconds: pulseDelay), (timer) {
            Vibration.vibrate(duration: 150); // Distinct heartbeat thump
            if (currentFearLevel == 10) {
              SystemSound.play(SystemSoundType.alert);
            }
          });
        }
      }

      if (isHuntModeActive && distanceToMonster <= 2.0 && !isDead) {
        _triggerDeath("CAUGHT BY DEMOGORGON");
        _startHuntCooldown();
        sendChatMessage("SYS: AGENT ELIMINATED");
      }

      notifyListeners();
    }
  }

  void addEnergy(int steps, bool isDemogorgon) {
    if (isDemogorgon) {
      demogorgonSteps += steps;
    } else {
      securitySteps += steps;
    }
    notifyListeners();
  }

  void sendChatMessage(String message) {
    secureChatMessages.add("AGENT: $message");
    Vibration.vibrate(duration: 50); 
    notifyListeners();
  }

  // ========================================
  // TIME-BASED COOLDOWN LOGIC 
  // ========================================
  void activateHuntMode() {
    if (huntActiveTime == 0 && huntCooldownTime == 0 && !isRecoveryPhase) {
      isHuntModeActive = true;
      huntActiveTime = 10; 
      
      // MOTOR CONTROL: Aggressive alert
      Vibration.vibrate(duration: 600);
      SystemSound.play(SystemSoundType.alert);
      
      notifyListeners();

      Timer.periodic(const Duration(seconds: 1), (timer) {
        if (huntActiveTime > 0 && !isRecoveryPhase && isHuntModeActive) {
          huntActiveTime--;
          blinkState = !blinkState; 
          notifyListeners();
        } else {
          if (isHuntModeActive) {
            isHuntModeActive = false;
            huntActiveTime = 0;
            _startHuntCooldown();
          }
          timer.cancel();
        }
      });
    }
  }

  void _startHuntCooldown() {
    if (isRecoveryPhase) return;
    huntCooldownTime = 20; 
    notifyListeners();
    
    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (huntCooldownTime > 0) {
        huntCooldownTime--;
        notifyListeners();
      } else {
        Vibration.vibrate(duration: 200); // Ready Alert
        SystemSound.play(SystemSoundType.click);
        timer.cancel();
      }
    });
  }

  void triggerSabotage() {
    if (sabotageActiveTime == 0 && sabotageCooldownTime == 0 && !isRecoveryPhase) {
      isSabotageActiveState = true;
      isSabotageActive = true;
      sabotageActiveTime = 10; 

      // MOTOR CONTROL: Glitchy stutter effect
      Vibration.vibrate(pattern: [0, 100, 50, 100, 50, 300]);

      notifyListeners();

      Timer.periodic(const Duration(seconds: 1), (timer) {
        if (sabotageActiveTime > 0 && !isRecoveryPhase) {
          sabotageActiveTime--;
          notifyListeners();
        } else {
          isSabotageActive = false;
          isSabotageActiveState = false;
          sabotageActiveTime = 0;
          timer.cancel();
          _startSabotageCooldown();
        }
      });
    }
  }

  void _startSabotageCooldown() {
    if (isRecoveryPhase) return;
    sabotageCooldownTime = 20; 
    notifyListeners();

    Timer.periodic(const Duration(seconds: 1), (timer) {
      if (sabotageCooldownTime > 0) {
        sabotageCooldownTime--;
        notifyListeners();
      } else {
        Vibration.vibrate(duration: 200); // Ready Alert
        SystemSound.play(SystemSoundType.click);
        timer.cancel();
      }
    });
  }

  void triggerRecoveryPhase() {
    isRecoveryPhase = true;
    isHuntModeActive = false; 
    isSabotageActive = false;
    huntActiveTime = 0;
    sabotageActiveTime = 0;
    
    Vibration.vibrate(pattern: [0, 600, 200, 600]);
    SystemSound.play(SystemSoundType.alert);

    notifyListeners();

    Timer(const Duration(seconds: 30), () {
      isRecoveryPhase = false;
      notifyListeners();
    });
  }
}

final GameEngine gameEngine = GameEngine();

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
// ATMOSPHERIC UPSIDE DOWN SPORE SYSTEM
// ==========================================
class SporesOverlay extends StatefulWidget {
  const SporesOverlay({super.key});

  @override
  State<SporesOverlay> createState() => _SporesOverlayState();
}

class _SporesOverlayState extends State<SporesOverlay> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<Spore> _spores = [];
  final int _sporeCount = 150; 

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_spores.isEmpty) {
      final size = MediaQuery.of(context).size;
      final rand = Random();
      for (int i = 0; i < _sporeCount; i++) {
        _spores.add(Spore(
          x: rand.nextDouble() * size.width,
          y: rand.nextDouble() * size.height,
          size: rand.nextDouble() * 2 + 1, 
          speedY: rand.nextDouble() * 1.5 + 0.5, 
          wobbleOffset: rand.nextDouble() * pi * 2, 
          wobbleSpeed: rand.nextDouble() * 0.05 + 0.01,
        ));
      }
    }
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
        final size = MediaQuery.of(context).size;
        for (var spore in _spores) {
          spore.y -= spore.speedY; 
          spore.x += sin(spore.wobbleOffset) * 1.5; 
          spore.wobbleOffset += spore.wobbleSpeed;

          if (spore.y < 0) {
            spore.y = size.height;
            spore.x = Random().nextDouble() * size.width;
          }
        }
        return CustomPaint(
          size: size,
          painter: SporesPainter(_spores),
        );
      },
    );
  }
}

class Spore {
  double x, y, size, speedY, wobbleOffset, wobbleSpeed;
  Spore({
    required this.x, required this.y, required this.size, 
    required this.speedY, required this.wobbleOffset, required this.wobbleSpeed
  });
}

class SporesPainter extends CustomPainter {
  final List<Spore> spores;
  SporesPainter(this.spores);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black87 
      ..style = PaintingStyle.fill;
    
    for (var spore in spores) {
      canvas.drawCircle(Offset(spore.x, spore.y), spore.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
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
      onTap: () {
        Vibration.vibrate(duration: 30); // Tactical click for all UI buttons
        onPressed();
      },
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

class ThemedActionButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final int activeTime;
  final int cooldownTime;
  final VoidCallback onTap;
  final Color baseColor;

  const ThemedActionButton({
    super.key,
    required this.label,
    required this.isActive,
    required this.activeTime,
    required this.cooldownTime,
    required this.onTap,
    required this.baseColor,
  });

  @override
  Widget build(BuildContext context) {
    bool isReady = !isActive && cooldownTime == 0;
    double progress = isActive ? (activeTime / 10.0) : 0.0;
    
    Color ringColor = Colors.redAccent;
    if (progress > 0.5) {
      ringColor = Colors.greenAccent;
    } else if (progress > 0.2) {
      ringColor = Colors.yellowAccent;
    }

    return GestureDetector(
      onTap: isReady ? () {
        Vibration.vibrate(duration: 40);
        onTap();
      } : null,
      child: SizedBox(
        width: 80,
        height: 80,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isReady ? baseColor.withOpacity(0.15) : const Color(0xFF111111),
                border: Border.all(
                  color: isReady ? baseColor : Colors.white12,
                  width: 2,
                ),
                boxShadow: isReady ? [BoxShadow(color: baseColor.withOpacity(0.4), blurRadius: 10)] : null,
              ),
              child: Center(
                child: isActive
                    ? Text("$activeTime", style: TextStyle(color: ringColor, fontSize: 26, fontWeight: FontWeight.bold, fontFamily: 'Courier'))
                    : cooldownTime > 0
                        ? Text("${cooldownTime}s", style: const TextStyle(color: Colors.white30, fontSize: 18, fontFamily: 'Courier'))
                        : Text(label, textAlign: TextAlign.center, style: TextStyle(color: baseColor, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ),
            
            if (isActive)
              CircularProgressIndicator(
                value: progress,
                strokeWidth: 4,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(ringColor),
              ),
          ],
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
  final bool isDemogorgon;
  const LiveGameMap({super.key, required this.isDemogorgon});

  @override
  State<LiveGameMap> createState() => _LiveGameMapState();
}

class _LiveGameMapState extends State<LiveGameMap> {
  Position? _currentPosition;
  StreamSubscription<Position>? _positionStream;
  String _locationStatus = "ACQUIRING SENSORS...";

  MapplsMapController? _mapController;

  String _pedestrianStatus = 'UNKNOWN';
  int _initialSteps = -1; 
  int _currentSessionSteps = 0;
  late StreamSubscription<StepCount> _stepCountStream;
  late StreamSubscription<PedestrianStatus> _pedestrianStatusStream;

  @override
  void initState() {
    super.initState();
    gameEngine.addListener(_onEngineUpdate);
    _initAllSensors();
  }

  @override
  void dispose() {
    gameEngine.removeListener(_onEngineUpdate);
    _positionStream?.cancel();
    _stepCountStream.cancel();
    _pedestrianStatusStream.cancel();
    super.dispose();
  }

  void _onEngineUpdate() {
    _drawMapOverlays();
  }

  void _drawMapOverlays() {
    if (_mapController == null) return;
    
    _mapController!.clearCircles(); 
    
    if (gameEngine.arenaCenter != null) {
      _mapController!.addCircle(CircleOptions(
        geometry: LatLng(gameEngine.arenaCenter!.latitude, gameEngine.arenaCenter!.longitude),
        circleRadius: gameEngine.arenaRadius,
        circleColor: "#FF0000",
        circleOpacity: 0.1,
        circleStrokeWidth: 2,
        circleStrokeColor: "#FF0000"
      ));
    }

    if (!widget.isDemogorgon) {
      for (var spawnLocation in gameEngine.trapSpawnPoints) {
        _mapController!.addCircle(CircleOptions(
          geometry: spawnLocation,
          circleRadius: 1.5, 
          circleColor: "#00FF00", 
          circleOpacity: 0.6,
          circleStrokeWidth: 1,
          circleStrokeColor: "#FFFFFF"
        ));
      }

      for (var trapLocation in gameEngine.activeTraps) {
        _mapController!.addCircle(CircleOptions(
          geometry: trapLocation,
          circleRadius: 3.0, 
          circleColor: "#00E5FF", 
          circleOpacity: 0.8,
          circleStrokeWidth: 1,
          circleStrokeColor: "#FFFFFF"
        ));
      }
    }

    if (widget.isDemogorgon && gameEngine.isHuntModeActive && gameEngine.blinkState && gameEngine.securityPosition != null && !gameEngine.isDead) {
      _mapController!.addCircle(CircleOptions(
        geometry: LatLng(gameEngine.securityPosition!.latitude, gameEngine.securityPosition!.longitude),
        circleRadius: 2.0, 
        circleColor: "#FF3300", 
        circleOpacity: 0.9,
        circleStrokeWidth: 2,
        circleStrokeColor: "#FFFFFF"
      ));
    }
  }

  Future<void> _initAllSensors() async {
    if (await Permission.activityRecognition.request().isGranted) {
      _initPedometer();
    } else {
      if (mounted) setState(() => _locationStatus = "PHYSICAL SENSOR PERMISSION DENIED");
    }
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
            _initialSteps = event.steps; 
          }
          int newSteps = event.steps - _initialSteps;
          int stepDifference = newSteps - _currentSessionSteps;
          _currentSessionSteps = newSteps;
          
          if (stepDifference > 0) {
            gameEngine.addEnergy(stepDifference, widget.isDemogorgon);
          }
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
          gameEngine.updatePlayerPosition(position, widget.isDemogorgon);
        }
      });
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
        MapplsMap(
          initialCameraPosition: CameraPosition(
            target: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
            zoom: 19.0, 
          ),
          myLocationEnabled: true,
          compassEnabled: false,
          onMapCreated: (MapplsMapController controller) {
            _mapController = controller;
            _drawMapOverlays(); 
          },
        ),
        Positioned(
          top: 100, 
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
                    const Text("GPS ACCURACY: ", style: TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'Courier')),
                    Text("${_currentPosition!.accuracy.toStringAsFixed(1)}m", 
                      style: TextStyle(color: _currentPosition!.accuracy < 5 ? Colors.greenAccent : Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
                  ],
                ),
                Row(
                  children: [
                    const Text("PLAYER STATE: ", style: TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'Courier')),
                    Text(_pedestrianStatus, 
                      style: TextStyle(color: _pedestrianStatus == 'WALKING' ? Colors.greenAccent : Colors.yellowAccent, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
                  ],
                ),
                AnimatedBuilder(
                  animation: gameEngine,
                  builder: (context, child) {
                    return Row(
                      children: [
                        const Text("STEPS LOGGED: ", style: TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'Courier')),
                        Text("${widget.isDemogorgon ? gameEngine.demogorgonSteps : gameEngine.securitySteps}", 
                          style: const TextStyle(color: Colors.blueAccent, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'Courier')),
                      ],
                    );
                  }
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
              "FEAR METER (EMF)",
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
                  const Text("STATUS", style: TextStyle(color: Colors.white70, fontSize: 6)),
                  const Text("SAFE", style: TextStyle(color: Colors.greenAccent, fontSize: 8, fontWeight: FontWeight.bold)),
                ],
              ),
              Container(width: 0.5, height: 12, color: Colors.white24), 
              const Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text("PROXIMITY", style: TextStyle(color: Colors.white70, fontSize: 6)),
                  const Text("LETHAL", style: TextStyle(color: Colors.redAccent, fontSize: 8, fontWeight: FontWeight.bold)),
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
                color: Colors.cyanAccent, 
                isFilled: true,
                onPressed: () {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const OnlineMatchmakingScreen()));
                },
              ),
              const SizedBox(height: 20),
              NeonButton(
                text: "PLAY WITH FRIENDS",
                color: Colors.redAccent,
                isFilled: false,
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

class OnlineMatchmakingScreen extends StatefulWidget {
  const OnlineMatchmakingScreen({super.key});

  @override
  State<OnlineMatchmakingScreen> createState() => _OnlineMatchmakingScreenState();
}

class _OnlineMatchmakingScreenState extends State<OnlineMatchmakingScreen> {
  String _status = "CALIBRATING GPS...";
  final List<String> _foundPlayers = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _startMatchmakingSequence();
  }

  Future<void> _startMatchmakingSequence() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) setState(() => _status = "ERROR: TURN ON GPS TO FIND PLAYERS");
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) setState(() => _status = "ERROR: GPS PERMISSION DENIED");
        return;
      }
    }

    if (mounted) {
      setState(() {
        _status = "SCANNING 200M RADIUS FOR REAL PLAYERS...";
        _isSearching = true;
        _foundPlayers.add("1. YOU (HOST)");
      });
      Vibration.vibrate(duration: 50); // Initial scan ping
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Opacity(
            opacity: 0.1,
            child: Image.asset('assets/opening_screen_bg.png', fit: BoxFit.cover),
          ),
          
          const RadarView(radarColor: Colors.cyanAccent),

          SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.satellite_alt_rounded, color: Colors.cyanAccent, size: 60),
                  const SizedBox(height: 20),
                  
                  Text(
                    _status,
                    style: const TextStyle(color: Colors.cyanAccent, fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Courier'),
                  ),
                  const SizedBox(height: 10),
                  
                  if (_isSearching)
                    Text("Awaiting 5 players to start... (${_foundPlayers.length}/5)", 
                      style: const TextStyle(color: Colors.white54, fontSize: 12, fontFamily: 'Courier')),
                  
                  const SizedBox(height: 40),

                  Container(
                    width: 300,
                    height: 200,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      border: Border.all(color: Colors.cyanAccent.withOpacity(0.5)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ListView.builder(
                      itemCount: _foundPlayers.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Row(
                            children: [
                              const Icon(Icons.person, color: Colors.greenAccent, size: 16),
                              const SizedBox(width: 10),
                              Text(
                                _foundPlayers[index], 
                                style: const TextStyle(color: Colors.white, fontFamily: 'Courier', fontSize: 12)
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  
                  const SizedBox(height: 50),
                  
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      NeonButton(
                        text: "CANCEL",
                        color: Colors.redAccent,
                        isFilled: false,
                        onPressed: () {
                          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const OpeningScreen()));
                        },
                      ),
                      NeonButton(
                        text: "DEV: FORCE START",
                        color: Colors.greenAccent,
                        isFilled: true,
                        onPressed: () {
                          Vibration.vibrate(pattern: [0, 500, 200, 500]); // Match start heavy vibration
                          final bool isDemogorgon = Random().nextBool(); 
                          Navigator.pushReplacement(
                            context, 
                            MaterialPageRoute(builder: (_) => RoleRevealScreen(isDemogorgon: isDemogorgon))
                          );
                        },
                      )
                    ],
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  late VideoPlayerController _videoController;
  final TextEditingController _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    gameEngine.clearLobby(); 
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
    _codeController.dispose();
    super.dispose();
  }

  void _startMatch() {
    Vibration.vibrate(pattern: [0, 500, 200, 500]); // HAPTIC: Match start
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
          Container(color: Colors.black.withOpacity(0.6)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: AnimatedBuilder(
                animation: gameEngine,
                builder: (context, child) {
                  return Column(
                    children: [
                      if (gameEngine.currentRoomCode.isEmpty)
                        Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                Expanded(
                                  child: NeonButton(
                                    text: "CREATE GAME", 
                                    color: Colors.redAccent, 
                                    onPressed: () {
                                      gameEngine.hostGame();
                                    }
                                  )
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(border: Border.all(color: Colors.white54), color: Colors.black45),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text("ENTER CODE: ", style: TextStyle(fontSize: 16, color: Colors.white)),
                                  SizedBox(
                                    width: 80,
                                    child: TextField(
                                      controller: _codeController,
                                      maxLength: 4,
                                      textCapitalization: TextCapitalization.characters,
                                      style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, letterSpacing: 5),
                                      decoration: const InputDecoration(
                                        counterText: "",
                                        isDense: true,
                                        border: InputBorder.none,
                                        hintText: "____",
                                        hintStyle: TextStyle(color: Colors.white30)
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      Vibration.vibrate(duration: 30);
                                      gameEngine.joinGame(_codeController.text);
                                    },
                                    child: const Text("JOIN", style: TextStyle(fontSize: 18, color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.2), border: Border.all(color: Colors.redAccent)),
                          child: Text("ROOM CODE: ${gameEngine.currentRoomCode}", style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 4)),
                        ),
                      
                      const SizedBox(height: 30),
                      
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(border: Border.all(color: Colors.white54), color: Colors.black45),
                          child: Column(
                            children: [
                              const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text("LOBBY", textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                              ),
                              const Divider(color: Colors.grey),
                              Expanded(
                                child: gameEngine.lobbyPlayers.isEmpty
                                  ? const Center(child: Text("Waiting for connection...", style: TextStyle(color: Colors.white54, fontFamily: 'Courier')))
                                  : ListView.builder(
                                      padding: const EdgeInsets.all(16),
                                      itemCount: gameEngine.lobbyPlayers.length,
                                      itemBuilder: (context, index) {
                                        return ListTile(
                                          leading: const Icon(Icons.person_outline, color: Colors.greenAccent),
                                          title: Text(gameEngine.lobbyPlayers[index]),
                                          trailing: const Text("CONNECTED", style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontFamily: 'Courier')),
                                        );
                                      },
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      
                      if (gameEngine.isHost)
                        SizedBox(
                          width: double.infinity,
                          child: NeonButton(
                            text: "START MATCH",
                            color: Colors.redAccent,
                            isFilled: true,
                            onPressed: _startMatch,
                          ),
                        )
                      else if (gameEngine.currentRoomCode.isNotEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text("WAITING FOR HOST TO START...", style: TextStyle(color: Colors.yellowAccent, fontFamily: 'Courier')),
                        )
                    ],
                  );
                }
              ),
            ),
          ),
        ],
      ),
    );
  }
}

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
        Vibration.vibrate(duration: 400); // Heavy pulse on role reveal
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

class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  bool _isChatOpen = false; 
  final TextEditingController _chatController = TextEditingController();

  @override
  void dispose() {
    _chatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false, 
      body: Stack(
        fit: StackFit.expand,
        children: [
          const LiveGameMap(isDemogorgon: false),

          IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.0,
                  colors: [
                    const Color(0xFF101B2B).withOpacity(0.7), 
                    const Color(0xFF3A0000).withOpacity(0.8), 
                    const Color(0xFF000000).withOpacity(0.9), 
                  ],
                  stops: const [0.3, 0.7, 1.0],
                ),
                backgroundBlendMode: BlendMode.hardLight,
              ),
            ),
          ),

          const IgnorePointer(
            child: SporesOverlay(),
          ),

          AnimatedBuilder(
            animation: gameEngine,
            builder: (context, child) {
              if (gameEngine.isDead) {
                return Container(
                  color: Colors.black,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.dangerous, color: Colors.red, size: 80),
                        const SizedBox(height: 20),
                        const Text("YOU DIED", style: TextStyle(color: Colors.red, fontSize: 40, fontWeight: FontWeight.bold)),
                        Text(gameEngine.deathReason, style: const TextStyle(color: Colors.white54, fontSize: 20, letterSpacing: 5)),
                      ],
                    ),
                  ),
                );
              }

              List<Widget> overlays = [];

              if (gameEngine.isSabotageActive) {
                overlays.add(
                  Container(
                    color: Colors.redAccent.withOpacity(0.2),
                    child: const Center(
                      child: Text("SABOTAGE DETECTED // INTERFERENCE", 
                        style: TextStyle(color: Colors.red, fontSize: 24, fontWeight: FontWeight.bold, fontFamily: 'Courier', fontStyle: FontStyle.italic)),
                    ),
                  )
                );
              }

              if (gameEngine.isOutOfBounds) {
                overlays.add(
                  Positioned(
                    top: 100,
                    left: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.9),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Column(
                        children: [
                          const Text("WARNING: OUT OF BOUNDS", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                          Text("RETURN IN: ${gameEngine.outOfBoundsTimer}s", style: const TextStyle(color: Colors.yellowAccent, fontSize: 18, fontFamily: 'Courier', fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  )
                );
              }
              
              if (gameEngine.isHuntModeActive) {
                overlays.add(
                  Positioned(
                    top: 180,
                    left: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      color: Colors.orangeAccent.withOpacity(0.3),
                      child: const Text(
                        "LOCATION EXPOSED // DEMOGORGON IS HUNTING",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.orangeAccent, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1),
                      ),
                    ),
                  )
                );
              }

              return Stack(children: overlays);
            }
          ),

          const RadarView(radarColor: Colors.greenAccent),
          
          AnimatedBuilder(
            animation: gameEngine,
            builder: (context, child) {
              if (gameEngine.currentFearLevel == 10 && !gameEngine.isDead) {
                return Positioned(
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
                );
              }
              return const SizedBox.shrink();
            }
          ),

          Positioned(
            top: 60,
            left: 20,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent.withOpacity(0.5)),
              onPressed: () {
                Vibration.vibrate(duration: 30);
                gameEngine.spawnGhostPlayerForTesting(false);
              },
              child: const Text("DEV TEST: SPAWN MOCK DEMOGORGON", style: TextStyle(fontSize: 8, color: Colors.white)),
            ),
          ),

          if (!_isChatOpen)
            Positioned(
              top: 60,
              right: 20,
              child: GestureDetector(
                onTap: () {
                  Vibration.vibrate(duration: 30);
                  setState(() {
                    _isChatOpen = true;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    border: Border.all(color: Colors.blueAccent, width: 2),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Colors.blueAccent.withOpacity(0.5), blurRadius: 10)
                    ]
                  ),
                  child: const Icon(Icons.chat_outlined, color: Colors.blueAccent, size: 24),
                ),
              ),
            ),
          
          if (_isChatOpen)
            Positioned(
              top: 120,
              right: 20,
              child: Container(
                width: 240,
                height: 200,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.85),
                  border: Border.all(color: Colors.blueAccent.withOpacity(0.8)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("SECURE COMMS", style: TextStyle(color: Colors.blueAccent, fontSize: 10, fontFamily: 'Courier', fontWeight: FontWeight.bold)),
                        GestureDetector(
                          onTap: () {
                            Vibration.vibrate(duration: 30);
                            setState(() {
                              _isChatOpen = false;
                            });
                          },
                          child: const Icon(Icons.close, color: Colors.redAccent, size: 18),
                        ),
                      ],
                    ),
                    const Divider(color: Colors.blueAccent),
                    Expanded(
                      child: AnimatedBuilder(
                        animation: gameEngine,
                        builder: (context, child) {
                          return ListView.builder(
                            reverse: true, 
                            itemCount: gameEngine.secureChatMessages.length,
                            itemBuilder: (context, index) {
                              int reversedIndex = gameEngine.secureChatMessages.length - 1 - index;
                              String msg = gameEngine.secureChatMessages[reversedIndex];
                              bool isSys = msg.startsWith("SYS:");
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(msg, style: TextStyle(
                                  color: isSys ? Colors.yellowAccent : Colors.white70, 
                                  fontSize: 10, fontFamily: 'Courier'
                                )),
                              );
                            },
                          );
                        }
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _chatController,
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontFamily: 'Courier'),
                            decoration: const InputDecoration(
                              hintText: "Transmit...",
                              hintStyle: TextStyle(color: Colors.white30, fontSize: 10),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(vertical: 4),
                              border: InputBorder.none,
                            ),
                            onSubmitted: (value) {
                              if (value.isNotEmpty) {
                                gameEngine.sendChatMessage(value);
                                _chatController.clear();
                              }
                            },
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.send, color: Colors.blueAccent, size: 16),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () {
                            if (_chatController.text.isNotEmpty) {
                              gameEngine.sendChatMessage(_chatController.text);
                              _chatController.clear();
                            }
                          },
                        )
                      ],
                    )
                  ],
                ),
              ),
            ),

          Positioned(
            bottom: 40,
            left: 20,
            child: AnimatedBuilder(
              animation: gameEngine,
              builder: (context, child) {
                return FearMeter(currentFearLevel: gameEngine.currentFearLevel);
              }
            ),
          ),

          Positioned(
            bottom: 40,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                AnimatedBuilder(
                  animation: gameEngine,
                  builder: (context, child) {
                    bool canCollect = gameEngine.trapInRangeIndex != -1;
                    return NeonButton(
                      text: "COLLECT TRAP", 
                      color: canCollect ? Colors.greenAccent : Colors.grey, 
                      isFilled: canCollect, 
                      onPressed: () {
                        if (canCollect) gameEngine.collectTrap();
                      }
                    );
                  }
                ),
                const SizedBox(height: 10),
                AnimatedBuilder(
                  animation: gameEngine,
                  builder: (context, child) {
                    return NeonButton(
                      text: "PLACE TRAP (${gameEngine.trapsInventory})", 
                      color: gameEngine.trapsInventory > 0 ? Colors.blueAccent : Colors.blueGrey, 
                      onPressed: () {
                        gameEngine.placeTrap();
                      }
                    );
                  }
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DemogorgonScreen extends StatelessWidget {
  const DemogorgonScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const LiveGameMap(isDemogorgon: true),

          IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.0,
                  colors: [
                    const Color(0xFF101B2B).withOpacity(0.7), 
                    const Color(0xFF3A0000).withOpacity(0.8), 
                    const Color(0xFF000000).withOpacity(0.9), 
                  ],
                  stops: const [0.3, 0.7, 1.0],
                ),
                backgroundBlendMode: BlendMode.hardLight,
              ),
            ),
          ),

          const IgnorePointer(
            child: SporesOverlay(),
          ),

          AnimatedBuilder(
            animation: gameEngine,
            builder: (context, child) {
              List<Widget> overlays = [];

              if (gameEngine.isRecoveryPhase) {
                overlays.add(
                  Container(
                    color: Colors.red.withOpacity(0.3),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 60),
                          const SizedBox(height: 10),
                          const Text("SYSTEM FAILURE", style: TextStyle(color: Colors.redAccent, fontSize: 32, fontWeight: FontWeight.bold)),
                          const Text("RECOVERY PHASE ACTIVE", style: TextStyle(color: Colors.white, fontSize: 20, letterSpacing: 2)),
                          const SizedBox(height: 20),
                          const Text("PROCEED TO THE ASSIGNED LOCATION", style: TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Courier')),
                        ],
                      ),
                    ),
                  )
                );
              } else {
                overlays.add(const RadarView(radarColor: Colors.redAccent));
              }

              if (gameEngine.isOutOfBounds) {
                overlays.add(
                  Positioned(
                    top: 100,
                    left: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.9),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Column(
                        children: [
                          const Text("WARNING: OUT OF BOUNDS", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                          Text("RETURN IN: ${gameEngine.outOfBoundsTimer}s", style: const TextStyle(color: Colors.yellowAccent, fontSize: 18, fontFamily: 'Courier', fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  )
                );
              }

              return Stack(children: overlays);
            }
          ),

          Positioned(
            top: 60,
            left: 20,
            child: AnimatedBuilder(
              animation: gameEngine,
              builder: (context, child) {
                if (gameEngine.isRecoveryPhase || gameEngine.isDead) return const SizedBox.shrink();
                
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent.withOpacity(0.5)),
                      onPressed: () {
                        Vibration.vibrate(duration: 30);
                        gameEngine.spawnGhostPlayerForTesting(true);
                      },
                      child: const Text("DEV TEST: SPAWN MOCK AGENT (15M AWAY)", style: TextStyle(fontSize: 8, color: Colors.white)),
                    ),
                    const SizedBox(height: 5),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.withOpacity(0.5)),
                      onPressed: () {
                        Vibration.vibrate(duration: 30);
                        gameEngine.triggerRecoveryPhase();
                      },
                      child: const Text("DEV TEST: HIT TRAP", style: TextStyle(fontSize: 8, color: Colors.white)),
                    ),
                  ],
                );
              }
            ),
          ),

          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: AnimatedBuilder(
              animation: gameEngine,
              builder: (context, child) {
                if (gameEngine.isRecoveryPhase || gameEngine.isDead) return const SizedBox.shrink();

                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.85),
                    border: Border.all(color: Colors.redAccent.withOpacity(0.5), width: 2),
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: [
                      BoxShadow(color: Colors.redAccent.withOpacity(0.2), blurRadius: 15, spreadRadius: 2)
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ThemedActionButton(
                        label: "SABOTAGE",
                        isActive: gameEngine.isSabotageActive,
                        activeTime: gameEngine.sabotageActiveTime,
                        cooldownTime: gameEngine.sabotageCooldownTime,
                        onTap: () => gameEngine.triggerSabotage(),
                        baseColor: Colors.deepOrangeAccent,
                      ),
                      ThemedActionButton(
                        label: "HUNT",
                        isActive: gameEngine.isHuntModeActive,
                        activeTime: gameEngine.huntActiveTime,
                        cooldownTime: gameEngine.huntCooldownTime,
                        onTap: () => gameEngine.activateHuntMode(),
                        baseColor: Colors.redAccent,
                      ),
                    ],
                  ),
                );
              }
            ),
          ),
        ],
      ),
    );
  }
}