import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:holescope/core/theme.dart';
import 'package:holescope/l10n/app_localizations.dart';

String fig(String name) => 'assets/figma/$name.svg';

/// Тело экрана: отступы 20, вертикальный список с gap 16 (как в Figma "Body").
class HpBody extends StatelessWidget {
  const HpBody({super.key, required this.children, this.top = 24, this.scroll = true, this.bottom = 20});
  final List<Widget> children;
  final double top, bottom;
  final bool scroll;

  @override
  Widget build(BuildContext context) {
    final col = Padding(
      padding: EdgeInsets.fromLTRB(20, top, 20, bottom),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: children),
    );
    return scroll ? SingleChildScrollView(child: col) : col;
  }
}

class HpTitle extends StatelessWidget {
  const HpTitle(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) =>
      Text(text, style: HpText.s(context.hp.text, 28, FontWeight.w700, ls: -0.42));
}

class HpSub extends StatelessWidget {
  const HpSub(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) =>
      Text(text, style: HpText.s(context.hp.muted, 14, FontWeight.w400, h: 20 / 14));
}

class HpCard extends StatelessWidget {
  const HpCard({super.key, required this.child, this.padding = 16, this.radius = 20, this.border = false, this.color, this.borderColor, this.borderWidth = 1, this.onTap});
  final Widget child;
  final double padding, radius, borderWidth;
  final bool border;
  final Color? color, borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    return Material(
      color: color ?? c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: (border || borderColor != null) ? BorderSide(color: borderColor ?? c.line, width: borderWidth) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: EdgeInsets.all(padding), child: child)),
    );
  }
}

enum HpButtonKind { primary, secondary, danger }

class HpButton extends StatelessWidget {
  const HpButton(this.label, {super.key, this.kind = HpButtonKind.primary, this.onPressed});
  final String label;
  final HpButtonKind kind;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    final (bg, fg, border) = switch (kind) {
      HpButtonKind.primary => (c.amber, c.inverse, null),
      HpButtonKind.secondary => (c.raised, c.text, c.line),
      HpButtonKind.danger => (c.surface, c.craterText, c.line),
    };
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: border == null ? BorderSide.none : BorderSide(color: border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Center(child: Text(label, style: HpText.s(fg, 16, FontWeight.w600))),
          ),
        ),
      ),
    );
  }
}

enum Tone { smooth, minor, major, info, muted, amber }

Color toneColor(HpColors c, Tone t) => switch (t) {
      Tone.smooth => c.smooth,
      Tone.minor => c.warn,
      Tone.major => c.crater,
      Tone.info => c.info,
      Tone.muted => c.muted,
      Tone.amber => c.amber,
    };

class HpDot extends StatelessWidget {
  const HpDot(this.tone, {super.key, this.size = 8});
  final Tone tone;
  final double size;
  @override
  Widget build(BuildContext context) =>
      Container(width: size, height: size, decoration: BoxDecoration(color: toneColor(context.hp, tone), shape: BoxShape.circle));
}

class HpChip extends StatelessWidget {
  const HpChip(this.label, this.tone, {super.key});
  final String label;
  final Tone tone;
  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 14, 8),
      decoration: BoxDecoration(color: c.raised, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
        HpDot(tone),
        Flexible(child: Text(label, style: HpText.s(c.text, 13, FontWeight.w500), overflow: TextOverflow.ellipsis)),
      ]),
    );
  }
}

/// Плашка NEW / метка раздела.
class HpBadge extends StatelessWidget {
  const HpBadge(this.label, {super.key});
  final String label;
  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.amberDim, borderRadius: BorderRadius.circular(999)),
      child: Text(label, style: HpText.s(c.amberText, 11, FontWeight.w700, ls: 0.88)),
    );
  }
}

/// Иконка списка: квадрат 44 r14 + точка (в Figma "List item/Icon").
class HpIconDot extends StatelessWidget {
  const HpIconDot(this.tone, {super.key});
  final Tone tone;
  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: c.raised, borderRadius: BorderRadius.circular(14)),
      alignment: Alignment.center,
      child: HpDot(tone, size: 14),
    );
  }
}

class HpListItem extends StatelessWidget {
  const HpListItem({super.key, required this.tone, required this.title, required this.subtitle, this.trailing, this.onTap, this.border = true});
  final Tone tone;
  final String title, subtitle;
  final String? trailing;
  final VoidCallback? onTap;
  final bool border;

  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    return HpCard(
      border: border,
      onTap: onTap,
      child: Row(spacing: 14, children: [
        HpIconDot(tone),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
            Text(title, style: HpText.s(c.text, 16, FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(subtitle, style: HpText.s(c.muted, 13, FontWeight.w400), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        if (trailing != null) Text(trailing!, style: HpText.s(c.text, 15, FontWeight.w600)),
      ]),
    );
  }
}

class HpProgress extends StatelessWidget {
  const HpProgress(this.value, this.color, {super.key});
  final double value; // 0..1
  final Color color;
  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 8,
        color: c.raised,
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: value.clamp(0.0, 1.0),
          child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
        ),
      ),
    );
  }
}

class HpSegmented extends StatelessWidget {
  const HpSegmented({super.key, required this.labels, required this.index, required this.onChanged});
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(16)),
      child: Row(spacing: 4, children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: Semantics(
              button: true,
              selected: i == index,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(color: i == index ? c.raised : c.surface, borderRadius: BorderRadius.circular(12)),
                  alignment: Alignment.center,
                  child: Text(labels[i], style: HpText.s(i == index ? c.text : c.muted, 14, FontWeight.w600)),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class HpToggleRow extends StatelessWidget {
  const HpToggleRow({super.key, required this.label, required this.value, required this.onChanged});
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    return HpCard(
      padding: 18,
      child: Row(children: [
        Expanded(child: Text(label, style: HpText.s(c.text, 16, FontWeight.w500))),
        Switch(value: value, onChanged: onChanged),
      ]),
    );
  }
}

class HpNavRow extends StatelessWidget {
  const HpNavRow({super.key, required this.label, this.onTap, this.value});
  final String label;
  final String? value;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    return HpCard(
      padding: 18,
      onTap: onTap,
      child: Row(spacing: 8, children: [
        Expanded(child: Text(label, style: HpText.s(c.text, 16, FontWeight.w500))),
        if (value != null) Text(value!, style: HpText.s(c.muted, 14, FontWeight.w400)),
        Text('›', style: HpText.s(c.muted, 20, FontWeight.w500)),
      ]),
    );
  }
}

/// Строки «ключ — значение» в карточке (Figma "Details").
class HpDetails extends StatelessWidget {
  const HpDetails(this.rows, {super.key});
  final List<(String, String, Color?)> rows;
  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    return HpCard(
      padding: 0,
      child: Column(children: [
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Expanded(child: Text(r.$1, style: HpText.s(c.muted, 15, FontWeight.w400))),
              Text(r.$2, style: HpText.s(r.$3 ?? c.text, 15, FontWeight.w600)),
            ]),
          ),
      ]),
    );
  }
}

/// SVG из Figma; [tint] перекрашивает монохромные иконки под тему.
class HpSvg extends StatelessWidget {
  const HpSvg(this.name, {super.key, this.size, this.tint});
  final String name;
  final double? size;
  final Color? tint;
  @override
  Widget build(BuildContext context) => SvgPicture.asset(fig(name),
      width: size, height: size, colorFilter: tint == null ? null : ColorFilter.mode(tint!, BlendMode.srcIn));
}

enum PinKind { major, minor, fixed }

class HpPin extends StatelessWidget {
  const HpPin(this.kind, {super.key});
  final PinKind kind;
  @override
  Widget build(BuildContext context) => HpSvg(switch (kind) { PinKind.major => 'pin_major', PinKind.minor => 'pin_minor', PinKind.fixed => 'pin_fixed' }, size: 36);
}

/// Схематичная карта из Figma (сетка улиц + янтарный маршрут + пины).
/// TODO(этап 2/3): заменить на maplibre_gl с реальными тайлами OSM; координаты пинов — из /map/clusters.
class SchematicMap extends StatelessWidget {
  const SchematicMap({super.key, this.pins = const [], this.route = false, this.clusters = const [], this.radius = 0});
  final List<(double, double, PinKind)> pins; // доли ширины/высоты ЦЕНТРА пина
  final List<(double, double, int)> clusters;
  final bool route;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ColoredBox(
        color: c.surface,
        child: LayoutBuilder(builder: (context, k) {
          final w = k.maxWidth, h = k.maxHeight;
          return Stack(children: [
            Positioned.fill(child: CustomPaint(painter: _GridPainter(c.raised, c.amber, route))),
            for (final p in pins) Positioned(left: p.$1 * w - 18, top: p.$2 * h - 18, child: HpPin(p.$3)),
            for (final cl in clusters)
              Positioned(
                left: cl.$1 * w - 24,
                top: cl.$2 * h - 24,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: c.amber.withValues(alpha: 0.35), shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(color: c.amber, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text('${cl.$3}', style: HpText.s(c.inverse, 14, FontWeight.w700)),
                  ),
                ),
              ),
          ]);
        }),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.road, this.amber, this.route);
  final Color road, amber;
  final bool route;
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..color = road;
    for (final fx in [0.18, 0.5, 0.82]) {
      canvas.drawRect(Rect.fromLTWH(fx * s.width - 7 + 7, 0, 14, s.height), p); // x как в Figma: left = fx*w
    }
    for (final fy in [0.2, 0.52, 0.8]) {
      canvas.drawRect(Rect.fromLTWH(0, fy * s.height, s.width, 14), p);
    }
    if (route) {
      final a = Paint()..color = amber..strokeCap = StrokeCap.round..strokeWidth = 6;
      final x = 0.51 * s.width + 0; // 199/390
      final y1 = 0.2 * s.height + 7, y2 = 0.52 * s.height + 7;
      canvas.drawLine(Offset(x + 3, y1), Offset(x + 3, y2), a);
      canvas.drawLine(Offset(x + 3, y2), Offset(0.82 * s.width, y2), a);
    }
  }

  @override
  bool shouldRepaint(_GridPainter o) => o.road != road || o.amber != amber || o.route != route;
}

class DemoBanner extends StatelessWidget {
  const DemoBanner({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: c.amberDim, borderRadius: BorderRadius.circular(10)),
      child: Text(AppLocalizations.of(context).demoBanner, style: HpText.s(c.amberText, 12, FontWeight.w500)),
    );
  }
}

/// Нижняя навигация (Figma "Tab bar": высота 88, 4 вкладки).
class HpTabBar extends StatelessWidget {
  const HpTabBar({super.key, required this.index, required this.onTap});
  final int index;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    final l = AppLocalizations.of(context);
    final tabs = [('tab_map', l.tabMap), ('tab_drive', l.tabDrive), ('tab_list', l.tabStreets), ('tab_user', l.tabProfile)];
    return Container(
      color: c.surface,
      padding: EdgeInsets.only(top: 10, left: 12, right: 12, bottom: MediaQuery.paddingOf(context).bottom),
      child: SizedBox(
        height: 54,
        child: Row(children: [
          for (var i = 0; i < tabs.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == index,
                label: tabs[i].$2,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onTap(i),
                  child: Column(spacing: 4, children: [
                    HpSvg(tabs[i].$1, size: 24, tint: i == index ? c.amberText : c.muted),
                    Text(tabs[i].$2, style: HpText.s(i == index ? c.amberText : c.muted, 11, FontWeight.w500)),
                  ]),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Оболочка с нижними вкладками для go_router StatefulShellRoute.
class HpShell extends StatelessWidget {
  const HpShell({super.key, required this.shell});
  final StatefulNavigationShell shell;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(bottom: false, child: shell),
        bottomNavigationBar: HpTabBar(index: shell.currentIndex, onTap: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex)),
      );
}

/// Экран без вкладок: безопасная область + кнопка «назад» при необходимости.
class HpPage extends StatelessWidget {
  const HpPage({super.key, required this.child, this.back = true});
  final Widget child;
  final bool back;
  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    return Scaffold(
      body: SafeArea(
        child: Stack(children: [
          Positioned.fill(child: child),
          if (back && context.canPop())
            Positioned(
              right: 12,
              top: 8,
              child: IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                icon: Icon(Icons.close_rounded, color: c.muted),
                onPressed: () => context.pop(),
              ),
            ),
        ]),
      ),
    );
  }
}
