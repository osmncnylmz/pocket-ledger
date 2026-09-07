import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities.dart';
import '../../domain/enums.dart';
import '../category_icons.dart';
import '../providers.dart';
import '../theme.dart';

/// Opens the category editor. Pass [existing] to edit.
Future<void> showCategoryEditor(
  BuildContext context, {
  Category? existing,
  CategoryKind kind = CategoryKind.expense,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) =>
        CategoryEditorSheet(existing: existing, initialKind: kind),
  );
}

/// Creates and edits categories.
class CategoryEditorSheet extends ConsumerStatefulWidget {
  const CategoryEditorSheet({
    super.key,
    this.existing,
    this.initialKind = CategoryKind.expense,
  });

  final Category? existing;
  final CategoryKind initialKind;

  @override
  ConsumerState<CategoryEditorSheet> createState() =>
      _CategoryEditorSheetState();
}

class _CategoryEditorSheetState extends ConsumerState<CategoryEditorSheet> {
  late final TextEditingController _nameController;
  late CategoryKind _kind;
  late String _iconKey;
  late int _color;
  int? _parentId;
  String? _error;

  bool get _isEditing => widget.existing != null;

  static const _palette = <int>[
    0xFF2E7D32,
    0xFF00838F,
    0xFF5E35B1,
    0xFFEF6C00,
    0xFFC2185B,
    0xFF00695C,
    0xFF6A1B9A,
    0xFF1565C0,
  ];

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _kind = existing?.kind ?? widget.initialKind;
    _iconKey = existing?.iconKey ?? categoryIconKeys.first;
    _color = existing?.colorValue ?? _palette.first;
    _parentId = existing?.parentId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the category a name.');
      return;
    }

    final dao = ref.read(databaseProvider).categoriesDao;
    final navigator = Navigator.of(context);
    if (_isEditing) {
      await dao.updateCategory(
        id: widget.existing!.id,
        name: name,
        iconKey: _iconKey,
        colorValue: _color,
        kind: _kind,
        parentId: _parentId,
      );
    } else {
      await dao.createCategory(
        name: name,
        iconKey: _iconKey,
        colorValue: _color,
        kind: _kind,
        parentId: _parentId,
      );
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final siblings = (ref.watch(categoriesProvider(_kind)).value ?? const [])
        .where((c) => c.id != widget.existing?.id && !c.isSubcategory)
        .toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Insets.lg, 0, Insets.lg, Insets.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _isEditing ? 'Edit category' : 'New category',
              style: context.texts.titleLarge,
            ),
            const SizedBox(height: Insets.lg),
            TextField(
              controller: _nameController,
              autofocus: !_isEditing,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: 'Name', errorText: _error),
            ),
            const SizedBox(height: Insets.md),
            SegmentedButton<CategoryKind>(
              segments: const [
                ButtonSegment(
                  value: CategoryKind.expense,
                  label: Text('Expense'),
                ),
                ButtonSegment(
                  value: CategoryKind.income,
                  label: Text('Income'),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (selection) => setState(() {
                _kind = selection.first;
                _parentId = null;
              }),
            ),
            if (siblings.isNotEmpty) ...[
              const SizedBox(height: Insets.md),
              DropdownButtonFormField<int?>(
                initialValue: _parentId,
                decoration: const InputDecoration(
                  labelText: 'Parent category (optional)',
                ),
                items: [
                  const DropdownMenuItem(child: Text('None')),
                  for (final parent in siblings)
                    DropdownMenuItem(
                      value: parent.id,
                      child: Text(parent.name),
                    ),
                ],
                onChanged: (value) => setState(() => _parentId = value),
              ),
            ],
            const SizedBox(height: Insets.lg),
            Text(
              'Icon',
              style: context.texts.labelMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Insets.sm),
            Wrap(
              spacing: Insets.sm,
              runSpacing: Insets.sm,
              children: [
                for (final key in categoryIconKeys)
                  InkResponse(
                    onTap: () => setState(() => _iconKey = key),
                    radius: 24,
                    child: AnimatedContainer(
                      duration: Motion.of(context, Motion.quick),
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _iconKey == key
                            ? Color(_color).withValues(alpha: 0.18)
                            : context.colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _iconKey == key
                              ? Color(_color)
                              : Colors.transparent,
                          width: 1.5,
                        ),
                      ),
                      child: Icon(categoryIconFor(key), size: 20),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Insets.lg),
            Text(
              'Colour',
              style: context.texts.labelMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: Insets.sm),
            Wrap(
              spacing: Insets.md,
              children: [
                for (final value in _palette)
                  InkResponse(
                    onTap: () => setState(() => _color = value),
                    radius: 22,
                    child: AnimatedContainer(
                      duration: Motion.of(context, Motion.quick),
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Color(value),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _color == value
                              ? context.colors.onSurface
                              : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Insets.xl),
            FilledButton(
              onPressed: _save,
              child: Text(_isEditing ? 'Save' : 'Add category'),
            ),
          ],
        ),
      ),
    );
  }
}
