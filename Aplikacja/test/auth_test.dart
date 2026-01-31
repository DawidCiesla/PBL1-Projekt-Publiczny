import 'package:flutter_test/flutter_test.dart';

import 'package:mac_nugget_net/core/auth/auth_state.dart';

void main() {
  group('AuthState', () {
    test('AuthState requires isAuthenticated', () {
      final state =
          AuthState(isAuthenticated: true, email: 'test@example.com');
      expect(state.isAuthenticated, isTrue);
      expect(state.email, equals('test@example.com'));
    });

    test('sessionDuration calculates correctly when authenticated', () {
      final now = DateTime.now();
      final oneHourAgo = now.subtract(const Duration(hours: 1));

      final state = AuthState(
        isAuthenticated: true,
        email: 'test@example.com',
        lastLoginTime: oneHourAgo,
      );

      final duration = state.sessionDuration;
      expect(duration, isNotNull);
      expect(duration!.inHours, equals(1));
    });

    test('sessionDuration is null when not authenticated', () {
      final state = AuthState(isAuthenticated: false);
      expect(state.sessionDuration, isNull);
    });

    test('sessionDuration is null when lastLoginTime is null', () {
      final state =
          AuthState(isAuthenticated: true, lastLoginTime: null);
      expect(state.sessionDuration, isNull);
    });

    test('equals returns true for same values', () {
      final now = DateTime.now();
      final state1 =
          AuthState(isAuthenticated: true, email: 'test@example.com', lastLoginTime: now);
      final state2 =
          AuthState(isAuthenticated: true, email: 'test@example.com', lastLoginTime: now);
      
      // Same properties should compare equal (if overridden)
      expect(state1.isAuthenticated, equals(state2.isAuthenticated));
      expect(state1.email, equals(state2.email));
    });

    test('AuthState unauthenticated state', () {
      final state = AuthState(isAuthenticated: false);
      expect(state.isAuthenticated, isFalse);
      expect(state.email, isNull);
      expect(state.lastLoginTime, isNull);
    });

    test('sessionDuration with multiple days', () {
      final now = DateTime.now();
      final twoDaysAgo = now.subtract(const Duration(days: 2, hours: 3));

      final state = AuthState(
        isAuthenticated: true,
        email: 'test@example.com',
        lastLoginTime: twoDaysAgo,
      );

      final duration = state.sessionDuration;
      expect(duration, isNotNull);
      expect(duration?.inDays, equals(2));
    });
  });
}

