import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rive/rive.dart';
import 'package:weather_buddy/weather_binding.dart';

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

  /// Bound MainViewModel — keep alive while the screen is showing.
  MainViewModel? _main;
  String? _bindError;

  @override
  void dispose() {
    _main?.instance.dispose();
    _fileLoader.dispose();
    super.dispose();
  }

  void _onRiveLoaded(RiveLoaded state) {
    try {
      // Splash has no View Model assigned in the editor dropdown, so we bind
      // MainViewModel's exported Instance explicitly.
      final main = MainViewModel.bindTo(state.controller);
      _main = main;

      // --- Demo / test data from code ---
      // ForecastDays already has 4 days (ensured in bindTo).
      // Third day (index 2) → Heatwave; leave its Day label alone.
      main.forecastDays[2].currentWeather = WeatherType.heatwave;

      // Mirror onto SelectedForecast (hero) so the change is visible on screen.
      // The bottom row needs MainViewModel assigned to Splash in the Rive editor
      // for list cells to refresh from ForecastDays.
      main.selectedForecast.currentWeather = WeatherType.heatwave;

      // Reveal the main UI after splash loading (no ViewModel trigger in this .riv).
      // ignore: deprecated_member_use
      state.controller.stateMachine.trigger('Loading completed')?.fire();

      setState(() => _bindError = null);
    } catch (e) {
      setState(() => _bindError = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.expand(
        child: RiveWidgetBuilder(
          fileLoader: _fileLoader,
          // Splash = main full-screen artboard in this .riv export.
          artboardSelector: ArtboardSelector.byName('Splash'),
          stateMachineSelector:
              StateMachineSelector.byName('Main State Machine'),
          onLoaded: _onRiveLoaded,
          builder: (context, state) => switch (state) {
            RiveLoading() => const ColoredBox(
                color: Colors.black,
                child: Center(
                  child: CircularProgressIndicator(color: Colors.white54),
                ),
              ),
            RiveFailed() => _ErrorPane('Couldn’t load Weather Buddy.\n${state.error}'),
            RiveLoaded() => _bindError != null
                ? _ErrorPane('Data binding failed.\n$_bindError')
                : RiveWidget(
                    controller: state.controller,
                    fit: Fit.layout,
                  ),
          },
        ),
      ),
    );
  }
}

class _ErrorPane extends StatelessWidget {
  const _ErrorPane(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
              height: 1.4,
            ),
          ),
        ),
      ),
    );
  }
}
