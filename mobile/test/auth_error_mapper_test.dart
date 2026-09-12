// AuthErrorMapper turns whatever GoTrue/PostgREST actually returns into the
// string the register/login screens show directly. When it has no case for
// an error shape, the raw exception message goes straight to the screen -
// which is exactly what happened with a failed confirmation email
// ({"code":"unexpected_failure","message":"Error sending confirmation
// email"}, 2026-09-12: Resend refused the configured sender domain).

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:richfield_connect/services/auth_error_mapper.dart';

void main() {
  group('confirmation email delivery failure', () {
    test('the exact 500 body GoTrue returns is mapped, not shown raw', () {
      final e = AuthException(
        '{"code":"unexpected_failure","message":"Error sending confirmation email"}',
        statusCode: '500',
      );
      final message = AuthErrorMapper.fromAuthException(e);
      expect(message, isNot(contains('unexpected_failure')));
      expect(message, isNot(contains('{')));
      expect(message, contains('try again'));
    });

    test('a plain "Error sending confirmation email" message also maps', () {
      final e = AuthException('Error sending confirmation email');
      expect(AuthErrorMapper.fromAuthException(e), isNot(contains('Error sending')));
    });
  });

  group('other known GoTrue shapes are unaffected', () {
    test('already registered', () {
      final e = AuthException('User already registered', statusCode: '400');
      expect(AuthErrorMapper.fromAuthException(e), contains('already exists'));
    });

    test('domain-rule trigger collapsed to a generic 500', () {
      final e = AuthException('Database error saving new user');
      expect(AuthErrorMapper.fromAuthException(e), contains('email is'));
    });

    test('suspended account', () {
      final e = AuthException('User is banned');
      expect(AuthErrorMapper.fromAuthException(e), contains('suspended'));
    });

    test('unconfirmed account signing in', () {
      final e = AuthException('Email not confirmed');
      expect(AuthErrorMapper.fromAuthException(e), contains('6-digit code'));
    });

    test('an unrecognised message still falls through unchanged', () {
      final e = AuthException('Some brand-new GoTrue message');
      expect(AuthErrorMapper.fromAuthException(e), 'Some brand-new GoTrue message');
    });
  });

  test('fromAny dispatches AuthException to fromAuthException', () {
    final e = AuthException('User already registered', statusCode: '400');
    expect(AuthErrorMapper.fromAny(e), contains('already exists'));
  });
}
