import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../domain/category.dart';
import '../../providers.dart';
import '../../widgets/category_icon.dart';

/// Built-in categories (read-only) plus your own, which you can add, rename
/// and archive. Archived ones leave the pickers but stay on old transactions.
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = (ref.watch(categoryByIdProvider).value ?? const <String, Category>{}).values.toList();
    final active = all.where((c) => c.isTopLevel && !c.isArchived).toList();
    final archived = all.where((c) => c.isCustom && c.isArchived).toList();
    List<Category> childrenOf(Category c) => all.where((x) => x.parentId == c.id && !x.isArchived).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Categories'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Card(
            child: Column(
              children: [for (final c in active) _CategoryTile(category: c, children: childrenOf(c))],
            ),
          ),
          if (archived.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('Archived', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppColors.muted)),
            const SizedBox(height: 8),
            Card(
              child: Column(children: [for (final c in archived) _CategoryTile(category: c)]),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.tonalIcon(
            key: const Key('add-category'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            icon: const Icon(Icons.add),
            label: const Text('Add custom category'),
            onPressed: () => showCategoryEditor(context, ref),
          ),
        ],
      ),
    );
  }
}

class _CategoryTile extends ConsumerWidget {
  const _CategoryTile({required this.category, this.children = const []});

  final Category category;
  final List<Category> children;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(categoryRepositoryProvider);
    return ListTile(
      leading: CategoryIcon(category, size: 36),
      title: Text(category.name),
      subtitle: children.isEmpty
          ? (category.isCustom && !category.isArchived ? const Text('Custom') : null)
          : Text(children.map((c) => c.name).join(', '), maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: !category.isCustom
          ? null
          : category.isArchived
          ? TextButton(onPressed: () => repo.setArchived(category.id, false), child: const Text('Restore'))
          : PopupMenuButton<String>(
              key: Key('menu-${category.name}'),
              onSelected: (action) async {
                if (action == 'rename') {
                  await showCategoryEditor(context, ref, existing: category);
                } else {
                  await repo.setArchived(category.id, true);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('Rename')),
                PopupMenuItem(value: 'archive', child: Text('Archive')),
              ],
            ),
    );
  }
}

/// Add a custom category, or rename [existing].
Future<void> showCategoryEditor(BuildContext context, WidgetRef ref, {Category? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CategoryEditor(existing: existing),
  );
}

class _CategoryEditor extends ConsumerStatefulWidget {
  const _CategoryEditor({this.existing});

  final Category? existing;

  @override
  ConsumerState<_CategoryEditor> createState() => _CategoryEditorState();
}

class _CategoryEditorState extends ConsumerState<_CategoryEditor> {
  late final _name = TextEditingController(text: widget.existing?.name);
  CategoryKind _kind = CategoryKind.expense;
  String _icon = CategoryStyle.customIcons.keys.first;
  String _color = CategoryStyle.customColors.first;
  String? _error;

  bool get _renaming => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give it a name');
      return;
    }
    final repo = ref.read(categoryRepositoryProvider);
    if (_renaming) {
      await repo.rename(widget.existing!.id, name);
    } else {
      final userId = ref.read(sessionProvider).value?.user.id ?? 'local';
      await repo.add(userId: userId, name: name, kind: _kind, icon: _icon, color: _color);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final preview = Category(id: '', name: _name.text, icon: _icon, color: _color, isCustom: true);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_renaming ? 'Rename category' : 'New category', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Row(
            children: [
              if (!_renaming) ...[CategoryIcon(preview, size: 48), const SizedBox(width: 12)],
              Expanded(
                child: TextField(
                  key: const Key('category-name'),
                  controller: _name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(hintText: 'e.g. Church, Pets, Gym', errorText: _error),
                  onChanged: (_) => setState(() => _error = null),
                  onSubmitted: (_) => _save(),
                ),
              ),
            ],
          ),
          if (!_renaming) ...[
            const SizedBox(height: 16),
            SegmentedButton<CategoryKind>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: CategoryKind.expense, label: Text('Expense')),
                ButtonSegment(value: CategoryKind.income, label: Text('Income')),
                ButtonSegment(value: CategoryKind.both, label: Text('Both')),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.single),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final MapEntry(key: name, value: icon) in CategoryStyle.customIcons.entries)
                  _Choice(
                    selected: name == _icon,
                    onTap: () => setState(() => _icon = name),
                    child: Icon(icon, size: 22),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final hex in CategoryStyle.customColors)
                  _Choice(
                    selected: hex == _color,
                    onTap: () => setState(() => _color = hex),
                    child: CircleAvatar(radius: 12, backgroundColor: CategoryStyle.of(color: hex).color),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(key: const Key('save-category'), onPressed: _save, child: const Text('Save')),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.selected, required this.onTap, required this.child});

  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.icon),
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.icon),
          border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 2 : 1),
        ),
        child: child,
      ),
    );
  }
}
