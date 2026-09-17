import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kgka_music_hl/ui/widgets/scroll_to_top_button.dart';

void main() {
  testWidgets('ScrollToTopButton appears on scroll and scrolls to top on tap', (tester) async {
    final controller = ScrollController();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              ListView.builder(
                controller: controller,
                itemCount: 100,
                itemExtent: 60.0,
                itemBuilder: (context, index) => Text('Item $index'),
              ),
              Positioned(
                right: 20,
                bottom: 20,
                child: ScrollToTopButton(
                  controller: controller,
                  threshold: 200.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // Initial state: offset is 0, button opacity is 0.0
    final initialOpacity = tester.widget<AnimatedOpacity>(
      find.descendant(
        of: find.byType(ScrollToTopButton),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(initialOpacity.opacity, 0.0);

    // Scroll down past the threshold (200px)
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(controller.offset, greaterThan(200.0));

    // Button should now be visible (opacity 1.0)
    final visibleOpacity = tester.widget<AnimatedOpacity>(
      find.descendant(
        of: find.byType(ScrollToTopButton),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(visibleOpacity.opacity, 1.0);

    // Tap the button
    await tester.tap(find.byType(ScrollToTopButton));
    await tester.pumpAndSettle();

    // Offset should now be scrolled back to top (0.0)
    expect(controller.offset, 0.0);

    // Button should be hidden again (opacity 0.0)
    final backToTopOpacity = tester.widget<AnimatedOpacity>(
      find.descendant(
        of: find.byType(ScrollToTopButton),
        matching: find.byType(AnimatedOpacity),
      ),
    );
    expect(backToTopOpacity.opacity, 0.0);
  });
}
