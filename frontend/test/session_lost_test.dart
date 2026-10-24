import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/api/api_client.dart';

void main() {
  test('a 409 with SESSION_NOT_OPEN means the server forgot the document', () {
    expect(
      isSessionLostResponse(
        409,
        '{"detail":"SESSION_NOT_OPEN: that document is no longer open on the server"}',
      ),
      isTrue,
    );
  });

  test('other answers do not', () {
    expect(isSessionLostResponse(200, 'SESSION_NOT_OPEN'), isFalse);
    expect(isSessionLostResponse(409, '{"detail":"DOCUMENT_BUSY"}'), isFalse);
    expect(isSessionLostResponse(401, 'SESSION_NOT_OPEN'), isFalse);
    expect(isSessionLostResponse(500, ''), isFalse);
  });
}
