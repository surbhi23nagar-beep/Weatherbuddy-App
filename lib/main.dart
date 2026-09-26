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
  final _bgAnims = <String, rive.Animation>{};
  final _avoAnims = <String, rive.Animation>{};

  /// Mini avocado artboards shown in the 4-day row (icons alone aren't enough).
  final _dayAvoControllers = <String, rive.RiveWidgetController>{};
  final _dayWeathers = <String>[
    WeatherType.clearSkies,
    WeatherType.heatwave,
    WeatherType.snowy,
    WeatherType.rainy,
  ];

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

  static const _dayAvoArtboards = <String, String>{
    WeatherType.clearSkies: 'Avo Clear Sky',
    WeatherType.heatwave: 'Avo Heatwave',
    WeatherType.snowy: 'Avosnowy',
    WeatherType.rainy: 'Avo Rainy',
  };

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

  rive.RiveWidgetController _controllerFor(
    rive.File file,
    String artboard, {
    String? stateMachine,
  }) {
    return rive.RiveWidgetController(
      file,
      artboardSelector: rive.ArtboardSelector.byName(artboard),
      stateMachineSelector: stateMachine == null
          ? const rive.StateMachineDefault()
          : rive.StateMachineSelector.byName(stateMachine),
    );
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
        final controller = _controllerFor(
          file,
          layer.artboard,
          stateMachine: 'Main State Machine',
        );
        controller.dataBind(rive.DataBind.byInstance(vmi));
        uiControllers.add(controller);
      }

      final effectControllers = <String, rive.RiveWidgetController>{};
      final effectLoops = <String, List<rive.Animation>>{};
      for (final effect in _effects) {
        final controller = _controllerFor(
          file,
          effect.artboard,
          stateMachine: 'State Machine 1',
        );
        effectControllers[effect.artboard] = controller;
        effectLoops[effect.artboard] = [
          for (final name in effect.loopAnimations)
            if (controller.artboard.animationNamed(name) case final anim?) anim,
        ];
      }

      // One controller per weather avocado used in the forecast row.
      final dayAvoControllers = <String, rive.RiveWidgetController>{};
      for (final entry in _dayAvoArtboards.entries) {
        dayAvoControllers[entry.key] = _controllerFor(file, entry.value);
      }

      final main = MainViewModel(file, vmi);
      main.ensureFourForecastDays();

      // Today Clear · Tue Heatwave · Wed Snow avocado · Thu Rainy avocado
      main.forecastDays[0].currentWeather = WeatherType.clearSkies;
      main.forecastDays[1].currentWeather = WeatherType.heatwave;
      main.forecastDays[2].currentWeather = WeatherType.snowy;
      main.forecastDays[3].currentWeather = WeatherType.rainy;
      _dayWeathers
        ..clear()
        ..addAll([
          WeatherType.clearSkies,
          WeatherType.heatwave,
          WeatherType.snowy,
          WeatherType.rainy,
        ]);

      // Hero = rainy avocado + rainy background + rain FX
      main.selectedForecast.currentWeather = WeatherType.rainy;

      final bgController = uiControllers[0];
      final avoController = uiControllers[2];
      final bgAnimsSafe = <String, rive.Animation>{
        for (final e in {
          WeatherType.clearSkies: 'Background (Set clear sky)',
          WeatherType.heatwave: 'Background (Heatwave)',
          WeatherType.snowy: 'Background (Snowy)  ',
          WeatherType.rainy: 'Background (Rainy) ',
        }.entries)
          if (bgController.artboard.animationNamed(e.value) case final a?)
            e.key: a,
      };
      final avoAnimsSafe = <String, rive.Animation>{
        for (final e in {
          WeatherType.clearSkies: '(Set clear sky)',
          WeatherType.heatwave: 'Set (Heatwave)',
          WeatherType.snowy: 'Set (Snowy)  ',
          WeatherType.rainy: 'Set (Rainy) ',
        }.entries)
          if (avoController.artboard.animationNamed(e.value) case final a?)
            e.key: a,
      };

      final weather = main.selectedForecast.currentWeather;
      _syncWeatherTypeInputs(uiControllers, weather);
      main.selectedForecast.instance
          .enumerator(RiveProps.currentWeather)
          ?.addListener((_) {
        if (!mounted) return;
        final next = main.selectedForecast.currentWeather;
        _syncWeatherTypeInputs(uiControllers, next);
        _snapOutfitTo(next);
        setState(() => _activeWeather = next);
      });

      if (!mounted) {
        for (final c in uiControllers) {
          c.dispose();
        }
        for (final c in effectControllers.values) {
          c.dispose();
        }
        for (final c in dayAvoControllers.values) {
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
        _bgAnims
          ..clear()
          ..addAll(bgAnimsSafe);
        _avoAnims
          ..clear()
          ..addAll(avoAnimsSafe);
        _dayAvoControllers
          ..clear()
          ..addAll(dayAvoControllers);
        _activeWeather = weather;
        _loading = false;
        _error = null;
      });

      _snapOutfitTo(weather);

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

    final bgAnim = _bgAnims[_activeWeather];
    if (bgAnim != null) {
      if (bgAnim.duration > 0 && bgAnim.time >= bgAnim.duration) {
        bgAnim.time = bgAnim.duration;
      } else {
        bgAnim.advanceAndApply(dt);
      }
      bgAnim.apply();
      _uiControllers[0].active = true;
    }

    final avoAnim = _avoAnims[_activeWeather];
    if (avoAnim != null) {
      if (avoAnim.duration > 0 && avoAnim.time >= avoAnim.duration) {
        avoAnim.time = avoAnim.duration;
      } else {
        avoAnim.advanceAndApply(dt);
      }
      avoAnim.apply();
      _uiControllers[2].active = true;
    }

    for (final effect in _effects) {
      if (!effect.weathers.contains(_activeWeather)) continue;
      final anims = _effectLoops[effect.artboard];
      if (anims == null || anims.isEmpty) continue;
      for (final anim in anims) {
        if (anim.duration > 0 && anim.time >= anim.duration) {
          anim.time = 0;
        }
        anim.advanceAndApply(dt);
      }
      _effectControllers[effect.artboard]?.active = true;
    }

    for (final c in _dayAvoControllers.values) {
      c.active = true;
    }
  }

  void _snapOutfitTo(String weather) {
    final bg = _bgAnims[weather];
    if (bg != null) {
      bg.time = bg.duration > 0 ? bg.duration : 0;
      bg.apply();
    }
    final avo = _avoAnims[weather];
    if (avo != null) {
      avo.time = avo.duration > 0 ? avo.duration : 0;
      avo.apply();
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
    for (final c in _dayAvoControllers.values) {
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final h = constraints.maxHeight;
                // Mini avocados sit in the forecast row slots.
                final slotW = w / 4;
                final avoSize = slotW * 0.55;
                final avoBottom = h * 0.07;

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // Fill weather background
                    rive.RiveWidget(
                      controller: _uiControllers[0],
                      fit: rive.Fit.cover,
                      alignment: _uiLayers[0].align,
                    ),
                    for (final effect in _effects)
                      if (!_isPrecipitation(effect.artboard) &&
                          _effectControllers.containsKey(effect.artboard))
                        IgnorePointer(
                          child: Visibility(
                            visible:
                                effect.weathers.contains(_activeWeather),
                            maintainState: true,
                            maintainAnimation: true,
                            child: rive.RiveWidget(
                              controller:
                                  _effectControllers[effect.artboard]!,
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
                    for (final effect in _effects)
                      if (_isPrecipitation(effect.artboard) &&
                          _effectControllers.containsKey(effect.artboard))
                        IgnorePointer(
                          child: Visibility(
                            visible:
                                effect.weathers.contains(_activeWeather),
                            maintainState: true,
                            maintainAnimation: true,
                            child: rive.RiveWidget(
                              controller:
                                  _effectControllers[effect.artboard]!,
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
                    // Day-row avocados: Wed = snow, Thu = rainy, etc.
                    for (var i = 0; i < _dayWeathers.length; i++)
                      if (_dayAvoControllers[_dayWeathers[i]] != null)
                        Positioned(
                          left: slotW * i + (slotW - avoSize) / 2,
                          bottom: avoBottom,
                          width: avoSize,
                          height: avoSize,
                          child: IgnorePointer(
                            child: rive.RiveWidget(
                              controller:
                                  _dayAvoControllers[_dayWeathers[i]]!,
                              fit: rive.Fit.contain,
                              alignment: Alignment.center,
                            ),
                          ),
                        ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
