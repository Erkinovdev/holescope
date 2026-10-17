import 'package:flutter/material.dart';

/// Токены бренда из Figma («Holescope — Brand & Product»).
/// Тёмная палитра — точные значения из Figma.
/// Светлая палитра — ПРЕДЛОЖЕНИЕ (в Figma её нет): те же акценты, инвертированные поверхности,
/// текстовые варианты статусов затемнены ради контраста ≥ 4.5:1 (проверяется тестом test/contrast_test.dart).
@immutable
class HpColors extends ThemeExtension<HpColors> {
  const HpColors({
    required this.bgBase,
    required this.surface,
    required this.raised,
    required this.line,
    required this.text,
    required this.muted,
    required this.amber,
    required this.amberText,
    required this.amberDim,
    required this.smooth,
    required this.smoothText,
    required this.warn,
    required this.warnText,
    required this.crater,
    required this.craterText,
    required this.info,
    required this.inverse,
  });

  final Color bgBase, surface, raised, line, text, muted;
  final Color amber, amberText, amberDim;
  final Color smooth, smoothText, warn, warnText, crater, craterText, info;
  final Color inverse; // текст на янтарной кнопке

  static const dark = HpColors(
    bgBase: Color(0xFF0B0D12),
    surface: Color(0xFF151922),
    raised: Color(0xFF1D222D),
    line: Color(0xFF2A3040),
    text: Color(0xFFF2F4F8),
    muted: Color(0xFF8F99AB),
    amber: Color(0xFFFFB020),
    amberText: Color(0xFFFFB020),
    amberDim: Color(0xFF3A2C0F),
    smooth: Color(0xFF3ECF8E),
    smoothText: Color(0xFF3ECF8E),
    warn: Color(0xFFFF8A3D),
    warnText: Color(0xFFFF8A3D),
    crater: Color(0xFFFF5D5D),
    craterText: Color(0xFFFF5D5D),
    info: Color(0xFF4DA3FF),
    inverse: Color(0xFF0B0D12),
  );

  static const light = HpColors(
    bgBase: Color(0xFFF4F6FA),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFE8ECF3),
    line: Color(0xFFD3D9E4),
    text: Color(0xFF12151C),
    muted: Color(0xFF5B6577),
    amber: Color(0xFFFFB020),
    amberText: Color(0xFF8A5A00),
    amberDim: Color(0xFFFFE9BD),
    smooth: Color(0xFF3ECF8E),
    smoothText: Color(0xFF17724D),
    warn: Color(0xFFFF8A3D),
    warnText: Color(0xFF9A4A00),
    crater: Color(0xFFFF5D5D),
    craterText: Color(0xFFC02626),
    info: Color(0xFF4DA3FF),
    inverse: Color(0xFF0B0D12),
  );

  @override
  HpColors copyWith() => this;

  @override
  HpColors lerp(ThemeExtension<HpColors>? other, double t) {
    if (other is! HpColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return HpColors(
      bgBase: l(bgBase, other.bgBase),
      surface: l(surface, other.surface),
      raised: l(raised, other.raised),
      line: l(line, other.line),
      text: l(text, other.text),
      muted: l(muted, other.muted),
      amber: l(amber, other.amber),
      amberText: l(amberText, other.amberText),
      amberDim: l(amberDim, other.amberDim),
      smooth: l(smooth, other.smooth),
      smoothText: l(smoothText, other.smoothText),
      warn: l(warn, other.warn),
      warnText: l(warnText, other.warnText),
      crater: l(crater, other.crater),
      craterText: l(craterText, other.craterText),
      info: l(info, other.info),
      inverse: l(inverse, other.inverse),
    );
  }
}

extension HpTheme on BuildContext {
  HpColors get hp => Theme.of(this).extension<HpColors>()!;
}

/// Типографика из Figma (Inter). Размеры/начертания взяты из дизайн-контекста экранов.
class HpText {
  static TextStyle s(Color c, double size, FontWeight w, {double? ls, double? h}) =>
      TextStyle(fontFamily: 'Inter', color: c, fontSize: size, fontWeight: w, letterSpacing: ls, height: h);
}

ThemeData buildTheme(Brightness b) {
  final c = b == Brightness.dark ? HpColors.dark : HpColors.light;
  return ThemeData(
    useMaterial3: true,
    brightness: b,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: c.bgBase,
    canvasColor: c.bgBase,
    colorScheme: ColorScheme.fromSeed(seedColor: c.amber, brightness: b).copyWith(
      surface: c.surface,
      primary: c.amber,
      onPrimary: c.inverse,
      onSurface: c.text,
    ),
    dividerColor: c.line,
    extensions: [c],
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: c.surface, modalBackgroundColor: c.surface),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStatePropertyAll(c.inverse == c.bgBase && b == Brightness.dark ? c.bgBase : Colors.white),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.amber : c.raised),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
  );
}
