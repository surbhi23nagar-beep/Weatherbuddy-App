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

/// Full Weather Buddy screen composed from the artboards in weatherbuddy.riv.
///
/// This export does not include a single "Main Screen 2" artboard — the editor
/// preview is assembled from:
///   Weather Bg + forecast detail + Avocado Master + forecast container
/// All share one MainViewModel instance so list/day animations stay live.
class WeatherBuddyScreen extends StatefulWidget {
  const WeatherBuddyScreen({super.key});

  @override
  State<WeatherBuddyScreen> createState() => _WeatherBuddyScreenState();
}

class _WeatherBuddyScreenState extends State<WeatherBuddyScreen> {
  File? _file;
  MainViewModel? _main;
  final _controllers = <RiveWidgetController>[];
  Object? _error;
  var _loading = true;

  static const _layers = <({String artboard, Alignment align})>[
    (artboard: 'Weather Bg', align: Alignment.center),
    (artboard: 'forecast detail', align: Alignment.topCenter),
    (artboard: 'Avocado Master', align: Alignment.center),
    (artboard: 'forecast container', align: Alignment.bottomCenter),
  ];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final file = await File.asset(
        'assets/weatherbuddy.riv',
        riveFactory: Factory.rive,
      );
      if (file == null) {
        throw StateError('Could not decode weatherbuddy.riv');
      }

      // One MainViewModel instance shared across every layer.
      final vm = file.viewModelByName(RiveProps.mainViewModel);
      if (vm == null) {
        throw StateError('MainViewModel not found in .riv');
      }
      final vmi = vm.createInstanceByName(RiveProps.mainInstance) ??
          vm.createDefaultInstance();
      if (vmi == null) {
        throw StateError('MainViewModel Instance not found');
      }

      final controllers = <RiveWidgetController>[];
      for (final layer in _layers) {
        final controller = RiveWidgetController(
          file,
          artboardSelector: ArtboardSelector.byName(layer.artboard),
          stateMachineSelector:
              StateMachineSelector.byName('Main State Machine'),
        );
        controller.dataBind(DataBind.byInstance(vmi));
        controllers.add(controller);
      }

      final main = MainViewModel(file, vmi);
      main.ensureFourForecastDays();

      // Demo: 3rd forecast day → Heatwave; keep Day labels + other days intact
      // so each ForecastDay artboard keeps its authored animation.
      main.forecastDays[2].currentWeather = WeatherType.heatwave;

      if (!mounted) {
        for (final c in controllers) {
          c.dispose();
        }
        vmi.dispose();
        file.dispose();
        return;
      }

      setState(() {
        _file = file;
        _main = main;
        _controllers
          ..clear()
          ..addAll(controllers);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    _main?.instance.dispose();
    _file?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF9EC9E6),
        body: Center(
          child: CircularProgressIndicator(color: Colors.white70),
        ),
      );
    }

    if (_error != null || _controllers.length != _layers.length) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Couldn’t load Weather Buddy.\n$_error',
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

    return Scaffold(
      backgroundColor: const Color(0xFF9EC9E6),
      body: SafeArea(
        child: Center(
          child: AspectRatio(
            aspectRatio: 9 / 19.5,
            child: Stack(
              fit: StackFit.expand,
              children: [
                for (var i = 0; i < _layers.length; i++)
                  RiveWidget(
                    controller: _controllers[i],
                    fit: Fit.contain,
                    alignment: _layers[i].align,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
