import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:rive/rive.dart' as rive;
import 'package:weather_buddy/weather_binding.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await rive.RiveNative.init();
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

class _EffectLayer {
  const _EffectLayer({
    required this.artboard,
    required this.weathers,
    required this.loopAnimations,
  });

  final String artboard;
  final Set<String> weathers;
  final List<String> loopAnimations;
}

class WeatherBuddyScreen extends StatefulWidget {
  const WeatherBuddyScreen({super.key});

  @override
  State<WeatherBuddyScreen> createState() => _WeatherBuddyScreenState();
}

class _WeatherBuddyScreenState extends State<WeatherBuddyScreen>
    with SingleTickerProviderStateMixin {
  rive.File? _file;
  MainViewModel? _main;
  final _uiControllers = <rive.RiveWidgetController>[];
  final _effectControllers = <String, rive.RiveWidgetController>{};
  final _effectLoops = <String, List<rive.Animation>>{};
  Object? _error;
  var _loading = true;
  String _activeWeather = WeatherType.rainy;

  Ticker? _fxTicker;
  Duration _lastTick = Duration.zero;

  static const _uiLayers = <({String artboard, Alignment align})>[
    (artboard: 'Weather Bg', align: Alignment.center),
    (artboard: 'forecast detail', align: Alignment.topCenter),
    (artboard: 'Avocado Master', align: Alignment.center),
    (artboard: 'forecast container', align: Alignment.bottomCenter),
  ];

  static const _effects = <_EffectLayer>[
    _EffectLayer(
      artboard: 'WEather sun',
      weathers: {WeatherType.clearSkies},
      loopAnimations: ['SHOW', 'glow'],
    ),
    _EffectLayer(
      artboard: 'weather red sun',
      weathers: {WeatherType.heatwave},
      loopAnimations: ['SHOW', 'ripple idle'],
    ),
    _EffectLayer(
      artboard: 'WEATHER RAIN',
      weathers: {WeatherType.rainy},
      loopAnimations: ['SHOW', 'rain'],
    ),
    _EffectLayer(
      artboard: 'weather snow MEDIUM',
      weathers: {WeatherType.snowy},
      loopAnimations: ['Start', 'SHOW', 'Snow'],
    ),
    _EffectLayer(
      artboard: 'leaves',
      weathers: {WeatherType.clearSkies},
      loopAnimations: ['SHOW', 'Start', 'leaves'],
    ),
    _EffectLayer(
      artboard: 'Beach ball',
      weathers: {WeatherType.clearSkies, WeatherType.heatwave},
      loopAnimations: ['SHOW', 'Start'],
    ),
    _EffectLayer(
      artboard: 'clouds componenet',
      weathers: {
        WeatherType.clearSkies,
        WeatherType.rainy,
        WeatherType.snowy,
      },
      loopAnimations: [
        'SHOW',
        'clouds idle',
        'Big clouds idle',
        'small clouds idle 2',
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final file = await rive.File.asset(
        'assets/weatherbuddy.riv',
        riveFactory: rive.Factory.rive,
      );
      if (file == null) {
        throw StateError('Could not decode weatherbuddy.riv');
      }

      final vm = file.viewModelByName(RiveProps.mainViewModel);
      if (vm == null) {
        throw StateError('MainViewModel not found in .riv');
      }
      final vmi = vm.createInstanceByName(RiveProps.mainInstance) ??
          vm.createDefaultInstance();
      if (vmi == null) {
        throw StateError('MainViewModel Instance not found');
      }

      final uiControllers = <rive.RiveWidgetController>[];
      for (final layer in _uiLayers) {
        final controller = rive.RiveWidgetController(
          file,
          artboardSelector: rive.ArtboardSelector.byName(layer.artboard),
          stateMachineSelector:
              rive.StateMachineSelector.byName('Main State Machine'),
        );
        controller.dataBind(rive.DataBind.byInstance(vmi));
        uiControllers.add(controller);
      }

      final effectControllers = <String, rive.RiveWidgetController>{};
      final effectLoops = <String, List<rive.Animation>>{};
      for (final effect in _effects) {
        final controller = rive.RiveWidgetController(
          file,
          artboardSelector: rive.ArtboardSelector.byName(effect.artboard),
          stateMachineSelector:
              rive.StateMachineSelector.byName('State Machine 1'),
        );
        effectControllers[effect.artboard] = controller;
        effectLoops[effect.artboard] = [
          for (final name in effect.loopAnimations)
            if (controller.artboard.animationNamed(name) case final anim?) anim,
        ];
      }

      final main = MainViewModel(file, vmi);
      main.ensureFourForecastDays();
      main.forecastDays[2].currentWeather = WeatherType.heatwave;

      // Keep SelectedForecast on the exported default (Rainy) so rain FX +
      // umbrella buddy match. Switch FX automatically when this enum changes:
      // Clear Skies → sun / leaves / ball / clouds
      // Heatwave → red sun / ball
      // Snowy → snowflakes
      // Rainy → rain / clouds

      final weather = main.selectedForecast.currentWeather;
      _syncWeatherTypeInputs(uiControllers, weather);
      main.selectedForecast.instance
          .enumerator(RiveProps.currentWeather)
          ?.addListener((_) {
        if (!mounted) return;
        final next = main.selectedForecast.currentWeather;
        _syncWeatherTypeInputs(uiControllers, next);
        setState(() => _activeWeather = next);
      });

      if (!mounted) {
        for (final c in uiControllers) {
          c.dispose();
        }
        for (final c in effectControllers.values) {
          c.dispose();
        }
        vmi.dispose();
        file.dispose();
        return;
      }

      setState(() {
        _file = file;
        _main = main;
        _uiControllers
          ..clear()
          ..addAll(uiControllers);
        _effectControllers
          ..clear()
          ..addAll(effectControllers);
        _effectLoops
          ..clear()
          ..addAll(effectLoops);
        _activeWeather = weather;
        _loading = false;
        _error = null;
      });

      _fxTicker?.dispose();
      _lastTick = Duration.zero;
      _fxTicker = createTicker(_onFxTick)..start();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  void _onFxTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt <= 0 || dt > 0.1) return;

    var needsPaint = false;
    for (final effect in _effects) {
      if (!effect.weathers.contains(_activeWeather)) continue;
      final anims = _effectLoops[effect.artboard];
      if (anims == null || anims.isEmpty) continue;
      for (final anim in anims) {
        if (anim.duration > 0 && anim.time >= anim.duration) {
          anim.time = 0;
        }
        anim.advanceAndApply(dt);
        needsPaint = true;
      }
    }
    if (needsPaint) {
      for (final effect in _effects) {
        if (!effect.weathers.contains(_activeWeather)) continue;
        _effectControllers[effect.artboard]?.active = true;
      }
    }
  }

  void _syncWeatherTypeInputs(
    List<rive.RiveWidgetController> controllers,
    String weather,
  ) {
    final index = switch (weather) {
      WeatherType.clearSkies => 0.0,
      WeatherType.rainy => 1.0,
      WeatherType.snowy => 2.0,
      WeatherType.heatwave => 3.0,
      _ => 1.0,
    };
    for (final controller in controllers) {
      // ignore: deprecated_member_use
      controller.stateMachine.number('weather type')?.value = index;
    }
  }

  bool _isPrecipitation(String artboard) =>
      artboard == 'WEATHER RAIN' || artboard == 'weather snow MEDIUM';

  @override
  void dispose() {
    _fxTicker?.dispose();
    for (final c in _uiControllers) {
      c.dispose();
    }
    for (final c in _effectControllers.values) {
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

    if (_error != null || _uiControllers.length != _uiLayers.length) {
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
                rive.RiveWidget(
                  controller: _uiControllers[0],
                  fit: rive.Fit.contain,
                  alignment: _uiLayers[0].align,
                ),
                // Atmosphere behind buddy (sun, heat sun, clouds, leaves, ball)
                for (final effect in _effects)
                  if (!_isPrecipitation(effect.artboard) &&
                      _effectControllers.containsKey(effect.artboard))
                    IgnorePointer(
                      child: Visibility(
                        visible: effect.weathers.contains(_activeWeather),
                        maintainState: true,
                        maintainAnimation: true,
                        child: rive.RiveWidget(
                          controller: _effectControllers[effect.artboard]!,
                          fit: rive.Fit.contain,
                          alignment: Alignment.center,
                        ),
                      ),
                    ),
                rive.RiveWidget(
                  controller: _uiControllers[1],
                  fit: rive.Fit.contain,
                  alignment: _uiLayers[1].align,
                ),
                rive.RiveWidget(
                  controller: _uiControllers[2],
                  fit: rive.Fit.contain,
                  alignment: _uiLayers[2].align,
                ),
                // Rain / snow in front of buddy
                for (final effect in _effects)
                  if (_isPrecipitation(effect.artboard) &&
                      _effectControllers.containsKey(effect.artboard))
                    IgnorePointer(
                      child: Visibility(
                        visible: effect.weathers.contains(_activeWeather),
                        maintainState: true,
                        maintainAnimation: true,
                        child: rive.RiveWidget(
                          controller: _effectControllers[effect.artboard]!,
                          fit: rive.Fit.contain,
                          alignment: Alignment.center,
                        ),
                      ),
                    ),
                rive.RiveWidget(
                  controller: _uiControllers[3],
                  fit: rive.Fit.contain,
                  alignment: _uiLayers[3].align,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
