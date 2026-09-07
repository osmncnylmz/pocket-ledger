import 'package:flutter/material.dart';

/// The icons a category can use, keyed by the string stored in the database.
///
/// Every entry is a `const IconData` written out in source. That is the whole
/// reason categories store an icon *key* rather than a code point: constructing
/// `IconData(codePoint)` at runtime defeats Flutter's icon tree-shaking and
/// forces `--no-tree-shake-icons` on release builds, which drags the entire
/// Material font into the bundle.
const categoryIcons = <String, IconData>{
  'groceries': Icons.local_grocery_store_outlined,
  'home': Icons.home_outlined,
  'transport': Icons.directions_bus_outlined,
  'dining': Icons.restaurant_outlined,
  'utilities': Icons.bolt_outlined,
  'health': Icons.favorite_outline,
  'entertainment': Icons.movie_outlined,
  'shopping': Icons.shopping_bag_outlined,
  'travel': Icons.flight_takeoff_outlined,
  'subscriptions': Icons.repeat_outlined,
  'education': Icons.school_outlined,
  'pets': Icons.pets_outlined,
  'gift': Icons.card_giftcard_outlined,
  'salary': Icons.work_outline,
  'freelance': Icons.laptop_mac_outlined,
  'interest': Icons.savings_outlined,
  'other': Icons.category_outlined,
};

/// The icon for [key], falling back to a neutral one for anything unknown (an
/// imported backup from a newer version, say).
IconData categoryIconFor(String key) =>
    categoryIcons[key] ?? Icons.category_outlined;

/// Keys in a stable order, for the icon picker.
List<String> get categoryIconKeys => categoryIcons.keys.toList();

/// The icon used for an account of a given kind.
const accountIcons = <String, IconData>{
  'cash': Icons.payments_outlined,
  'checking': Icons.account_balance_outlined,
  'savings': Icons.savings_outlined,
  'credit': Icons.credit_card_outlined,
  'investment': Icons.trending_up_outlined,
};
