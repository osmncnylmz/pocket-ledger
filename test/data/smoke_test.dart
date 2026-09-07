import 'package:flutter_test/flutter_test.dart';

import 'test_database.dart';

void main() {
  test('an empty database opens and reports schema version 2', () async {
    await withTestDatabase((db) async {
      expect(db.schemaVersion, 2);
      expect(await db.transactionsDao.countAll(), 0);
    });
  });
}
