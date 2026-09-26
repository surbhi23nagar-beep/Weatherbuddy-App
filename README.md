# Weather Buddy

A one-screen Flutter app that plays your Rive file full-screen on **iPhone** and **Android**.

| Setting | Value |
| --- | --- |
| File | `assets/weatherbuddy.riv` |
| Artboard | `Splash` (main full-screen artboard in this export) |
| State machine | `Main State Machine` |
| Fit | `Fit.layout` (fills and adapts to any screen size) |
| View model | `MainViewModel` (bound from code) |

No menus, settings, or extra UI — just the animation (plus a brief loading / error state).

## Data binding (set values from code)

Helpers live in `lib/weather_binding.dart`. Example:

```dart
main.location = 'Bangalore';
main.forecastDays[2].currentWeather = WeatherType.heatwave; // 3rd day
main.selectedForecast.currentDegree = 72;
```

### Brief name → name inside this `.riv` file

Your Data Binding panel uses slightly different property paths than the brief. The Dart API uses the brief names; under the hood it writes to these Rive paths:

| Brief (Dart API) | Path in this `.riv` |
| --- | --- |
| `Location` | `location` |
| `ForecastDays` | `forecastdayz` |
| `SelectedForecast` | `selectedday` |
| `CurrentDegree` | `currentdegreenumber` |
| `ToDegree` | `Todegree` |
| `CurrentWeather` / `FromDegree` / `Day` | same |
| ForecastDay view model | `forecastday:viewmodel` |
| Enum value `Heatwave` | `Heatwave` |

**Editor tip:** Splash currently has no View Model assigned in the artboard dropdown. For bindings to drive text/icons on that screen, assign **MainViewModel** to Splash in the Rive editor and re-export. The app still binds `MainViewModel` at runtime either way.

### Current test in the app

On load, the app sets the **third** ForecastDays item’s `CurrentWeather` to **Heatwave** (Day label unchanged) and keeps all **4** days in the list.

## Run on the iPhone Simulator (Mac)

```bash
flutter pub get
open -a Simulator
flutter run -d iPhone
```

## Preview in a browser

```bash
flutter pub get
flutter run -d web-server --web-hostname=0.0.0.0 --web-port=43123
```

Then open [http://127.0.0.1:43123](http://127.0.0.1:43123).
