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

## Website files (HTML)

The live web app (same files previously on the Cloudflare tunnel) is committed under **`docs/`**:

- `docs/index.html` — app entry
- `docs/main.dart.js`, `docs/canvaskit/`, `docs/assets/` — Flutter web runtime + Rive asset

### Local preview

```bash
cd docs && python3 -m http.server 43210
# → http://127.0.0.1:43210/
```

Rebuild after code changes:

```bash
flutter build web --release --base-href / -o docs
```

### GitHub Pages (share with others)

1. Repo → **Settings → Pages**
2. Source: **Deploy from a branch**
3. Branch: `main` / folder: **/docs** → Save
4. Site URL will be like:  
   `https://surbhi23nagar-beep.github.io/Weatherbuddy-App/`

(If the app looks broken on Pages, rebuild with  
`flutter build web --release --base-href /Weatherbuddy-App/ -o docs` and push again.)

## Prefer a single artboard?

In the Rive editor, export an updated `.riv` that includes **Main Screen 2** as one artboard (with MainViewModel assigned). Replace `assets/weatherbuddy.riv` and we can switch the app back to a single full-screen artboard with `Fit.layout`.
