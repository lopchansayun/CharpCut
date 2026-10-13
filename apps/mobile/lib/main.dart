import 'dart:async';

import 'package:flutter/material.dart';

import 'engine/editor_engine.dart';
import 'engine/rust_engine.dart';
import 'engine/project_session.dart';
import 'home_screen.dart';
import 'src/rust/frb_generated.dart';
import 'theme.dart';

export 'editor_screen.dart' show EditorHome;
export 'engine/editor_engine.dart' show EditorEngine, EngineScope;
export 'engine/editor_state.dart' show EditorClip, EditorState;
export 'home_screen.dart' show HomeScreen;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    // Loads the Rust library. Without it there is no editing engine.
    await RustLib.init();
  } catch (error) {
    runApp(StartupFailure(error: error));
    return;
  }
  runApp(CharpCutApp(engine: ProjectSession(const RustEditorEngine(), AndroidProjectStore())));
}

class CharpCutApp extends StatelessWidget {
  const CharpCutApp({super.key, required this.engine});

  final EditorEngine engine;

  @override
  Widget build(BuildContext context) => EngineScope(
    engine: engine,
    child: MaterialApp(
      title: 'CharpCut',
      debugShowCheckedModeBanner: false,
      theme: buildDarkTheme(),
      home: const StartupScreen(),
    ),
  );
}

/// Shown instead of the app when the native editing engine could not be loaded.
class StartupFailure extends StatelessWidget {
  const StartupFailure({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildDarkTheme(),
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 40),
              const SizedBox(height: 16),
              const Text('CharpCut could not start', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              const Text(
                'The native editing engine is missing. Build it with\nscripts\\build-android-lib.ps1 (Windows) and run the app again.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              Text('$error', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Minimal centered launch screen. The short delay allows the brand to appear
/// before routing to the home page, similar to a mobile editor splash screen.
class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});
  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1100), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const HomeScreen()));
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Text('CharpCut', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 1.8)),
    ),
  );
}
