// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mac_nugget_net/app.dart';
import 'package:mac_nugget_net/core/auth/auth_state.dart';

class _TestAuthController extends AuthController {
  @override
  Future<AuthState> build() async => const AuthState(isAuthenticated: false);
}

void main() {
  testWidgets('shows login screen when unauthenticated', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_TestAuthController.new),
        ],
        child: const MacNuggetNetApp(),
      ),
    );

    // Let routing settle after the initial redirect to /login.
    await tester.pumpAndSettle();

    expect(find.text('Smart Kurnik'), findsOneWidget);
    expect(find.text('Zaloguj'), findsOneWidget);
  });
}
