# Weather Buddy

A one-screen Flutter app that plays your Rive weather UI full-screen on **iPhone** and **Android**.

## What’s on screen

This `.riv` export doesn’t include a single artboard named `Main Screen 2`. The editor preview is assembled from several artboards; the app composites them and binds **one** shared `MainViewModel`:

| Layer | Artboard | Role |
| --- | --- | --- |
| Background | `Weather Bg` | Full-bleed sky |
| Hero text | `forecast detail` | Location, temps, weather label |
| Character | `Avocado Master` | Buddy + weather outfit animations |
| Day row | `forecast container` | 4-day `ForecastDays` list (each day keeps its animation) |

State machine on each layer: `Main State Machine`.

## Data binding

Helpers: `lib/weather_binding.dart`

| Brief (Dart API) | Path in this `.riv` |
| --- | --- |
| Location | `location` |
| ForecastDays | `forecastdayz` |
| SelectedForecast | `selectedday` |
| CurrentDegree | `currentdegreenumber` |
| ToDegree | `Todegree` |
| CurrentWeather / FromDegree / Day | same |

On load, the **3rd** forecast day is set to **Heatwave** (Day label unchanged).

## Run

```bash
flutter pub get
flutter run -d web-server --web-hostname=0.0.0.0 --web-port=43123
# or on a Mac: open -a Simulator && flutter run -d iPhone
```

Open [http://127.0.0.1:43123](http://127.0.0.1:43123).

## HTML preview

Static web build lives in **`preview/index.html`**. Phone-framed launcher: **`preview.html`**.

```bash
# Rebuild the HTML export
flutter build web --release -o preview

# Serve (required — don't open the file via file://)
python3 -m http.server 43125 --directory preview
# → http://127.0.0.1:43125/

# Or serve the whole repo (phone frame + preview/)
python3 -m http.server 43125
# → http://127.0.0.1:43125/preview.html
```

## Prefer a single artboard?

In the Rive editor, export an updated `.riv` that includes **Main Screen 2** as one artboard (with MainViewModel assigned). Replace `assets/weatherbuddy.riv` and we can switch the app back to a single full-screen artboard with `Fit.layout`.
