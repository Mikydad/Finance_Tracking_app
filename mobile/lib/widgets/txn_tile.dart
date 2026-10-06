import 'package:flutter/material.dart';

import '../core/dates.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../domain/category.dart';
import '../domain/transaction.dart';
import 'category_icon.dart';

/// One transaction row: category icon, name, "Category · 12:42", amount and
/// an Auto/Manual tag.
class TxnTile extends StatelessWidget {
  const TxnTile({super.key, required this.txn, required this.categories, this.onTap});

  final Txn txn;
  final Map<String, Category> categories;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final category = categories[txn.categoryId];
    final parent = categories[category?.parentId];
    final total = txn.signedTotal;
    final theme = Theme.of(context);
    final needsReview = txn.status == TransactionStatus.needsReview;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: CategoryIcon(category, parent: parent),
      title: Text(txn.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
      subtitle: Text(
        '${category?.name ?? 'Uncategorized'} · ${clock(txn.occurredAt)}',
        style: theme.textTheme.bodySmall?.copyWith(color: AppColors.muted),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '${total >= 0 ? '+' : '-'}${formatBirrCompact(total.abs())} ${txn.currency}',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: total >= 0 ? AppColors.income : AppColors.text,
            ),
          ),
          const SizedBox(height: 4),
          _Tag(needsReview ? 'Review' : (txn.isAutomatic ? 'Auto' : 'Manual'), highlight: needsReview),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, {this.highlight = false});

  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: highlight ? const Color(0xFFFFF1D6) : AppColors.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: highlight ? const Color(0xFFF2C46B) : AppColors.border),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
    );
  }
}
