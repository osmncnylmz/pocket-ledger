import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/daos/transactions_dao.dart';
import '../../domain/date_range.dart';
import '../../domain/entities.dart';
import '../../domain/money.dart';
import '../providers.dart';
import '../sheets/filter_sheet.dart';
import '../sheets/transaction_editor_sheet.dart';
import '../theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/money_text.dart';
import '../widgets/transaction_tile.dart';

/// The ledger: every entry, newest first, grouped by day.
class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.text = ref.read(transactionFilterProvider).text;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Widens the SQL `LIMIT` when the list gets close to its end.
  bool _onScroll(ScrollNotification notification, LedgerPage page) {
    if (notification is! ScrollUpdateNotification &&
        notification is! ScrollEndNotification) {
      return false;
    }
    final metrics = notification.metrics;
    if (metrics.extentAfter > 600) return false;
    if (page.entries.length >= page.totalCount) return false;
    ref.read(visibleRowCountProvider.notifier).loadMore();
    return false;
  }

  Future<void> _delete(LedgerEntryDetail detail) async {
    final dao = ref.read(databaseProvider).transactionsDao;
    final messenger = ScaffoldMessenger.of(context);
    final removed = await dao.deleteEntry(detail.id);
    if (removed.isEmpty) return;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            removed.length > 1 ? 'Transfer deleted' : 'Transaction deleted',
          ),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => dao.restoreEntries(removed),
          ),
          duration: const Duration(seconds: 5),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final page = ref.watch(ledgerPageProvider);
    final filter = ref.watch(transactionFilterProvider);
    final ledgerIsEmpty = ref.watch(ledgerIsEmptyProvider).value ?? false;

    return Scaffold(
      body: switch (page) {
        AsyncError(:final error) => Center(child: Text('$error')),
        AsyncData(value: final data) =>
          NotificationListener<ScrollNotification>(
            onNotification: (notification) => _onScroll(notification, data),
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  title: const Text('Transactions'),
                  pinned: true,
                  actions: [
                    IconButton(
                      onPressed: _openFilters,
                      tooltip: 'Filter',
                      isSelected: filter.activeCount > 0,
                      icon: Badge.count(
                        count: filter.activeCount,
                        isLabelVisible: filter.activeCount > 0,
                        child: const Icon(Icons.tune),
                      ),
                    ),
                    const SizedBox(width: Insets.sm),
                  ],
                  bottom: PreferredSize(
                    preferredSize: const Size.fromHeight(64),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Insets.lg,
                        0,
                        Insets.lg,
                        Insets.md,
                      ),
                      child: _SearchField(
                        controller: _searchController,
                        onChanged: (text) => ref
                            .read(transactionFilterProvider.notifier)
                            .setText(text),
                      ),
                    ),
                  ),
                ),
                if (data.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: ledgerIsEmpty
                        ? EmptyState(
                            icon: Icons.receipt_long_outlined,
                            title: 'No transactions yet',
                            message:
                                'Record what you spend and earn, and this list '
                                'becomes the history everything else is built '
                                'from.',
                            action: FilledButton.icon(
                              onPressed: () => showTransactionEditor(context),
                              icon: const Icon(Icons.add),
                              label: const Text('Add a transaction'),
                            ),
                          )
                        : EmptyState(
                            icon: Icons.search_off_outlined,
                            title: 'Nothing matches',
                            message:
                                'No transaction matches the current search and '
                                'filters.',
                            action: TextButton(
                              onPressed: () {
                                _searchController.clear();
                                ref
                                    .read(transactionFilterProvider.notifier)
                                    .clear();
                              },
                              child: const Text('Clear filters'),
                            ),
                          ),
                  )
                else ...[
                  if (filter.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _ResultSummary(page: data, filter: filter),
                    ),
                  ..._buildDayGroups(data),
                  SliverToBoxAdapter(
                    child: _ListFooter(
                      loaded: data.entries.length,
                      total: data.totalCount,
                    ),
                  ),
                ],
              ],
            ),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  void _openFilters() {
    showFilterSheet(context);
  }

  List<Widget> _buildDayGroups(LedgerPage page) {
    final groups = <DateTime, List<LedgerEntryDetail>>{};
    for (final entry in page.entries) {
      groups.putIfAbsent(startOfDay(entry.date), () => []).add(entry);
    }

    return [
      for (final day in groups.keys)
        SliverMainAxisGroup(
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _DayHeaderDelegate(
                day: day,
                entries: groups[day]!,
                now: ref.read(nowProvider),
              ),
            ),
            SliverList.builder(
              itemCount: groups[day]!.length,
              itemBuilder: (context, index) {
                final detail = groups[day]![index];
                return _DismissibleEntry(
                  detail: detail,
                  onDelete: () => _delete(detail),
                );
              },
            ),
          ],
        ),
    ];
  }
}

class _DismissibleEntry extends StatelessWidget {
  const _DismissibleEntry({required this.detail, required this.onDelete});

  final LedgerEntryDetail detail;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(detail.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: AlignmentDirectional.centerEnd,
        color: context.ledgerColors.expenseContainer,
        padding: const EdgeInsets.symmetric(horizontal: Insets.xl),
        child: Icon(Icons.delete_outline, color: context.ledgerColors.expense),
      ),
      child: TransactionTile(
        detail: detail,
        onTap: () => showTransactionEditor(context, existing: detail),
      ),
    );
  }
}

class _DayHeaderDelegate extends SliverPersistentHeaderDelegate {
  _DayHeaderDelegate({
    required this.day,
    required this.entries,
    required this.now,
  });

  final DateTime day;
  final List<LedgerEntryDetail> entries;
  final DateTime now;

  static const _height = 42.0;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  String get _label {
    final today = startOfDay(now);
    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    if (day.year == today.year) return DateFormat('EEEE d MMMM').format(day);
    return DateFormat.yMMMMEEEEd().format(day);
  }

  Money get _net {
    final currency = entries.first.amount.currency;
    // Transfers net to zero across the ledger but not within one account, so
    // they are left out of the day total to keep it meaningful.
    return sumMoney(
      entries.where((e) => !e.entry.type.isTransfer).map((e) => e.amount),
      currency,
    );
  }

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return SizedBox(
      height: _height,
      child: DayHeader(label: _label, total: MoneyText(_net, forceSign: true)),
    );
  }

  @override
  bool shouldRebuild(_DayHeaderDelegate oldDelegate) =>
      oldDelegate.day != day || oldDelegate.entries.length != entries.length;
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search notes, categories, accounts',
        prefixIcon: const Icon(Icons.search),
        isDense: true,
        suffixIcon: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => controller.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Clear search',
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
        ),
      ),
    );
  }
}

class _ResultSummary extends ConsumerWidget {
  const _ResultSummary({required this.page, required this.filter});

  final LedgerPage page;
  final Object filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.sm, Insets.lg, 0),
      child: Row(
        children: [
          Text(
            page.totalCount == 1 ? '1 match' : '${page.totalCount} matches',
            style: context.texts.labelMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: () =>
                ref.read(transactionFilterProvider.notifier).clear(),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }
}

class _ListFooter extends StatelessWidget {
  const _ListFooter({required this.loaded, required this.total});

  final int loaded;
  final int total;

  @override
  Widget build(BuildContext context) {
    final more = total - loaded;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.lg,
        Insets.lg,
        Insets.lg,
        Insets.xxl * 2,
      ),
      child: Center(
        child: Text(
          more > 0 ? 'Loading $more more…' : 'That is all $total of them.',
          style: context.texts.bodySmall?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
