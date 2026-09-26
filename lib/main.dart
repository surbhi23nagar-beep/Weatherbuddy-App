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
    this.introAnimations = const ['SHOW'],
    this.loopAnimations = const [],
  });

  final String artboard;
  final Set<String> weathers;

  /// Play once when the weather becomes active (e.g. SHOW).
  final List<String> introAnimations;

  /// Continuous loops (sun glow/rotation, rain, leaves, snow, clouds).
  final List<String> loopAnimations;
}

class WeatherBuddyScreen extends StatefulWidget {
  const WeatherBuddyScreen({super.key});

  @override
  State<WeatherBuddyScreen> createState() => _WeatherBuddyScreenState();
}

class _WeatherBuddyScreenState extends State<WeatherBuddyScreen>
    with TickerProviderStateMixin {
  rive.File? _file;
  MainViewModel? _main;
  final _uiControllers = <rive.RiveWidgetController>[];
  final _effectControllers = <String, rive.RiveWidgetController>{};
  final _effectIntros = <String, List<rive.Animation>>{};
  final _effectLoops = <String, List<rive.Animation>>{};
  final _effectIntroDone = <String>{};
  final _bgAnims = <String, rive.Animation>{};
  final _avoAnims = <String, rive.Animation>{};

  /// Beach ball enter/exit. The .riv Beach ball artboard stays empty when
  /// driven from runtime (SM has no inputs; Start/SHOW/Hide don't paint),
  /// so we animate a matching Flutter beach ball instead.
  var _ballVisible = false;
  var _ballExiting = false;
  late final AnimationController _ballMotion;
  late final Animation<Alignment> _ballAlign;

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
    // Yellow sun — SHOW once, then glow loops (sun rotation).
    _EffectLayer(
      artboard: 'WEather sun',
      weathers: {WeatherType.clearSkies},
      introAnimations: ['SHOW'],
      loopAnimations: ['glow'],
    ),
    _EffectLayer(
      artboard: 'weather red sun',
      weathers: {WeatherType.heatwave},
      introAnimations: ['SHOW'],
      loopAnimations: ['ripple idle'],
    ),
    _EffectLayer(
      artboard: 'WEATHER RAIN',
      weathers: {WeatherType.rainy},
      introAnimations: ['SHOW'],
      loopAnimations: ['rain'],
    ),
    _EffectLayer(
      artboard: 'weather snow MEDIUM',
      weathers: {WeatherType.snowy},
      introAnimations: ['Start', 'SHOW'],
      loopAnimations: ['Snow'],
    ),
    // Leaves fall on the rainy screen (drawn with precipitation).
    _EffectLayer(
      artboard: 'leaves',
      weathers: {WeatherType.rainy},
      introAnimations: ['SHOW'],
      loopAnimations: ['leaves'],
    ),
    _EffectLayer(
      artboard: 'clouds componenet',
      weathers: {
        WeatherType.clearSkies,
        WeatherType.rainy,
        WeatherType.snowy,
      },
      introAnimations: ['SHOW'],
      loopAnimations: [
        'clouds idle',
        'Big clouds idle',
        'small clouds idle 2',
      ],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _ballMotion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _ballAlign = AlignmentTween(
      begin: const Alignment(1.6, 0.35),
      end: const Alignment(0.55, 0.25),
    ).animate(CurvedAnimation(parent: _ballMotion, curve: Curves.easeOutBack));
    _bootstrap();
  }

  rive.RiveWidgetController _controllerFor(
    rive.File file,
    String artboard, {
    required String stateMachine,
  }) {
    return rive.RiveWidgetController(
      file,
      artboardSelector: rive.ArtboardSelector.byName(artboard),
      stateMachineSelector: rive.StateMachineSelector.byName(stateMachine),
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
      final effectIntros = <String, List<rive.Animation>>{};
      final effectLoops = <String, List<rive.Animation>>{};
      for (final effect in _effects) {
        final controller = _controllerFor(
          file,
          effect.artboard,
          stateMachine: 'State Machine 1',
        );
        effectControllers[effect.artboard] = controller;
        effectIntros[effect.artboard] = [
          for (final name in effect.introAnimations)
            if (controller.artboard.animationNamed(name) case final anim?) anim,
        ];
        effectLoops[effect.artboard] = [
          for (final name in effect.loopAnimations)
            if (controller.artboard.animationNamed(name) case final anim?) anim,
        ];
      }

      final main = MainViewModel(file, vmi);
      main.ensureFourForecastDays();

      // Forecast row: icons only (no avocados on the buttons).
      main.forecastDays[0].currentWeather = WeatherType.clearSkies;
      main.forecastDays[1].currentWeather = WeatherType.heatwave;
      main.forecastDays[2].currentWeather = WeatherType.snowy;
      main.forecastDays[3].currentWeather = WeatherType.rainy;

      // Hero starts Rainy → rain + falling leaves.
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
        _onWeatherChanged(next);
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
        _effectIntros
          ..clear()
          ..addAll(effectIntros);
        _effectLoops
          ..clear()
          ..addAll(effectLoops);
        _effectIntroDone.clear();
        _bgAnims
          ..clear()
          ..addAll(bgAnimsSafe);
        _avoAnims
          ..clear()
          ..addAll(avoAnimsSafe);
        _activeWeather = weather;
        _loading = false;
        _error = null;
      });

      _snapOutfitTo(weather);
      _resetEffectIntrosFor(weather);
      _onWeatherChanged(weather);

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

  void _resetEffectIntrosFor(String weather) {
    for (final effect in _effects) {
      final active = effect.weathers.contains(weather);
      if (!active) {
        _effectIntroDone.remove(effect.artboard);
        continue;
      }
      if (_effectIntroDone.contains(effect.artboard)) continue;
      for (final anim in _effectIntros[effect.artboard] ?? const []) {
        anim.time = 0;
      }
      for (final anim in _effectLoops[effect.artboard] ?? const []) {
        anim.time = 0;
      }
    }
  }

  void _onWeatherChanged(String weather) {
    final wasHeat = _activeWeather == WeatherType.heatwave;
    final isHeat = weather == WeatherType.heatwave;

    _resetEffectIntrosFor(weather);

    if (isHeat && !wasHeat) {
      _ballExiting = false;
      _ballVisible = true;
      _ballMotion.forward(from: 0);
      if (mounted) setState(() {});
    } else if (!isHeat && (wasHeat || _ballVisible)) {
      _ballExiting = true;
      _ballMotion.reverse().whenComplete(() {
        if (!mounted) return;
        setState(() {
          _ballExiting = false;
          _ballVisible = false;
        });
      });
      if (mounted) setState(() {});
    }
  }

  void _onFxTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt <= 0 || dt > 0.1) return;

    // Keep Flutter FX in sync when day selection rebinds selectedday.
    final selected = _main?.selectedForecast.currentWeather;
    if (selected != null &&
        selected.isNotEmpty &&
        selected != _activeWeather) {
      _onWeatherChanged(selected);
      _syncWeatherTypeInputs(_uiControllers, selected);
      _snapOutfitTo(selected);
      _activeWeather = selected;
      if (mounted) setState(() {});
    }

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
      final intros = _effectIntros[effect.artboard] ?? const <rive.Animation>[];
      final loops = _effectLoops[effect.artboard] ?? const <rive.Animation>[];
      if (intros.isEmpty && loops.isEmpty) continue;

      var introsComplete = _effectIntroDone.contains(effect.artboard);
      if (!introsComplete) {
        introsComplete = true;
        for (final anim in intros) {
          if (anim.duration > 0 && anim.time >= anim.duration) {
            anim.time = anim.duration;
            anim.apply();
          } else {
            anim.advanceAndApply(dt);
            introsComplete = false;
          }
        }
        if (introsComplete) {
          _effectIntroDone.add(effect.artboard);
        }
      }

      if (introsComplete || intros.isEmpty) {
        for (final anim in loops) {
          if (anim.duration > 0 && anim.time >= anim.duration) {
            anim.time = 0;
          }
          anim.advanceAndApply(dt);
        }
      }
      _effectControllers[effect.artboard]?.active = true;
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
      artboard == 'WEATHER RAIN' ||
      artboard == 'weather snow MEDIUM' ||
      artboard == 'leaves';

  bool _showEffect(String artboard) {
    final effect = _effects.cast<_EffectLayer?>().firstWhere(
          (e) => e?.artboard == artboard,
          orElse: () => null,
        );
    return effect?.weathers.contains(_activeWeather) ?? false;
  }

  @override
  void dispose() {
    _fxTicker?.dispose();
    _ballMotion.dispose();
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

    final atmosphere = [
      for (final effect in _effects)
        if (!_isPrecipitation(effect.artboard)) effect.artboard,
    ];
    final precipitation = [
      for (final effect in _effects)
        if (_isPrecipitation(effect.artboard)) effect.artboard,
    ];

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
                  fit: rive.Fit.cover,
                  alignment: _uiLayers[0].align,
                ),
                for (final name in atmosphere)
                  if (_effectControllers.containsKey(name))
                    IgnorePointer(
                      child: Visibility(
                        visible: _showEffect(name),
                        maintainState: true,
                        maintainAnimation: true,
                        child: rive.RiveWidget(
                          controller: _effectControllers[name]!,
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
                for (final name in precipitation)
                  if (_effectControllers.containsKey(name))
                    IgnorePointer(
                      child: Visibility(
                        visible: _showEffect(name),
                        maintainState: true,
                        maintainAnimation: true,
                        child: rive.RiveWidget(
                          controller: _effectControllers[name]!,
                          fit: rive.Fit.contain,
                          alignment: Alignment.center,
                        ),
                      ),
                    ),
                // Beach ball enters on Heatwave, exits on other screens.
                if (_ballVisible || _ballExiting)
                  IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _ballAlign,
                      builder: (context, child) {
                        return Align(
                          alignment: _ballAlign.value,
                          child: child,
                        );
                      },
                      child: FractionallySizedBox(
                        widthFactor: 0.2,
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: CustomPaint(painter: _BeachBallPainter()),
                        ),
                      ),
                    ),
                  ),
                // Forecast buttons — icons + temps only (no avocados).
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

class _BeachBallPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    final colors = <Color>[
      const Color(0xFFE85D4C),
      const Color(0xFFF5D76E),
      const Color(0xFF4AA3DF),
      const Color(0xFFF7F7F7),
    ];
    for (var i = 0; i < colors.length; i++) {
      final start = -1.2 + (i * 1.55);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        1.55,
        true,
        Paint()..color = colors[i],
      );
    }
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = radius * 0.06
        ..color = const Color(0x33000000),
    );
    canvas.drawCircle(
      center.translate(-radius * 0.25, -radius * 0.28),
      radius * 0.18,
      Paint()..color = const Color(0x55FFFFFF),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
