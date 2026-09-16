import 'package:flutter_test/flutter_test.dart';
import 'package:richfield_connect/main.dart' show normalisedRegistrationNumber;

void main() {
  group('normalisedRegistrationNumber', () {
    test('accepts the canonical CIPC format', () {
      expect(normalisedRegistrationNumber('2019/123456/07'), '2019/123456/07');
    });

    test('accepts a number typed without punctuation and normalises it', () {
      expect(normalisedRegistrationNumber('201912345607'), '2019/123456/07');
      expect(normalisedRegistrationNumber('2019 123456 07'), '2019/123456/07');
      expect(normalisedRegistrationNumber('  2019-123456-07 '), '2019/123456/07');
    });

    test('refuses the wrong number of digits', () {
      expect(normalisedRegistrationNumber('2019/12345/07'), isNull);
      expect(normalisedRegistrationNumber('2019/1234567/07'), isNull);
      expect(normalisedRegistrationNumber(''), isNull);
    });

    test('refuses a year that cannot be a registration year', () {
      expect(normalisedRegistrationNumber('1899/123456/07'), isNull);
      final nextYear = DateTime.now().year + 1;
      expect(normalisedRegistrationNumber('$nextYear/123456/07'), isNull);
    });

    test('refuses text that is not a registration number at all', () {
      expect(normalisedRegistrationNumber('Acme Digital (Pty) Ltd'), isNull);
      expect(normalisedRegistrationNumber('0821234567'), isNull);
    });
  });
}
