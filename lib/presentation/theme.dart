import 'package:flutter/material.dart';

/// Colours that mean something: money in, money out, and the two levels of
/// budget trouble. A [ThemeExtension] so both themes have to define them
/// explicitly and no widget guesses a shade from the brightness.
@immutable
class LedgerColors extends ThemeExtension<LedgerColors> {
  const LedgerColors({
    required this.income,
    required this.incomeContainer,
    required this.expense,
    required this.expenseContainer,
    required this.warning,
    required this.warningContainer,
    required this.gridLine,
  });

  final Color income;
  final Color incomeContainer;
  final Color expense;
  final Color expenseContainer;
  final Color warning;
  final Color warningContainer;
  final Color gridLine;

  static const light = LedgerColors(
    income: Color(0xFF15683F),
    incomeContainer: Color(0xFFD5F0DF),
    expense: Color(0xFF9B2C2C),
    expenseContainer: Color(0xFFFBE0E0),
    warning: Color(0xFF8A5300),
    warningContainer: Color(0xFFFCE9C8),
    gridLine: Color(0x142B2B2B),
  );

  static const dark = LedgerColors(
    income: Color(0xFF7BD9A4),
    incomeContainer: Color(0xFF12341F),
    expense: Color(0xFFFFA3A0),
    expenseContainer: Color(0xFF3D1A1A),
    warning: Color(0xFFF5C87A),
    warningContainer: Color(0xFF3A2A0D),
    gridLine: Color(0x1FFFFFFF),
  );

  @override
  LedgerColors copyWith({
    Color? income,
    Color? incomeContainer,
    Color? expense,
    Color? expenseContainer,
    Color? warning,
    Color? warningContainer,
    Color? gridLine,
  }) {
    return LedgerColors(
      income: income ?? this.income,
      incomeContainer: incomeContainer ?? this.incomeContainer,
      expense: expense ?? this.expense,
      expenseContainer: expenseContainer ?? this.expenseContainer,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
      gridLine: gridLine ?? this.gridLine,
    );
  }

  @override
  LedgerColors lerp(ThemeExtension<LedgerColors>? other, double t) {
    if (other is! LedgerColors) return this;
    return LedgerColors(
      income: Color.lerp(income, other.income, t)!,
      incomeContainer: Color.lerp(incomeContainer, other.incomeContainer, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      expenseContainer: Color.lerp(
        expenseContainer,
        other.expenseContainer,
        t,
      )!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      gridLine: Color.lerp(gridLine, other.gridLine, t)!,
    );
  }
}

extension LedgerTheme on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get texts => Theme.of(this).textTheme;
  LedgerColors get ledgerColors => Theme.of(this).extension<LedgerColors>()!;
}

/// For category slices where the category has no colour of its own. Ordered
/// so adjacent slices stay distinguishable.
const categoryFallbackPalette = <Color>[
  Color(0xFF3F7D6E),
  Color(0xFFB4693C),
  Color(0xFF4B6BB5),
  Color(0xFF9A5CA6),
  Color(0xFF2E8B7A),
  Color(0xFFB5525F),
  Color(0xFF7A7C3C),
  Color(0xFF5C6BC0),
];

/// One seed drives the whole scheme; everything else is Material 3 doing its
/// job. Both brightnesses come from it, so the two themes cannot drift apart.
const _seedColor = Color(0xFF15695B);

ThemeData buildAppTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: _seedColor,
    brightness: brightness,
  );
  final isLight = brightness == Brightness.light;
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);

  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    extensions: [isLight ? LedgerColors.light : LedgerColors.dark],
    textTheme: _tuneTypography(base.textTheme),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: scheme.surfaceTint,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
      minVerticalPadding: 10,
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.5),
      space: 1,
      thickness: 1,
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      side: BorderSide(color: scheme.outlineVariant),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
      elevation: 0,
      height: 68,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    ),
  );
}

/// Tighter headings, and tabular figures anywhere a number can appear so that
/// columns of money line up.
TextTheme _tuneTypography(TextTheme base) {
  const tabular = [FontFeature.tabularFigures()];
  return base.copyWith(
    displaySmall: base.displaySmall?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: -1,
      fontFeatures: tabular,
    ),
    headlineMedium: base.headlineMedium?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: -0.6,
      fontFeatures: tabular,
    ),
    headlineSmall: base.headlineSmall?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: -0.4,
      fontFeatures: tabular,
    ),
    titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w600),
    titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    labelLarge: base.labelLarge?.copyWith(letterSpacing: 0.1),
  );
}

/// Spacing steps. Ad hoc numbers drift.
abstract final class Insets {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

/// All in one place so "make it snappier" is one edit.
abstract final class Motion {
  static const quick = Duration(milliseconds: 180);
  static const normal = Duration(milliseconds: 320);
  static const chart = Duration(milliseconds: 700);
  static const curve = Curves.easeOutCubic;

  /// Zero when the platform asks for reduced motion, so every animation in the
  /// app honours the accessibility setting without each widget remembering to.
  static Duration of(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}
