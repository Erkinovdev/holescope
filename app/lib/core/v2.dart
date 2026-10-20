import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'theme.dart';
import 'widgets.dart';

/// Строительные блоки экранов v2.1 по макетам Figma («Screens · v2.1»): плитка-иконка, строки списков, переключатели, ползунки.

Color toneOf(HpColors c, Tone t) => toneColor(c, t);

/// Плитка 40×40 со скруглением 12 и иконкой цвета тона.
class V2Icon extends StatelessWidget {
  const V2Icon(this.icon, this.tone, {super.key, this.size = 40});
  final IconData icon;
  final Tone tone;
  final double size;
  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    final col = toneOf(c, tone);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: col.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(size * 0.3)),
      alignment: Alignment.center,
      child: Icon(icon, size: size * 0.52, color: col),
    );
  }
}

/// Заголовок группы: мелкие прописные буквы.
class V2Section extends StatelessWidget {
  const V2Section(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6, left: 4),
        child: Text(text.toUpperCase(), style: HpText.s(context.hp.muted, 11, FontWeight.w700, ls: 1.2)),
      );
}

/// Строка списка: иконка, название, пояснение, справа значение или стрелка.
class V2Row extends StatelessWidget {
  const V2Row({super.key, required this.icon, required this.tone, required this.title, this.sub, this.value, this.trailing, this.onTap, this.chevron = true});
  final IconData icon;
  final Tone tone;
  final String title;
  final String? sub, value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron;
  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    return HpCard(
      padding: 14,
      radius: 18,
      onTap: onTap,
      child: Row(spacing: 12, children: [
        V2Icon(icon, tone),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
            Text(title, style: HpText.s(c.text, 15, FontWeight.w600)),
            if (sub != null) Text(sub!, style: HpText.s(c.muted, 12, FontWeight.w400, h: 1.3)),
          ]),
        ),
        if (value != null) Text(value!, style: HpText.s(c.amberText, 13, FontWeight.w700)),
        ?trailing,
        if (chevron && onTap != null) Icon(Icons.chevron_right_rounded, color: c.muted),
      ]),
    );
  }
}

/// Строка с переключателем.
class V2Toggle extends StatelessWidget {
  const V2Toggle({super.key, required this.icon, required this.tone, required this.title, this.sub, required this.value, required this.onChanged});
  final IconData icon;
  final Tone tone;
  final String title;
  final String? sub;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => V2Row(icon: icon, tone: tone, title: title, sub: sub, chevron: false, onTap: () => onChanged(!value), trailing: Switch(value: value, onChanged: onChanged));
}

/// Переключатель из 2–4 вариантов на всю ширину.
class V2Segments extends StatelessWidget {
  const V2Segments({super.key, required this.labels, required this.index, required this.onChanged});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: c.line)),
      child: Row(children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Semantics(
              button: true,
              selected: i == index,
              label: labels[i],
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: i == index ? c.amber : Colors.transparent, borderRadius: BorderRadius.circular(12)),
                  child: Text(labels[i], style: HpText.s(i == index ? c.inverse : c.muted, 14, FontWeight.w700)),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Карточка с ползунком и значением справа в заголовке.
class V2Slider extends StatelessWidget {
  const V2Slider({super.key, required this.title, required this.valueText, required this.value, required this.min, required this.max, required this.onChanged, this.divisions});
  final String title, valueText;
  final double value, min, max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    return HpCard(
      padding: 14,
      radius: 18,
      child: Column(children: [
        Row(children: [
          Expanded(child: Text(title, style: HpText.s(c.text, 15, FontWeight.w600))),
          Text(valueText, style: HpText.s(c.amberText, 14, FontWeight.w700)),
        ]),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(activeTrackColor: c.amber, inactiveTrackColor: c.raised, thumbColor: c.amber, overlayColor: c.amber.withValues(alpha: 0.12)),
          child: Slider(value: value.clamp(min, max), min: min, max: max, divisions: divisions, onChanged: onChanged),
        ),
      ]),
    );
  }
}

/// Экран подраздела: кнопка «назад», заголовок, прокручиваемый список блоков.
class V2Screen extends StatelessWidget {
  const V2Screen({super.key, required this.title, required this.children, this.bottom = const []});
  final String title;
  final List<Widget> children, bottom;
  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 20, 4),
            child: Row(children: [
              IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                icon: Icon(Icons.chevron_left_rounded, color: c.text, size: 30),
                onPressed: () => context.canPop() ? context.pop() : context.go('/settings'),
              ),
              Expanded(child: Text(title, style: HpText.s(c.text, 24, FontWeight.w700, ls: -0.3))),
            ]),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: children),
            ),
          ),
          if (bottom.isNotEmpty) Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 16), child: Column(spacing: 10, children: bottom)),
        ]),
      ),
    );
  }
}
