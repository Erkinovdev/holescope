// ignore_for_file: sort_child_properties_last
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/settings.dart';
import '../core/theme.dart';
import '../core/v2.dart';
import '../core/widgets.dart';
import '../l10n/tr.dart';
import '../services/config.dart';
import '../services/providers.dart';
import 'screens_live.dart' show permStateProvider;
import 'splash.dart' show drawMark;

// «Запуск и настройка» (Figma · Screens v2.1 · Flow 1): загрузка → язык → 3 слайда → геолокация → датчики → положение телефона → роль → тема → «Всё готово».

/// Каркас шага приветствия: содержимое сверху, кнопки внизу.
class OnbFrame extends StatelessWidget {
  const OnbFrame({super.key, required this.children, required this.buttons, this.top = 28});
  final List<Widget> children, buttons;
  final double top;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) => SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(22, top, 22, 20),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: box.maxHeight - top - 20),
                child: IntrinsicHeight(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [...children, const Spacer(), ...buttons]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

// ───────────────────────── Загрузка (3 секунды) ─────────────────────────
class WelcomeSplash extends ConsumerStatefulWidget {
  const WelcomeSplash({super.key});
  @override
  ConsumerState<WelcomeSplash> createState() => _WelcomeSplashState();
}

class _WelcomeSplashState extends ConsumerState<WelcomeSplash> with SingleTickerProviderStateMixin {
  late final AnimationController ctl = AnimationController(vsync: this);
  bool started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (started) return;
    started = true;
    final reduce = ref.read(settingsProvider).reduceMotion || MediaQuery.disableAnimationsOf(context);
    ctl.duration = Duration(milliseconds: reduce ? 700 : 3000);
    ctl.forward().whenComplete(() {
      if (!mounted) return;
      final done = ref.read(settingsProvider).onboarded;
      context.go(done ? (AppConfig.carMonitor ? '/car' : '/map') : '/onboarding/lang');
    });
  }

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  String _status(BuildContext context, double t) {
    if (t < 0.34) return context.tr('Запуск сенсоров…', 'Sensorlar ishga tushmoqda…');
    if (t < 0.62) return context.tr('Сканируем дорогу', 'Yoʻlni skanerlaymiz');
    if (t < 0.86) return context.tr('Собираем ямы в одну точку', 'Choʻqqilarni bir nuqtaga yigʻamiz');
    return context.tr('Готово', 'Tayyor');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    final reduce = ref.read(settingsProvider).reduceMotion || MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      backgroundColor: c.bgBase,
      body: Semantics(
        label: 'Holescope ${AppConfig.appVersion}',
        child: AnimatedBuilder(
          animation: ctl,
          builder: (_, __) {
            final t = reduce ? 1.0 : ctl.value;
            final logo = ((t - 0.8) / 0.2).clamp(0.0, 1.0);
            return Stack(fit: StackFit.expand, children: [
              CustomPaint(painter: _SplashPainter(t, c)),
              Positioned(
                left: 0,
                right: 0,
                bottom: 54,
                child: Column(spacing: 12, children: [
                  Text(_status(context, t), style: HpText.s(c.muted, 13, FontWeight.w500)),
                  SizedBox(
                    width: 200,
                    child: ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: t, minHeight: 3, color: c.amber, backgroundColor: c.line)),
                  ),
                  Text('${context.tr('Версия', 'Versiya')} ${AppConfig.appVersion}', style: HpText.s(c.muted.withValues(alpha: 0.8), 12, FontWeight.w500)),
                ]),
              ),
              Center(
                child: Opacity(
                  opacity: logo,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 150),
                    child: Column(mainAxisSize: MainAxisSize.min, spacing: 6, children: [
                      Text('Holescope', style: HpText.s(c.text, 34, FontWeight.w700, ls: -0.68)),
                      Text('See every hole before you hit it.', style: HpText.s(c.muted, 13, FontWeight.w400)),
                    ]),
                  ),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

class _SplashPainter extends CustomPainter {
  _SplashPainter(this.t, this.c);
  final double t;
  final HpColors c;

  static const _dots = [Offset(.22, .30), Offset(.30, .44), Offset(.74, .26), Offset(.80, .52), Offset(.40, .62), Offset(.66, .66)];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.42);
    // тонкая сетка дорог
    final road = Paint()..color = c.line.withValues(alpha: 0.35)..strokeWidth = 1.2..style = PaintingStyle.stroke;
    for (var i = 0; i < 6; i++) {
      final y = size.height * (0.12 + i * 0.16);
      canvas.drawPath(Path()..moveTo(0, y)..quadraticBezierTo(size.width * .5, y + 28 * (i.isEven ? 1 : -1), size.width, y - 10), road);
    }
    for (var i = 0; i < 4; i++) {
      final x = size.width * (0.15 + i * 0.24);
      canvas.drawLine(Offset(x, 0), Offset(x + 30, size.height), road);
    }
    // луч сканера слева направо (0 → 0.62)
    final scan = (t / 0.62).clamp(0.0, 1.0);
    if (t < 0.7) {
      final x = size.width * scan;
      final rect = Rect.fromLTRB(math.max(0, x - 120), 0, x, size.height);
      canvas.drawRect(rect, Paint()..shader = LinearGradient(colors: [c.amber.withValues(alpha: 0), c.amber.withValues(alpha: 0.35)]).createShader(rect));
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), Paint()..color = c.amber..strokeWidth = 2);
    }
    // красные точки появляются, когда луч их «открывает», затем стягиваются в центр
    final pull = ((t - 0.62) / 0.24).clamp(0.0, 1.0);
    for (final d in _dots) {
      final p = Offset(size.width * d.dx, size.height * d.dy);
      if (scan < d.dx) continue;
      final pos = Offset.lerp(p, center, Curves.easeInOut.transform(pull))!;
      final a = (1 - pull * 0.6);
      canvas.drawCircle(pos, 9, Paint()..color = c.crater.withValues(alpha: 0.25 * a));
      canvas.drawCircle(pos, 4.5, Paint()..color = c.crater.withValues(alpha: a));
    }
    // прицел-знак: проявляется по ходу сканирования, в конце светится
    final glow = ((t - 0.8) / 0.2).clamp(0.0, 1.0);
    if (glow > 0) {
      canvas.drawCircle(center, 120, Paint()..shader = RadialGradient(colors: [c.amber.withValues(alpha: 0.22 * glow), c.amber.withValues(alpha: 0)]).createShader(Rect.fromCircle(center: center, radius: 120)));
    }
    drawMark(canvas, center, 110, amber: c.amber, hole: c.bgBase, ring: (0.35 + 0.65 * t).clamp(0.0, 1.0), eye: (t * 1.4).clamp(0.0, 1.0));
  }

  @override
  bool shouldRepaint(_SplashPainter o) => o.t != t || o.c != c;
}

// ───────────────────────── Выбор языка ─────────────────────────
class LanguageStep extends ConsumerWidget {
  const LanguageStep({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hp;
    final s = ref.watch(settingsProvider);
    final cur = s.locale?.languageCode ?? Localizations.localeOf(context).languageCode;
    Widget card(String code, String name, String sub) {
      final sel = cur == code;
      return HpCard(
        radius: 20,
        padding: 14,
        color: sel ? c.amberDim : c.surface,
        borderColor: sel ? c.amber : c.line,
        borderWidth: sel ? 1.5 : 1,
        onTap: () => ref.read(settingsProvider.notifier).update((x) => x.copyWith(locale: Locale(code))),
        child: Row(spacing: 14, children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: sel ? c.amber : c.raised, shape: BoxShape.circle), alignment: Alignment.center, child: Text(code.toUpperCase(), style: HpText.s(sel ? c.inverse : c.muted, 14, FontWeight.w700))),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(name, style: HpText.s(c.text, 17, FontWeight.w600)), Text(sub, style: HpText.s(c.muted, 12, FontWeight.w400))])),
          Icon(sel ? Icons.check_rounded : Icons.chevron_right_rounded, color: sel ? c.amberText : c.muted),
        ]),
      );
    }

    return OnbFrame(
      children: [
        Row(spacing: 10, children: [const HpSvg('logo', size: 30), Text('Holescope', style: HpText.s(c.text, 20, FontWeight.w700))]),
        const SizedBox(height: 8),
        Text('Tilni tanlang\nВыберите язык', style: HpText.s(c.text, 30, FontWeight.w700, ls: -0.5, h: 1.15)),
        Text('Til keyin sozlamalardan oʻzgartiriladi · Язык можно сменить в настройках в любой момент.', style: HpText.s(c.muted, 13, FontWeight.w400, h: 1.35)),
        const SizedBox(height: 6),
        card('uz', 'Oʻzbekcha', 'Lotin yozuvi'),
        card('ru', 'Русский', 'Кириллица'),
      ],
      buttons: [HpButton(context.tr('Продолжить', 'Davom etish'), onPressed: () => context.go('/onboarding/intro'))],
    );
  }
}

// ───────────────────────── Три слайда ─────────────────────────
class IntroStep extends StatefulWidget {
  const IntroStep({super.key});
  @override
  State<IntroStep> createState() => _IntroStepState();
}

class _IntroStepState extends State<IntroStep> {
  final ctl = PageController();
  int page = 0;

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  void _next() {
    if (page >= 2) {
      context.go('/onboarding/location');
    } else {
      ctl.nextPage(duration: const Duration(milliseconds: 260), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    final pages = [
      (context.tr('Видим ямы раньше, чем вы', 'Choʻqqilarni sizdan oldin koʻramiz'), context.tr('Holescope предупредит о яме за 100–150 метров — как оповещение о камере, только о дороге.', 'Holescope 100–150 metr oldin ogohlantiradi — kamera haqidagi ogohlantirish kabi, faqat yoʻl haqida.')),
      (context.tr('Телефон — датчик дороги', 'Telefon — yoʻl datchigi'), context.tr('Акселерометр, гироскоп и GPS сами чувствуют удар. Ничего нажимать за рулём не нужно.', 'Akselerometr, giroskop va GPS zarbani oʻzlari sezadi. Rul orqasida hech narsa bosish shart emas.')),
      (context.tr('Солидарность водителей', 'Haydovchilar hamjihatligi'), context.tr('Каждая подтверждённая яма — это карта для всех. Чем нас больше, тем быстрее дороги чинят.', 'Har bir tasdiqlangan choʻqqi — hamma uchun xarita. Qancha koʻp boʻlsak, yoʻllar shuncha tez tuzatiladi.')),
    ];
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(
                  child: PageView(controller: ctl, onPageChanged: (i) => setState(() => page = i), children: [
                    for (var i = 0; i < 3; i++)
                      SingleChildScrollView(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
                          AspectRatio(aspectRatio: 1.15, child: ClipRRect(borderRadius: BorderRadius.circular(24), child: CustomPaint(painter: _SlidePainter(i, c, context.isUz)))),
                          Text(pages[i].$1, style: HpText.s(c.text, 28, FontWeight.w700, ls: -0.4, h: 1.15)),
                          Text(pages[i].$2, style: HpText.s(c.muted, 15, FontWeight.w400, h: 1.4)),
                        ]),
                      ),
                  ]),
                ),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.center, spacing: 6, children: [
                  for (var i = 0; i < 3; i++) AnimatedContainer(duration: const Duration(milliseconds: 180), width: i == page ? 22 : 7, height: 7, decoration: BoxDecoration(color: i == page ? c.amber : c.line, borderRadius: BorderRadius.circular(4))),
                ]),
                const SizedBox(height: 14),
                Row(spacing: 10, children: [
                  Expanded(child: HpButton(context.tr('Пропустить', 'Oʻtkazib yuborish'), kind: HpButtonKind.secondary, onPressed: () => context.go('/onboarding/location'))),
                  Expanded(flex: 2, child: HpButton(page >= 2 ? context.tr('Начать', 'Boshlash') : context.tr('Далее', 'Keyingi'), onPressed: _next)),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _SlidePainter extends CustomPainter {
  _SlidePainter(this.kind, this.c, this.uz);
  final int kind;
  final HpColors c;
  final bool uz;

  void _chip(Canvas canvas, Offset at, String text, Color col) {
    final tp = TextPainter(text: TextSpan(text: text, style: HpText.s(col, 12, FontWeight.w600)), textDirection: TextDirection.ltr)..layout();
    final r = RRect.fromRectAndRadius(Rect.fromLTWH(at.dx, at.dy, tp.width + 20, tp.height + 12), const Radius.circular(14));
    canvas.drawRRect(r, Paint()..color = c.bgBase.withValues(alpha: 0.85));
    canvas.drawRRect(r, Paint()..color = col.withValues(alpha: 0.5)..style = PaintingStyle.stroke);
    tp.paint(canvas, at + const Offset(10, 6));
  }

  @override
  void paint(Canvas canvas, Size s) {
    final bg = switch (kind) { 0 => c.surface, 1 => const Color(0xFF14202F), _ => const Color(0xFF14241F) };
    canvas.drawRect(Offset.zero & s, Paint()..color = c.brightnessIsDark ? bg : c.raised);
    final cx = s.width / 2;
    if (kind == 0) {
      // дорога в перспективе
      final road = Path()..moveTo(s.width * .38, 0)..lineTo(s.width * .62, 0)..lineTo(s.width * .95, s.height)..lineTo(s.width * .05, s.height)..close();
      canvas.drawPath(road, Paint()..color = c.raised);
      for (var i = 0; i < 6; i++) {
        final y0 = s.height * (i / 6.0 + .02), y1 = y0 + s.height * .06;
        canvas.drawLine(Offset(cx, y0), Offset(cx, y1), Paint()..color = c.muted.withValues(alpha: .5)..strokeWidth = 2 + i * .6);
      }
      final hole = Offset(cx, s.height * .66);
      canvas.drawOval(Rect.fromCenter(center: hole, width: s.width * .30, height: s.height * .13), Paint()..color = Colors.black.withValues(alpha: .85));
      canvas.drawOval(Rect.fromCenter(center: hole, width: s.width * .34, height: s.height * .16), Paint()..color = c.crater..style = PaintingStyle.stroke..strokeWidth = 2);
      _chip(canvas, Offset(s.width * .25, s.height * .08), uz ? 'Tezlikni 30 km/soatgacha kamaytiring' : 'Снизьте до 30 км/ч', c.amber);
      _chip(canvas, Offset(s.width * .16, s.height * .46), uz ? 'Choʻqqi · 8 sm · 120 m' : 'Яма · 8 см · через 120 м', c.crater);
    } else if (kind == 1) {
      final phone = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(cx, s.height * .5), width: s.width * .26, height: s.height * .56), const Radius.circular(16));
      for (var i = 1; i <= 3; i++) {
        canvas.drawCircle(Offset(cx, s.height * .5), s.width * (.14 + i * .08), Paint()..color = c.info.withValues(alpha: .18 / i)..style = PaintingStyle.stroke..strokeWidth = 1.5);
      }
      canvas.drawRRect(phone, Paint()..color = c.bgBase);
      canvas.drawRRect(phone, Paint()..color = c.muted..style = PaintingStyle.stroke..strokeWidth = 2);
      final pulse = Path()..moveTo(cx - s.width * .09, s.height * .52)..lineTo(cx - s.width * .04, s.height * .52)..lineTo(cx - s.width * .02, s.height * .42)..lineTo(cx + s.width * .02, s.height * .62)..lineTo(cx + s.width * .04, s.height * .52)..lineTo(cx + s.width * .09, s.height * .52);
      canvas.drawPath(pulse, Paint()..color = c.amber..style = PaintingStyle.stroke..strokeWidth = 3..strokeJoin = StrokeJoin.round);
      _chip(canvas, Offset(s.width * .06, s.height * .14), uz ? 'Akselerometr' : 'Акселерометр', c.info);
      _chip(canvas, Offset(s.width * .60, s.height * .30), uz ? 'Giroskop' : 'Гироскоп', c.smooth);
      _chip(canvas, Offset(s.width * .08, s.height * .76), 'GPS ±3 m', c.amber);
    } else {
      final rnd = math.Random(7);
      final pts = [for (var i = 0; i < 16; i++) Offset(s.width * (.08 + rnd.nextDouble() * .84), s.height * (.08 + rnd.nextDouble() * .72))];
      final center = Offset(cx, s.height * .46);
      for (final p in pts) {
        canvas.drawLine(p, center, Paint()..color = c.muted.withValues(alpha: .35)..strokeWidth = 1);
      }
      for (var i = 0; i < pts.length; i++) {
        canvas.drawCircle(pts[i], 5, Paint()..color = i % 4 == 0 ? c.crater : c.amber);
      }
      drawMark(canvas, center, 54, amber: c.amber, hole: bg);
      _chip(canvas, Offset(s.width * .22, s.height * .86), uz ? 'Toshkent haydovchilari' : 'Водители Ташкента', c.smooth);
    }
  }

  @override
  bool shouldRepaint(_SlidePainter o) => o.kind != kind || o.c != c;
}

extension on HpColors {
  bool get brightnessIsDark => bgBase.computeLuminance() < 0.3;
}

// ───────────────────────── Геолокация и датчики ─────────────────────────
class PermissionStep extends ConsumerStatefulWidget {
  const PermissionStep({super.key, required this.location});
  final bool location;
  @override
  ConsumerState<PermissionStep> createState() => _PermissionStepState();
}

class _PermissionStepState extends ConsumerState<PermissionStep> {
  bool busy = false;
  bool denied = false;
  bool permanent = false;

  String get _next => widget.location ? '/onboarding/motion' : '/onboarding/mount';

  Future<void> _ask() async {
    setState(() => busy = true);
    final svc = ref.read(permissionServiceProvider);
    final r = widget.location ? await svc.requestLocation() : await svc.requestMotion();
    if (!mounted) return;
    ref.invalidate(permStateProvider);
    final ok = widget.location ? r.location : (r.motion || r.notifications);
    setState(() {
      busy = false;
      denied = !ok;
      permanent = r.permanentlyDenied;
    });
    if (ok) context.go(_next);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    final loc = widget.location;
    final tone = loc ? c.amber : c.info;
    final bullets = loc
        ? [context.tr('Автостарт, когда вы поехали', 'Siz yoʻlga chiqqaningizda avtomatik boshlanadi'), context.tr('Точное место ямы с точностью ±3 м', 'Choʻqqining aniq joyi ±3 m aniqlikda'), context.tr('Координаты не привязаны к вашему имени', 'Koordinatalar ismingizga bogʻlanmagan')]
        : [context.tr('Данные уходят на сервер без номера телефона', 'Maʼlumotlar telefon raqamisiz serverga yuboriladi'), context.tr('Пешком и в автобусе запись отключается', 'Piyoda va avtobusda yozuv oʻchadi'), context.tr('Фоновая запись экономит батарею', 'Fon rejimi batareyani tejaydi')];
    return OnbFrame(
      top: 60,
      children: [
        Center(
          child: Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(shape: BoxShape.circle, color: tone.withValues(alpha: 0.12), border: Border.all(color: tone.withValues(alpha: 0.5), width: 2)),
            child: Icon(loc ? Icons.place_outlined : Icons.sensors_rounded, color: tone, size: 48),
          ),
        ),
        const SizedBox(height: 14),
        Text(loc ? context.tr('Геолокация «всегда»', 'Geolokatsiya «doim»') : context.tr('Датчики движения', 'Harakat datchiklari'), style: HpText.s(c.text, 28, FontWeight.w700, ls: -0.4)),
        Text(
          loc
              ? context.tr('Чтобы поездка записывалась сама, пока телефон в кармане или на сиденье.', 'Telefon cho‘ntakda yoki o‘rindiqda bo‘lganda safar o‘zi yozilishi uchun.')
              : context.tr('Читаем акселерометр и гироскоп только во время поездки на автомобиле.', 'Akselerometr va giroskopni faqat avtomobilda ketayotganda oʻqiymiz.'),
          style: HpText.s(c.muted, 14, FontWeight.w400, h: 1.4),
        ),
        const SizedBox(height: 6),
        for (final b in bullets) Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 10, children: [Icon(Icons.check_rounded, size: 18, color: c.smoothText), Expanded(child: Text(b, style: HpText.s(c.text, 13, FontWeight.w500, h: 1.35)))]),
        if (denied) Text(permanent ? context.tr('Доступ закрыт в системе. Откройте настройки приложения.', 'Ruxsat tizimda yopilgan. Ilova sozlamalarini oching.') : context.tr('Без этого запись не заработает. Можно разрешить позже в настройках.', 'Busiz yozuv ishlamaydi. Keyinroq sozlamalardan ruxsat berish mumkin.'), style: HpText.s(c.craterText, 13, FontWeight.w500)),
      ],
      buttons: [
        if (denied && permanent) HpButton(context.tr('Открыть настройки', 'Sozlamalarni ochish'), kind: HpButtonKind.secondary, onPressed: () => ref.read(permissionServiceProvider).openSettings()),
        HpButton(loc ? context.tr('Разрешить', 'Ruxsat berish') : context.tr('Разрешить датчики', 'Datchiklarga ruxsat'), loading: busy, onPressed: busy ? null : _ask),
        HpButton(context.tr('Позже', 'Keyinroq'), kind: HpButtonKind.secondary, onPressed: () => context.go(_next)),
      ],
    );
  }
}

// ───────────────────────── Положение телефона / роль / тема ─────────────────────────
class _Choice extends StatelessWidget {
  const _Choice({required this.icon, required this.tone, required this.title, required this.sub, required this.selected, required this.onTap, this.extra});
  final IconData icon;
  final Tone tone;
  final String title, sub;
  final bool selected;
  final VoidCallback onTap;
  final Widget? extra;
  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    return HpCard(
      radius: 18,
      padding: 14,
      color: selected ? c.amberDim : c.surface,
      borderColor: selected ? c.amber : c.line,
      borderWidth: selected ? 1.5 : 1,
      onTap: onTap,
      child: Row(spacing: 12, children: [
        V2Icon(icon, tone, size: 44),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [Text(title, style: HpText.s(c.text, 15, FontWeight.w700)), Text(sub, style: HpText.s(c.muted, 12, FontWeight.w400, h: 1.3)), ?extra])),
        Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, color: selected ? c.amber : c.line),
      ]),
    );
  }
}

String mountName(BuildContext c, PhoneMount m) => switch (m) {
      PhoneMount.seat => c.tr('На сиденье', 'Oʻrindiqda'),
      PhoneMount.cupholder => c.tr('В подстаканнике', 'Stakan tutqichda'),
      PhoneMount.holder => c.tr('В держателе на стекле', 'Oynadagi tutqichda'),
      PhoneMount.hand => c.tr('В руке / в кармане', 'Qoʻlda / choʻntakda'),
    };

String roleName(BuildContext c, DeviceRole r) => switch (r) {
      DeviceRole.driver => c.tr('Водитель', 'Haydovchi'),
      DeviceRole.passenger => c.tr('Пассажир (такси)', 'Yoʻlovchi (taksi)'),
      DeviceRole.research => c.tr('Исследователь', 'Tadqiqotchi'),
    };

/// Точность чтения ударов по положению телефона (3 деления).
int mountAccuracy(PhoneMount m) => switch (m) { PhoneMount.seat => 2, PhoneMount.cupholder => 3, PhoneMount.holder => 3, PhoneMount.hand => 1 };

class MountStep extends ConsumerWidget {
  const MountStep({super.key, this.onboarding = true});
  final bool onboarding;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hp;
    final s = ref.watch(settingsProvider);
    final sub = {
      PhoneMount.seat: context.tr('Экран вверх, не двигается', 'Ekran tepada, qimirlamaydi'),
      PhoneMount.cupholder: context.tr('Плотно, вертикально', 'Zich, vertikal'),
      PhoneMount.holder: context.tr('Лучшая запись ударов', 'Zarbalar eng yaxshi yoziladi'),
      PhoneMount.hand: context.tr('Запись будет шумной', 'Yozuv shovqinli boʻladi'),
    };
    final icons = {PhoneMount.seat: Icons.smartphone_rounded, PhoneMount.cupholder: Icons.local_cafe_outlined, PhoneMount.holder: Icons.speed_rounded, PhoneMount.hand: Icons.person_outline_rounded};
    Widget bars(int n) => Row(spacing: 3, children: [Text(context.tr('Точность', 'Aniqlik'), style: HpText.s(c.muted, 10, FontWeight.w500)), for (var i = 0; i < 3; i++) Container(width: 16, height: 3, decoration: BoxDecoration(color: i < n ? c.smooth : c.line, borderRadius: BorderRadius.circular(2)))]);
    final list = [PhoneMount.seat, PhoneMount.cupholder, PhoneMount.holder, PhoneMount.hand];
    Widget body() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
          for (final m in list)
            _Choice(
              icon: icons[m]!,
              tone: m == s.mount ? Tone.amber : Tone.muted,
              title: mountName(context, m),
              sub: sub[m]!,
              selected: s.mount == m,
              extra: bars(mountAccuracy(m)),
              onTap: () => ref.read(settingsProvider.notifier).update((x) => x.copyWith(mount: m)),
            ),
        ]);
    final title = context.tr('Где лежит телефон?', 'Telefon qayerda turadi?');
    final lead = context.tr('От этого зависит, как читать удары. Позже определим автоматически.', 'Zarbalarni qanday oʻqish shunga bogʻliq. Keyinroq avtomatik aniqlaymiz.');
    if (!onboarding) return V2Screen(title: title, children: [Text(lead, style: HpText.s(c.muted, 13, FontWeight.w400)), body()]);
    return OnbFrame(
      top: 40,
      children: [Text(title, style: HpText.s(c.text, 28, FontWeight.w700, ls: -0.4)), Text(lead, style: HpText.s(c.muted, 14, FontWeight.w400, h: 1.4)), body()],
      buttons: [HpButton(context.tr('Продолжить', 'Davom etish'), onPressed: () => context.go('/onboarding/role'))],
    );
  }
}

class RoleStep extends ConsumerWidget {
  const RoleStep({super.key, this.onboarding = true});
  final bool onboarding;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hp;
    final s = ref.watch(settingsProvider);
    final subs = {
      DeviceRole.driver: context.tr('Моя машина, мой маршрут', 'Mening mashinam, mening yoʻlim'),
      DeviceRole.passenger: context.tr('Запись идёт, в рейтинг не попадает', 'Yozuv ketadi, reytingga kirmaydi'),
      DeviceRole.research: context.tr('Ручная разметка и сырые данные', 'Qoʻlda belgilash va xom maʼlumot'),
    };
    final icons = {DeviceRole.driver: Icons.directions_car_filled_outlined, DeviceRole.passenger: Icons.groups_2_outlined, DeviceRole.research: Icons.build_outlined};
    final tones = {DeviceRole.driver: Tone.amber, DeviceRole.passenger: Tone.info, DeviceRole.research: Tone.smooth};
    final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
      for (final r in DeviceRole.values)
        _Choice(icon: icons[r]!, tone: tones[r]!, title: roleName(context, r), sub: subs[r]!, selected: s.role == r, onTap: () => ref.read(settingsProvider.notifier).update((x) => x.copyWith(role: r))),
      HpCard(
        radius: 14,
        padding: 12,
        color: c.info.withValues(alpha: 0.1),
        child: Row(spacing: 10, children: [Icon(Icons.info_outline_rounded, size: 18, color: c.info), Expanded(child: Text(context.tr('Автобус и трамвай приложение отсеет само — в карту ям они не попадут.', 'Avtobus va tramvayni ilova oʻzi ajratadi — ular choʻqqilar xaritasiga kirmaydi.'), style: HpText.s(c.text, 12, FontWeight.w500, h: 1.35)))]),
      ),
    ]);
    final title = context.tr('Кто вы в этой поездке?', 'Bu safarda siz kimsiz?');
    final lead = context.tr('Влияет на вес ваших данных на карте.', 'Maʼlumotlaringizning xaritadagi ogʻirligiga taʼsir qiladi.');
    if (!onboarding) return V2Screen(title: title, children: [Text(lead, style: HpText.s(c.muted, 13, FontWeight.w400)), body]);
    return OnbFrame(
      top: 40,
      children: [Text(title, style: HpText.s(c.text, 28, FontWeight.w700, ls: -0.4)), Text(lead, style: HpText.s(c.muted, 14, FontWeight.w400)), body],
      buttons: [HpButton(context.tr('Продолжить', 'Davom etish'), onPressed: () => context.go('/onboarding/theme'))],
    );
  }
}

class ThemeStep extends ConsumerWidget {
  const ThemeStep({super.key, this.onboarding = true});
  final bool onboarding;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hp;
    final s = ref.watch(settingsProvider);
    final n = ref.read(settingsProvider.notifier);
    Widget mini(ThemeMode m, String label, Color bg, Color bar) {
      final sel = s.themeMode == m;
      return Expanded(
        child: GestureDetector(
          onTap: () => n.update((x) => x.copyWith(themeMode: m)),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: sel ? c.amber : c.line, width: sel ? 2 : 1)),
            child: Column(spacing: 8, children: [
              Container(
                height: 84,
                decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.all(8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
                  Container(height: 6, width: 40, color: bar.withValues(alpha: .7)),
                  Container(height: 14, color: bar.withValues(alpha: .18)),
                  Container(height: 14, color: bar.withValues(alpha: .18)),
                  Container(height: 6, width: 24, color: c.amber),
                ]),
              ),
              Text(label, style: HpText.s(sel ? c.amberText : c.text, 12, FontWeight.w700)),
            ]),
          ),
        ),
      );
    }

    final title = context.tr('Оформление', 'Koʻrinish');
    final lead = context.tr('Светлая днём, тёмная ночью — или как в системе.', 'Kunduzi yorugʻ, kechasi qorongʻi — yoki tizimdagidek.');
    final body = Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
      Row(spacing: 10, children: [
        mini(ThemeMode.light, context.tr('Светлая', 'Yorugʻ'), const Color(0xFFF4F6FA), const Color(0xFF12151C)),
        mini(ThemeMode.dark, context.tr('Тёмная', 'Qorongʻi'), const Color(0xFF0B0D12), const Color(0xFFF2F4F8)),
        mini(ThemeMode.system, context.tr('Системная', 'Tizim'), const Color(0xFF1D222D), const Color(0xFFB8C0CF)),
      ]),
      V2Toggle(icon: Icons.bolt_rounded, tone: Tone.muted, title: context.tr('Меньше анимаций', 'Kamroq animatsiya'), sub: context.tr('Для слабых телефонов', 'Zaif telefonlar uchun'), value: s.reduceMotion, onChanged: (v) => n.update((x) => x.copyWith(reduceMotion: v))),
    ]);
    if (!onboarding) return V2Screen(title: title, children: [Text(lead, style: HpText.s(c.muted, 13, FontWeight.w400)), body]);
    return OnbFrame(
      top: 40,
      children: [Text(title, style: HpText.s(c.text, 28, FontWeight.w700, ls: -0.4)), Text(lead, style: HpText.s(c.muted, 14, FontWeight.w400)), body],
      buttons: [HpButton(context.tr('Продолжить', 'Davom etish'), onPressed: () => context.go('/onboarding/ready'))],
    );
  }
}

// ───────────────────────── Всё готово ─────────────────────────
class ReadyStep extends ConsumerWidget {
  const ReadyStep({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hp;
    final s = ref.watch(settingsProvider);
    final lang = (s.locale?.languageCode ?? Localizations.localeOf(context).languageCode) == 'uz' ? 'Oʻzbekcha' : 'Русский';
    Widget chip(String t, Color col) => Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: col.withValues(alpha: .14), borderRadius: BorderRadius.circular(999)), child: Text(t, style: HpText.s(col, 12, FontWeight.w700)));
    return OnbFrame(
      top: 80,
      children: [
        Center(child: Container(width: 112, height: 112, decoration: BoxDecoration(shape: BoxShape.circle, color: c.smooth.withValues(alpha: .1), border: Border.all(color: c.smooth.withValues(alpha: .6), width: 2)), child: Icon(Icons.check_rounded, size: 56, color: c.smooth))),
        const SizedBox(height: 16),
        Text(context.tr('Всё готово!', 'Hammasi tayyor!'), textAlign: TextAlign.center, style: HpText.s(c.text, 30, FontWeight.w700, ls: -0.5)),
        Text(context.tr('Поездка начнётся сама, когда вы тронетесь. Мы подскажем, где яма, и учтём ваши удары.', 'Siz yoʻlga chiqqaningizda safar oʻzi boshlanadi. Choʻqqi qayerdaligini aytamiz va zarbalaringizni hisobga olamiz.'), textAlign: TextAlign.center, style: HpText.s(c.muted, 14, FontWeight.w400, h: 1.4)),
        Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [chip(lang, c.amber), chip(mountName(context, s.mount), c.info), chip(roleName(context, s.role), c.smooth)]),
        Text('${context.tr('Версия', 'Versiya')} ${AppConfig.appVersion}', textAlign: TextAlign.center, style: HpText.s(c.muted, 12, FontWeight.w500)),
      ],
      buttons: [
        HpButton(context.tr('На карту', 'Xaritaga'), onPressed: () {
          ref.read(settingsProvider.notifier).update((x) => x.copyWith(onboarded: true, autoRecord: true));
          context.go(AppConfig.carMonitor ? '/car' : '/map');
        }),
      ],
    );
  }
}
