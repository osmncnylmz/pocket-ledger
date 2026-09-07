import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/backup_files.dart';
import '../../data/backup_service.dart';
import '../../data/seed.dart';
import '../../domain/enums.dart';
import '../../domain/money.dart';
import '../providers.dart';
import '../settings.dart';
import '../theme.dart';
import 'accounts_screen.dart';
import 'categories_screen.dart';

final backupFileStoreProvider = Provider<BackupFileStore>(
  (ref) => const BackupFileStore(),
);

/// Preferences, the data the app is holding, and the way to get it out.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Insets.xxl * 2),
        children: [
          const _SectionHeading('Appearance'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
            child: SegmentedButton<AppThemeMode>(
              segments: const [
                ButtonSegment(
                  value: AppThemeMode.system,
                  label: Text('System'),
                  icon: Icon(Icons.brightness_auto_outlined),
                ),
                ButtonSegment(
                  value: AppThemeMode.light,
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode_outlined),
                ),
                ButtonSegment(
                  value: AppThemeMode.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode_outlined),
                ),
              ],
              selected: {settings.themeMode},
              onSelectionChanged: (selection) => ref
                  .read(settingsProvider.notifier)
                  .setThemeMode(selection.first),
            ),
          ),
          const _SectionHeading('Currency'),
          ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: const Text('Display currency'),
            subtitle: Text(
              'New accounts and every total on the dashboard use '
              '${settings.currency.code}.',
            ),
            trailing: DropdownButton<String>(
              value: settings.currency.code,
              underline: const SizedBox.shrink(),
              items: [
                for (final currency in Currency.supported)
                  DropdownMenuItem(
                    value: currency.code,
                    child: Text('${currency.symbol}  ${currency.code}'),
                  ),
              ],
              onChanged: (code) {
                if (code == null) return;
                ref
                    .read(settingsProvider.notifier)
                    .setCurrency(Currency.byCode(code));
              },
            ),
          ),
          const _SectionHeading('Ledger'),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('Accounts'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => const AccountsScreen(),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('Categories'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (context) => const CategoriesScreen(),
              ),
            ),
          ),
          const _SectionHeading('Backup'),
          const _BackupSection(),
          const _SectionHeading('About'),
          const _AboutSection(),
        ],
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.lg,
        Insets.xl,
        Insets.lg,
        Insets.sm,
      ),
      child: Text(
        text,
        style: context.texts.labelLarge?.copyWith(
          color: context.colors.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _BackupSection extends ConsumerStatefulWidget {
  const _BackupSection();

  @override
  ConsumerState<_BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends ConsumerState<_BackupSection> {
  bool _busy = false;

  void _report(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? context.colors.errorContainer : null,
        ),
      );
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final json = await ref.read(backupServiceProvider).exportToJson();
      await Clipboard.setData(ClipboardData(text: json));

      String? path;
      try {
        final file = await ref.read(backupFileStoreProvider).write(json);
        path = file.path;
      } on Object {
        // No writable documents directory (a plain test host, for example).
        // The clipboard copy above still gives the user their data.
        path = null;
      }

      _report(
        path == null
            ? 'Backup copied to the clipboard.'
            : 'Backup copied to the clipboard and saved to $path',
      );
    } on Object catch (error) {
      _report('Export failed: $error', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final files = await _listBackups();
    if (!mounted) return;

    final source = await showModalBottomSheet<_ImportSource>(
      context: context,
      builder: (context) => _ImportPicker(files: files),
    );
    if (source == null || !mounted) return;

    String json;
    if (source.file != null) {
      json = await source.file!.readAsString();
    } else {
      final pasted = await _promptForJson();
      if (pasted == null) return;
      json = pasted;
    }

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace everything?'),
        content: const Text(
          'Importing replaces every account, category, transaction and budget '
          'currently in the app with the contents of the backup.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;

    setState(() => _busy = true);
    try {
      final summary = await ref
          .read(backupServiceProvider)
          .importFromJson(json);
      _report(
        'Restored ${summary.transactions} transactions across '
        '${summary.accounts} accounts.',
      );
    } on BackupFormatException catch (error) {
      _report(error.message, isError: true);
    } on Object catch (error) {
      _report('Import failed: $error', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<List<File>> _listBackups() async {
    try {
      return await ref.read(backupFileStoreProvider).list();
    } on Object {
      return const [];
    }
  }

  Future<String?> _promptForJson() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Paste a backup'),
        content: TextField(
          controller: controller,
          maxLines: 8,
          decoration: const InputDecoration(hintText: '{ "format": … }'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result == null || result.trim().isEmpty ? null : result;
  }

  Future<void> _loadSample() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Load sample data?'),
        content: const Text(
          'This replaces everything in the app with six months of generated '
          'transactions, so the charts and budgets have something to show.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Load'),
          ),
        ],
      ),
    );
    if (!(confirmed ?? false)) return;

    setState(() => _busy = true);
    try {
      await loadSampleData(
        ref.read(databaseProvider),
        currency: ref.read(activeCurrencyProvider),
      );
      _report('Sample ledger loaded.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          enabled: !_busy,
          leading: const Icon(Icons.ios_share_outlined),
          title: const Text('Export a backup'),
          subtitle: const Text(
            'Writes the whole ledger as readable JSON and copies it to the '
            'clipboard.',
          ),
          onTap: _busy ? null : _export,
        ),
        ListTile(
          enabled: !_busy,
          leading: const Icon(Icons.download_outlined),
          title: const Text('Restore from a backup'),
          subtitle: const Text('Replaces everything currently in the app.'),
          onTap: _busy ? null : _import,
        ),
        ListTile(
          enabled: !_busy,
          leading: const Icon(Icons.auto_awesome_outlined),
          title: const Text('Load sample data'),
          subtitle: const Text('Six months of generated transactions.'),
          onTap: _busy ? null : _loadSample,
        ),
      ],
    );
  }
}

class _ImportSource {
  const _ImportSource.file(this.file);
  const _ImportSource.paste() : file = null;

  final File? file;
}

class _ImportPicker extends StatelessWidget {
  const _ImportPicker({required this.files});

  final List<File> files;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(Insets.lg),
            child: Text('Restore from', style: context.texts.titleMedium),
          ),
          for (final file in files.take(10))
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(file.uri.pathSegments.last),
              subtitle: Text(
                DateFormat.yMMMd().add_jm().format(file.statSync().modified),
              ),
              onTap: () => Navigator.of(context).pop(_ImportSource.file(file)),
            ),
          if (files.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
              child: Text(
                'No exported files found on this device.',
                style: context.texts.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.content_paste),
            title: const Text('Paste JSON'),
            onTap: () => Navigator.of(context).pop(const _ImportSource.paste()),
          ),
          const SizedBox(height: Insets.lg),
        ],
      ),
    );
  }
}

class _AboutSection extends ConsumerWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    final count = ref.watch(ledgerCountProvider);

    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.storage_outlined),
          title: const Text('Stored locally'),
          subtitle: Text(
            'SQLite, schema version ${db.schemaVersion}. '
            '${count.value ?? 0} transactions. '
            'Nothing leaves this device.',
          ),
        ),
      ],
    );
  }
}
