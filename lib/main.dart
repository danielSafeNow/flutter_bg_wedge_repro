import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_background_geolocation/flutter_background_geolocation.dart" as bg;

const Duration _wedgeThreshold = Duration(seconds: 10);

void _log(String tag, String message) {
  final timestamp = DateTime.now().toIso8601String();
  // print() lands in logcat tagged "flutter"; the inline tag lets you grep precisely.
  // ignore: avoid_print
  print("[$tag] $timestamp $message");
}

@pragma("vm:entry-point")
Future<void> headlessTask(bg.HeadlessEvent event) async {
  _log("Headless", "event.fired {name:${event.name}}");
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WedgeReproApp());
  bg.BackgroundGeolocation.registerHeadlessTask(headlessTask);
}

class WedgeReproApp extends StatelessWidget {
  const WedgeReproApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: "BG Wedge Repro",
      home: ReproHomePage(),
    );
  }
}

class ReproHomePage extends StatefulWidget {
  const ReproHomePage({super.key});

  @override
  State<ReproHomePage> createState() => _ReproHomePageState();
}

class _ReproHomePageState extends State<ReproHomePage> {
  bool _listenersInstalled = false;
  String _phase = "boot";
  String _readyResult = "—";
  String _startResult = "—";
  DateTime? _startReturnedAt;
  DateTime? _lastMainIsolateEventAt;
  final Map<String, int> _counts = <String, int>{
    "onLocation": 0,
    "onMotionChange": 0,
    "onHeartbeat": 0,
    "onHttp": 0,
    "onEnabledChange": 0,
    "onActivityChange": 0,
    "onProviderChange": 0,
  };
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _installListenersOnce();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    unawaited(_boot());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _installListenersOnce() {
    if (_listenersInstalled) return;
    _listenersInstalled = true;
    bg.BackgroundGeolocation.onLocation(
      (bg.Location loc) => _bump("onLocation", "accuracy=${loc.coords.accuracy}"),
    );
    bg.BackgroundGeolocation.onMotionChange(
      (bg.Location loc) => _bump("onMotionChange", "isMoving=${loc.isMoving}"),
    );
    bg.BackgroundGeolocation.onHeartbeat(
      (bg.HeartbeatEvent _) => _bump("onHeartbeat", ""),
    );
    bg.BackgroundGeolocation.onHttp(
      (bg.HttpEvent e) => _bump("onHttp", "status=${e.status}"),
    );
    bg.BackgroundGeolocation.onEnabledChange(
      (bool enabled) => _bump("onEnabledChange", "enabled=$enabled"),
    );
    bg.BackgroundGeolocation.onActivityChange(
      (bg.ActivityChangeEvent e) => _bump("onActivityChange", "type=${e.activity}"),
    );
    bg.BackgroundGeolocation.onProviderChange(
      (bg.ProviderChangeEvent e) => _bump("onProviderChange", "enabled=${e.enabled}"),
    );
    _log("LocationService", "listenersInstalledOnce");
  }

  void _bump(String name, String detail) {
    _lastMainIsolateEventAt = DateTime.now();
    _counts[name] = (_counts[name] ?? 0) + 1;
    _log("LocationService", "$name.received {$detail}");
    if (mounted) setState(() {});
  }

  Future<void> _boot() async {
    setState(() => _phase = "requesting permission");
    final permission = await bg.BackgroundGeolocation.requestPermission();
    _log("InitBG", "permission.returned $permission");

    setState(() => _phase = "ready");
    final state = await bg.BackgroundGeolocation.ready(
      bg.Config(
        foregroundService: true,
        reset: true,
        desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,
        distanceFilter: 0,
        stationaryRadius: 0,
        disableElasticity: false,
        locationAuthorizationRequest: "WhenInUse",
        disableLocationAuthorizationAlert: true,
        allowIdenticalLocations: true,
        fastestLocationUpdateInterval: 0,
        autoSync: false,
        heartbeatInterval: 10,
        enableHeadless: true,
        startOnBoot: false,
        stopOnTerminate: true,
        preventSuspend: false,
        stopOnStationary: true,
        stopDetectionDelay: 0,
        activityRecognitionInterval: 0,
        minimumActivityRecognitionConfidence: 0,
        disableStopDetection: false,
        maxDaysToPersist: 1,
        maxRecordsToPersist: 1,
        logLevel: bg.Config.LOG_LEVEL_OFF,
        logMaxDays: 1,
        extras: <String, dynamic>{"alarmMode": "IDLE"},
      ),
    );
    setState(() => _readyResult = "enabled=${state.enabled}");
    _log(
      "InitBG",
      "ready.returned {enabled:${state.enabled}, isMoving:${state.isMoving}, trackingMode:${state.trackingMode}}",
    );

    setState(() => _phase = "starting");
    final started = await bg.BackgroundGeolocation.start();
    _startReturnedAt = DateTime.now();
    setState(() {
      _startResult = "enabled=${started.enabled}";
      _phase = "running";
    });
    _log("InitBG", "start.returned {enabled:${started.enabled}}");
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final lastEvent = _lastMainIsolateEventAt;
    final startedAt = _startReturnedAt;

    Duration silentFor = Duration.zero;
    if (startedAt != null) {
      silentFor = now.difference(lastEvent ?? startedAt);
    }
    final wedge = startedAt != null && silentFor > _wedgeThreshold;

    return Scaffold(
      appBar: AppBar(title: const Text("BG Wedge Repro")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Phase: $_phase"),
            const SizedBox(height: 8),
            Text("bg.ready: $_readyResult"),
            Text("bg.start: $_startResult"),
            const SizedBox(height: 16),
            const Text(
              "Main-isolate event counts:",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            for (final entry in _counts.entries) Text("  ${entry.key}: ${entry.value}"),
            const SizedBox(height: 16),
            Text("Last main-isolate event: ${lastEvent?.toIso8601String() ?? "—"}"),
            Text("Silent for: ${silentFor.inSeconds}s"),
            const SizedBox(height: 16),
            if (wedge)
              Container(
                padding: const EdgeInsets.all(12),
                color: Colors.red,
                child: Text(
                  "WEDGE DETECTED — no main-isolate events for ${silentFor.inSeconds}s.\n"
                  "Check `adb logcat | grep Headless` to confirm the native source is still firing.",
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              )
            else
              const Text("(waiting for events…)"),
          ],
        ),
      ),
    );
  }
}