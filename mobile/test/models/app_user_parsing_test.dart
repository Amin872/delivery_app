import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/core/errors/app_exception.dart';
import 'package:delivery_app/models/app_user.dart';

void main() {
  test('AppUser.fromMap throws AppException(malformed-data) for an unknown role',
      () {
    expect(
      () => AppUser.fromMap('user-1', {
        'email': 'a@b.com',
        'displayName': 'A',
        'role': 'not-a-real-role',
      }),
      throwsA(
        isA<AppException>().having((e) => e.code, 'code', 'malformed-data'),
      ),
    );
  });
}
