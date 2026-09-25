# Weather Buddy

A one-screen Flutter app that plays your Rive file full-screen on **iPhone** and **Android**.

| Setting | Value |
| --- | --- |
| File | `assets/weatherbuddy.riv` |
| Artboard | `MainScreen2` |
| State machine | `MainStateMachine` |
| Fit | `Fit.layout` (fills and adapts to any screen size) |

No menus, settings, or extra UI — just the animation (plus a brief loading / error state).

## What you need on your computer

1. **Flutter** — install from [flutter.dev](https://docs.flutter.dev/get-started/install)
2. For iPhone: a **Mac** with **Xcode** (includes the iPhone Simulator)
3. For Android: **Android Studio** (includes an emulator)

## Run on the iPhone Simulator (Mac)

```bash
flutter pub get
open -a Simulator
flutter run -d iPhone
```

If several devices are listed, pick the iPhone simulator ID from `flutter devices`.

## Run on an Android emulator

```bash
flutter pub get
flutter run -d android
```

## Preview in a browser (any computer)

Useful when you don’t have a simulator handy:

```bash
flutter pub get
flutter run -d chrome --web-port=43123
```

Then open [http://127.0.0.1:43123](http://127.0.0.1:43123).

## Replace the animation later

1. Export a new `.riv` from the Rive editor.
2. Replace `assets/weatherbuddy.riv`.
3. If you rename the artboard or state machine, update those names in `lib/main.dart`.
4. Run the app again.
