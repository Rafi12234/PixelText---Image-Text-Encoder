// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:image_to_text/main.dart';

void main() {
  testWidgets('renders the image to text home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('PixelText Studio'), findsOneWidget);
    expect(find.text('Pick Image'), findsWidgets);
    expect(find.text('Decode Text'), findsOneWidget);
    expect(find.text('Copy Text'), findsOneWidget);
    expect(find.text('Save PDF'), findsOneWidget);
    expect(find.text('Download Image'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);
  });
}
