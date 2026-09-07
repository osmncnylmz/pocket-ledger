import 'package:drift/drift.dart';

import '../../domain/entities.dart';
import '../../domain/enums.dart';
import '../database.dart';
import '../mappers.dart';

part 'categories_dao.g.dart';

/// Queries over the category tree.
@DriftAccessor(tables: [Categories])
class CategoriesDao extends DatabaseAccessor<AppDatabase>
    with _$CategoriesDaoMixin {
  CategoriesDao(super.db);

  Stream<List<Category>> watchCategories({
    CategoryKind? kind,
    bool includeArchived = false,
  }) {
    return _query(
      kind: kind,
      includeArchived: includeArchived,
    ).watch().map((rows) => rows.map((row) => row.toEntity()).toList());
  }

  Future<List<Category>> allCategories({
    CategoryKind? kind,
    bool includeArchived = false,
  }) {
    return _query(
      kind: kind,
      includeArchived: includeArchived,
    ).get().then((rows) => rows.map((row) => row.toEntity()).toList());
  }

  MultiSelectable<CategoryRow> _query({
    CategoryKind? kind,
    bool includeArchived = false,
  }) {
    final query = select(categories)
      ..orderBy([
        // Parents sort above their children, then alphabetically.
        (c) => OrderingTerm.asc(coalesce([c.parentId, c.id])),
        (c) => OrderingTerm.asc(c.parentId.isNotNull()),
        (c) => OrderingTerm.asc(c.name),
      ]);
    if (kind != null) {
      query.where((c) => c.kind.equalsValue(kind));
    }
    if (!includeArchived) {
      query.where((c) => c.archived.equals(false));
    }
    return query;
  }

  Future<Category?> findById(int id) async {
    final row = await (select(
      categories,
    )..where((c) => c.id.equals(id))).getSingleOrNull();
    return row?.toEntity();
  }

  Future<int> createCategory({
    required String name,
    required String iconKey,
    required int colorValue,
    required CategoryKind kind,
    int? parentId,
  }) {
    return into(categories).insert(
      CategoriesCompanion.insert(
        name: name,
        iconKey: iconKey,
        colorValue: colorValue,
        kind: kind,
        parentId: Value(parentId),
      ),
    );
  }

  Future<void> updateCategory({
    required int id,
    required String name,
    required String iconKey,
    required int colorValue,
    required CategoryKind kind,
    int? parentId,
  }) {
    return (update(categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(
        name: Value(name),
        iconKey: Value(iconKey),
        colorValue: Value(colorValue),
        kind: Value(kind),
        parentId: Value(parentId),
      ),
    );
  }

  Future<void> setArchived(int id, {required bool archived}) {
    return (update(categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(archived: Value(archived)),
    );
  }

  /// Removes a category. Entries that referenced it become uncategorised
  /// (`ON DELETE SET NULL`) rather than disappearing, and any budget for it is
  /// cascaded away.
  Future<void> deleteCategory(int id) {
    return (delete(categories)..where((c) => c.id.equals(id))).go();
  }
}
