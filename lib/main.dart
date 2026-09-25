import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rive/rive.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await RiveNative.init();
  runApp(const WeatherBuddyApp());
}

class WeatherBuddyApp extends StatelessWidget {
  const WeatherBuddyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WeatherBuddyScreen(),
    );
  }
}

/// One full-screen Rive surface — no menus or chrome.
class WeatherBuddyScreen extends StatefulWidget {
  const WeatherBuddyScreen({super.key});

  @override
  State<WeatherBuddyScreen> createState() => _WeatherBuddyScreenState();
}

class _WeatherBuddyScreenState extends State<WeatherBuddyScreen> {
  late final FileLoader _fileLoader = FileLoader.fromAsset(
    'assets/weatherbuddy.riv',
    riveFactory: Factory.rive,
  );

  @override
  void dispose() {
    _fileLoader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.expand(
        child: RiveWidgetBuilder(
          fileLoader: _fileLoader,
          artboardSelector: ArtboardSelector.byName('MainScreen2'),
          stateMachineSelector:
              StateMachineSelector.byName('MainStateMachine'),
          builder: (context, state) => switch (state) {
            RiveLoading() => const ColoredBox(
                color: Colors.black,
                child: Center(
                  child: CircularProgressIndicator(color: Colors.white54),
                ),
              ),
            RiveFailed() => ColoredBox(
                color: Colors.black,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Couldn’t load Weather Buddy.\n${state.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 16,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
            RiveLoaded() => RiveWidget(
                controller: state.controller,
                fit: Fit.layout,
              ),
          },
        ),
      ),
    );
  }
}
