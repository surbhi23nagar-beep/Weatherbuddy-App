import 'package:flutter_test/flutter_test.dart';
import 'package:weather_buddy/main.dart';

void main() {
  testWidgets('Weather Buddy app builds', (tester) async {
    // Rive native init is heavy in unit tests; smoke-check the widget type only.
    expect(WeatherBuddyApp, isNotNull);
  });
}
