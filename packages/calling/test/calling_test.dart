import 'package:flutter_test/flutter_test.dart';

import 'package:calling/calling.dart';

void main() {
  test('CallingService starts disconnected', () {
    final callingService = CallingService();

    expect(callingService.isConnected, isFalse);
    expect(callingService.room, isNull);
  });
}
