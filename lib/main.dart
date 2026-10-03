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

enum _OutfitPhase { idle, outro, intro }

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
  rive.Animation? _avoOutro;

  /// Avocado exit→enter: Outro (current goes down) then Set (next comes up).
  var _outfitPhase = _OutfitPhase.idle;
  String _outfitWeather = WeatherType.rainy;
  String? _pendingOutfitWeather;

  /// Beach ball from weatherbuddy.riv (375×69 strip).
  /// Start = rolls left→right; Hide = exits. Decoded with Factory.flutter so
  /// it paints via Flutter canvas (native textures fight the other layers).
  /// Separate from heatwave red-sun ripple idle at the top.
  /// Positioned at avocado height, clear of the sun ripple zone.
  rive.File? _ballFile;
  rive.Artboard? _ballArtboard;
  rive.SingleAnimationPainter? _ballPainter;
  String? _ballAnimName;
  var _ballVisible = false;
  var _ballExiting = false;
  static const _ballAspect = 375.0 / 69.0;
  /// Vertical align for the strip (0 = center). Lower = avocado body/feet,
  /// well below the heatwave red-sun ripple rings.
  static const _ballAlignY = 0.48;

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

  void _playBall(String animationName) {
    final artboard = _ballArtboard;
    if (artboard == null) {
      debugPrint('Beach ball: artboard missing');
      return;
    }
    final hasAnim = artboard.animationNamed(animationName) != null;
    debugPrint(
      'Beach ball: play $animationName '
      'size=${artboard.width}x${artboard.height} hasAnim=$hasAnim '
      'factory=${artboard.riveFactory == rive.Factory.flutter ? "flutter" : "rive"}',
    );
    _ballPainter?.dispose();
    final painter = rive.SingleAnimationPainter(
      animationName,
      fit: rive.Fit.fill,
      alignment: Alignment.center,
    );
    painter.artboardChanged(artboard);
    _ballPainter = painter;
    _ballAnimName = animationName;
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

      // Beach ball: separate Factory.flutter decode so canvas paint isn't
      // blanked by the many Factory.rive textures used for the rest of the UI.
      final ballFile = await rive.File.asset(
        'assets/weatherbuddy.riv',
        riveFactory: rive.Factory.flutter,
      );
      final ballArtboard = ballFile?.artboard('Beach ball');

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
      final avoOutro = avoController.artboard.animationNamed('Outro');

      final weather = main.selectedForecast.currentWeather;
      _syncWeatherTypeInputs(uiControllers, weather);
      main.selectedForecast.instance
          .enumerator(RiveProps.currentWeather)
          ?.addListener((_) {
        if (!mounted) return;
        final next = main.selectedForecast.currentWeather;
        _onWeatherChanged(next);
        _beginOutfitTransition(next);
        setState(() => _activeWeather = next);
      });

      if (!mounted) {
        for (final c in uiControllers) {
          c.dispose();
        }
        for (final c in effectControllers.values) {
          c.dispose();
        }
        ballArtboard?.dispose();
        ballFile?.dispose();
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
        _avoOutro = avoOutro;
        _ballFile = ballFile;
        _ballArtboard = ballArtboard;
        _activeWeather = weather;
        _outfitWeather = weather;
        _outfitPhase = _OutfitPhase.idle;
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

  void _beginOutfitTransition(String next) {
    if (next.isEmpty) return;
    if (next == _outfitWeather &&
        _pendingOutfitWeather == null &&
        _outfitPhase == _OutfitPhase.idle) {
      return;
    }

    _pendingOutfitWeather = next;

    // Already exiting — finish Outro, then intro the latest pending weather.
    if (_outfitPhase == _OutfitPhase.outro) return;

    // Mid-intro of another outfit: treat that outfit as current and outro it.
    if (_outfitPhase == _OutfitPhase.intro) {
      final current = _avoAnims[_outfitWeather];
      if (current != null) {
        current.time = current.duration > 0 ? current.duration : 0;
        current.apply();
      }
    }

    _startOutfitOutro();
  }

  void _startOutfitOutro() {
    // Keep weather-type on the CURRENT outfit so Outro sends THAT avocado down.
    _syncWeatherTypeInputs(_uiControllers, _outfitWeather);
    final current = _avoAnims[_outfitWeather];
    if (current != null) {
      current.time = current.duration > 0 ? current.duration : 0;
      current.apply();
    }
    final bg = _bgAnims[_outfitWeather];
    if (bg != null) {
      bg.time = bg.duration > 0 ? bg.duration : 0;
      bg.apply();
    }

    final outro = _avoOutro;
    if (outro == null || outro.duration <= 0) {
      _startOutfitIntro(_pendingOutfitWeather ?? _activeWeather);
      return;
    }
    outro.time = 0;
    _outfitPhase = _OutfitPhase.outro;
  }

  void _startOutfitIntro(String weather) {
    _pendingOutfitWeather = null;
    _outfitWeather = weather;
    _outfitPhase = _OutfitPhase.intro;
    // Swap weather-type only now so the new avocado is the one that rises.
    _syncWeatherTypeInputs(_uiControllers, weather);

    final set = _avoAnims[weather];
    if (set != null) {
      set.time = 0;
    } else {
      _outfitPhase = _OutfitPhase.idle;
    }
    final bg = _bgAnims[weather];
    if (bg != null) {
      bg.time = 0;
    }

    // File Beach ball: Start rolls left → right, then SHOW parks it at avocado
    // height — clear of the red-sun ripple at the top.
    if (weather == WeatherType.heatwave) {
      _ballExiting = false;
      _ballVisible = true;
      _playBall('Start');
      if (mounted) setState(() {});
      Future<void>.delayed(const Duration(milliseconds: 1100), () {
        if (!mounted || !_ballVisible || _ballExiting) return;
        if (_activeWeather != WeatherType.heatwave) return;
        setState(() => _playBall('SHOW'));
      });
    }
  }

  void _onWeatherChanged(String weather) {
    final wasHeat = _activeWeather == WeatherType.heatwave;
    final isHeat = weather == WeatherType.heatwave;

    _resetEffectIntrosFor(weather);

    // Enter is handled in _startOutfitIntro so Start rolls with the avocado.
    if (!isHeat && (wasHeat || _ballVisible || _ballExiting)) {
      _ballExiting = true;
      _ballVisible = true;
      _playBall('Hide');
      if (mounted) setState(() {});
      // Hide duration in the file is ~1s.
      Future<void>.delayed(const Duration(milliseconds: 1100), () {
        if (!mounted || !_ballExiting) return;
        setState(() {
          _ballExiting = false;
          _ballVisible = false;
          _ballPainter?.dispose();
          _ballPainter = null;
          _ballAnimName = null;
        });
      });
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
      _beginOutfitTransition(selected);
      _activeWeather = selected;
      if (mounted) setState(() {});
    }

    // Background follows the outfit phase (old held, then new rises).
    final bgWeather = _outfitPhase == _OutfitPhase.outro
        ? _outfitWeather
        : (_outfitPhase == _OutfitPhase.intro
            ? _outfitWeather
            : _activeWeather);
    final bgAnim = _bgAnims[bgWeather];
    if (bgAnim != null) {
      if (_outfitPhase == _OutfitPhase.outro) {
        bgAnim.time = bgAnim.duration > 0 ? bgAnim.duration : 0;
        bgAnim.apply();
      } else if (bgAnim.duration > 0 && bgAnim.time >= bgAnim.duration) {
        bgAnim.time = bgAnim.duration;
        bgAnim.apply();
      } else {
        bgAnim.advanceAndApply(dt);
      }
      _uiControllers[0].active = true;
    }

    // Avocado: Outro (current goes down) → Set (next comes up).
    // Pause the SM so it can't fight our Outro/Set timelines.
    final avoController = _uiControllers[2];
    avoController.active = false;
    switch (_outfitPhase) {
      case _OutfitPhase.outro:
        final current = _avoAnims[_outfitWeather];
        if (current != null) {
          current.time = current.duration > 0 ? current.duration : 0;
          current.apply();
        }
        final outro = _avoOutro;
        if (outro == null) {
          _startOutfitIntro(_pendingOutfitWeather ?? _activeWeather);
        } else {
          final playing = outro.advanceAndApply(dt);
          if (!playing ||
              (outro.duration > 0 && outro.time >= outro.duration)) {
            outro.time = outro.duration;
            outro.apply();
            _startOutfitIntro(_pendingOutfitWeather ?? _activeWeather);
          }
        }
      case _OutfitPhase.intro:
        final intro = _avoAnims[_outfitWeather];
        if (intro == null) {
          _outfitPhase = _OutfitPhase.idle;
        } else if (intro.duration > 0 && intro.time >= intro.duration) {
          intro.time = intro.duration;
          intro.apply();
          _outfitPhase = _OutfitPhase.idle;
        } else {
          intro.advanceAndApply(dt);
        }
      case _OutfitPhase.idle:
        final idle = _avoAnims[_outfitWeather];
        if (idle != null) {
          idle.time = idle.duration > 0 ? idle.duration : 0;
          idle.apply();
        }
    }
    avoController.scheduleRepaint();

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
    _outfitWeather = weather;
    _outfitPhase = _OutfitPhase.idle;
    _pendingOutfitWeather = null;
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
    _syncWeatherTypeInputs(_uiControllers, weather);
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
    for (final c in _uiControllers) {
      c.dispose();
    }
    for (final c in _effectControllers.values) {
      c.dispose();
    }
    _ballPainter?.dispose();
    _ballArtboard?.dispose();
    _ballFile?.dispose();
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
                // File Beach ball (375×69): Start rolls left → right at avocado
                // height — below the heatwave red-sun ripple (top of frame).
                if (_ballArtboard != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Opacity(
                        opacity: (_ballVisible || _ballExiting) &&
                                _ballPainter != null
                            ? 1
                            : 0,
                        child: Align(
                          alignment: const Alignment(0, _ballAlignY),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final width = constraints.maxWidth.isFinite
                                  ? constraints.maxWidth
                                  : MediaQuery.sizeOf(context).width;
                              final height = width / _ballAspect;
                              return SizedBox(
                                width: width,
                                height: height,
                                child: _ballPainter == null
                                    ? const SizedBox.shrink()
                                    : rive.RiveArtboardWidget(
                                        key: ValueKey(
                                          'beach-ball-$_ballAnimName',
                                        ),
                                        artboard: _ballArtboard!,
                                        painter: _ballPainter!,
                                      ),
                              );
                            },
                          ),
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
