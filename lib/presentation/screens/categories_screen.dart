import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities.dart';
import '../../domain/enums.dart';
import '../category_icons.dart';
import '../providers.dart';
import '../sheets/category_editor_sheet.dart';
import '../theme.dart';
import '../widgets/empty_state.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expenses = ref.watch(categoriesProvider(CategoryKind.expense));
    final income = ref.watch(categoriesProvider(CategoryKind.income));

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Categories'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Expense'),
              Tab(text: 'Income'),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => showCategoryEditor(context),
          icon: const Icon(Icons.add),
          label: const Text('Category'),
        ),
        body: TabBarView(
          children: [
            _CategoryList(categories: expenses, kind: CategoryKind.expense),
            _CategoryList(categories: income, kind: CategoryKind.income),
          ],
        ),
      ),
    );
  }
}

class _CategoryList extends ConsumerWidget {
  const _CategoryList({required this.categories, required this.kind});

  final AsyncValue<List<Category>> categories;
  final CategoryKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (categories) {
      AsyncError(:final error) => Center(child: Text('$error')),
      AsyncData(value: final all) when all.isEmpty => EmptyState(
        icon: Icons.category_outlined,
        title: 'No ${kind.name} categories',
        message: 'Nothing to break spending down by yet.',
        action: FilledButton.icon(
          onPressed: () => showCategoryEditor(context, kind: kind),
          icon: const Icon(Icons.add),
          label: const Text('Add a category'),
        ),
      ),
      AsyncData(value: final all) => ListView.builder(
        padding: const EdgeInsets.only(bottom: 96),
        itemCount: all.length,
        itemBuilder: (context, index) {
          final category = all[index];
          return ListTile(
            onTap: () => showCategoryEditor(context, existing: category),
            contentPadding: EdgeInsets.only(
              left: category.isSubcategory ? Insets.xxl : Insets.lg,
              right: Insets.sm,
            ),
            leading: Icon(
              categoryIconFor(category.iconKey),
              color: Color(category.colorValue),
            ),
            title: Text(category.name),
            trailing: IconButton(
              tooltip: 'Archive',
              icon: const Icon(Icons.archive_outlined),
              onPressed: () => ref
                  .read(databaseProvider)
                  .categoriesDao
                  .setArchived(category.id, archived: true),
            ),
          );
        },
      ),
      _ => const Center(child: CircularProgressIndicator()),
    };
  }
}
