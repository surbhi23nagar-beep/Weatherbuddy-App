import 'package:rive/rive.dart';

/// WeatherType enum values as authored in the Rive file (exact strings).
abstract final class WeatherType {
  static const clearSkies = 'Clear Skies';
  static const rainy = 'Rainy';
  static const snowy = 'Snowy';
  static const heatwave = 'Heatwave';

  static const all = <String>[clearSkies, rainy, snowy, heatwave];
}

/// Rive property *paths* inside weatherbuddy.riv.
///
/// The design brief uses friendlier names (Location, ForecastDays, …).
/// This file's Data Binding panel uses the paths below — runtime must match.
abstract final class RiveProps {
  // MainViewModel
  static const location = 'location'; // brief: Location
  static const forecastDays = 'forecastdayz'; // brief: ForecastDays
  static const selectedForecast = 'selectedday'; // brief: SelectedForecast

  // forecastday:viewmodel (brief: ForecastDay)
  static const currentWeather = 'CurrentWeather';
  static const currentDegree = 'currentdegreenumber'; // brief: CurrentDegree
  static const fromDegree = 'FromDegree';
  static const toDegree = 'Todegree'; // brief: ToDegree
  static const day = 'Day';

  static const mainViewModel = 'MainViewModel';
  static const forecastDayViewModel = 'forecastday:viewmodel';
  static const mainInstance = 'Instance';
  static const dayInstances = <String>['day1', 'day2', 'day3', 'day4'];
}

/// Typed accessors for one ForecastDay view-model instance.
class ForecastDay {
  ForecastDay(this._vmi);

  final ViewModelInstance _vmi;

  ViewModelInstance get instance => _vmi;

  /// Brief: CurrentWeather — enum WeatherType.
  String get currentWeather =>
      _vmi.enumerator(RiveProps.currentWeather)?.value ?? '';

  set currentWeather(String value) {
    _vmi.enumerator(RiveProps.currentWeather)?.value = value;
  }

  /// Brief: CurrentDegree.
  double get currentDegree =>
      _vmi.number(RiveProps.currentDegree)?.value ?? 0;

  set currentDegree(double value) {
    _vmi.number(RiveProps.currentDegree)?.value = value;
  }

  /// Brief: FromDegree (daily low).
  double get fromDegree => _vmi.number(RiveProps.fromDegree)?.value ?? 0;

  set fromDegree(double value) {
    _vmi.number(RiveProps.fromDegree)?.value = value;
  }

  /// Brief: ToDegree (daily high).
  double get toDegree => _vmi.number(RiveProps.toDegree)?.value ?? 0;

  set toDegree(double value) {
    _vmi.number(RiveProps.toDegree)?.value = value;
  }

  /// Brief: Day — label like "Today", "Sat".
  String get day => _vmi.string(RiveProps.day)?.value ?? '';

  set day(String value) {
    _vmi.string(RiveProps.day)?.value = value;
  }
}

/// Typed accessors for MainViewModel (bound to the screen).
class MainViewModel {
  MainViewModel(this._file, this._vmi);

  final File _file;
  final ViewModelInstance _vmi;

  ViewModelInstance get instance => _vmi;

  /// Brief: Location — city name.
  String get location => _vmi.string(RiveProps.location)?.value ?? '';

  set location(String value) {
    _vmi.string(RiveProps.location)?.value = value;
  }

  /// Brief: SelectedForecast — hero day.
  ForecastDay get selectedForecast {
    final nested = _vmi.viewModel(RiveProps.selectedForecast);
    if (nested == null) {
      throw StateError(
        'SelectedForecast (path "${RiveProps.selectedForecast}") missing on MainViewModel',
      );
    }
    return ForecastDay(nested);
  }

  set selectedForecast(ForecastDay day) {
    // Nested view-model properties are reassigned by replacing list/selection
    // usage; prefer mutating [selectedForecast] fields in place.
    final target = _vmi.viewModel(RiveProps.selectedForecast);
    if (target == null) return;
    target.enumerator(RiveProps.currentWeather)?.value = day.currentWeather;
    target.number(RiveProps.currentDegree)?.value = day.currentDegree;
    target.number(RiveProps.fromDegree)?.value = day.fromDegree;
    target.number(RiveProps.toDegree)?.value = day.toDegree;
    target.string(RiveProps.day)?.value = day.day;
  }

  /// Brief: ForecastDays — the 4-day row list.
  ViewModelInstanceList get forecastDaysList {
    final list = _vmi.list(RiveProps.forecastDays);
    if (list == null) {
      throw StateError(
        'ForecastDays (path "${RiveProps.forecastDays}") missing on MainViewModel',
      );
    }
    return list;
  }

  /// ForecastDays as typed [ForecastDay] rows (index 0 = first day).
  List<ForecastDay> get forecastDays {
    final list = forecastDaysList;
    return [
      for (var i = 0; i < list.length; i++) ForecastDay(list.instanceAt(i)),
    ];
  }

  /// Ensures the ForecastDays list has all 4 exported day instances.
  void ensureFourForecastDays() {
    final list = forecastDaysList;
    if (list.length == 4) return;

    final dayVm = _file.viewModelByName(RiveProps.forecastDayViewModel);
    if (dayVm == null) {
      throw StateError(
        'View model "${RiveProps.forecastDayViewModel}" not found in .riv',
      );
    }

    while (list.length > 0) {
      list.removeAt(list.length - 1);
    }

    for (final name in RiveProps.dayInstances) {
      final inst = dayVm.createInstanceByName(name);
      if (inst == null) {
        throw StateError('Forecast day instance "$name" not found in .riv');
      }
      list.add(inst);
    }
  }

  /// Bind MainViewModel's default exported instance to a controller.
  static MainViewModel bindTo(RiveWidgetController controller) {
    final file = controller.file;
    final vm = file.viewModelByName(RiveProps.mainViewModel);
    if (vm == null) {
      throw StateError(
        'View model "${RiveProps.mainViewModel}" not found in .riv',
      );
    }

    final vmi = vm.createInstanceByName(RiveProps.mainInstance) ??
        vm.createDefaultInstance();
    if (vmi == null) {
      throw StateError(
        'Could not create MainViewModel instance "${RiveProps.mainInstance}"',
      );
    }

    controller.dataBind(DataBind.byInstance(vmi));
    final main = MainViewModel(file, vmi);
    main.ensureFourForecastDays();
    return main;
  }
}
