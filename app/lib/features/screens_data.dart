import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:holescope/core/road_map.dart';
import 'package:holescope/core/loaders.dart';
import 'package:holescope/core/theme.dart';
import 'package:holescope/core/widgets.dart';
import 'package:holescope/features/screens_live.dart' show fmtDate, fmtKm;
import 'package:holescope/l10n/app_localizations.dart';
import 'package:holescope/services/api_client.dart';
import 'package:holescope/services/data_providers.dart';
import 'package:holescope/services/providers.dart';

// Экраны с данными сервера: карта, карточка ямы, рейтинги, жалобы, отчёт недели.

String _daysAgo(AppLocalizations l, DateTime t) {
  final d = DateTime.now().difference(t).inDays;
  return d <= 0 ? l.today : l.daysAgoShort(d);
}

String _levelName(AppLocalizations l, String level) => switch (level) { 'light' => l.levelLight, 'mid' => l.levelMid, 'danger' => l.levelDanger, _ => l.levelDeep };

class _Error extends StatelessWidget {
  const _Error({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    return Column(spacing: 12, children: [
      Text(l.noConnection, style: HpText.s(c.craterText, 14, FontWeight.w500)),
      HpButton(l.retry, kind: HpButtonKind.secondary, onPressed: onRetry),
    ]);
  }
}

Widget _loading() => const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: SkeletonList());

// ───────────────────────── Живая карта ─────────────────────────
class LiveMapScreen extends ConsumerStatefulWidget {
  const LiveMapScreen({super.key});
  @override
  ConsumerState<LiveMapScreen> createState() => _LiveMapScreenState();
}

class _LiveMapScreenState extends ConsumerState<LiveMapScreen> {
  final ctl = RoadMapController();
  List<ClusterDto> clusters = const [];
  bool centered = false;
  String filter = 'all';

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  static const _filters = <(String, String, IconData)>[
    ('all', 'Все', Icons.layers_outlined),
    ('deep', 'Глубокие', Icons.trip_origin_rounded),
    ('manholes', 'Люки', Icons.circle_outlined),
    ('humps', 'Лежачие', Icons.show_chart_rounded),
    ('rails', 'Рельсы', Icons.train_outlined),
  ];

  Future<void> _pickFilter() async {
    final c = context.hp;
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          for (final f in _filters)
            ListTile(
              leading: Icon(f.$3, color: f.$1 == filter ? c.amber : c.muted),
              title: Text(f.$2, style: HpText.s(c.text, 16, FontWeight.w500)),
              trailing: f.$1 == filter ? Icon(Icons.check_rounded, color: c.amber) : null,
              onTap: () => Navigator.pop(context, f.$1),
            ),
        ]),
      ),
    );
    if (v != null) setState(() => filter = v);
  }

  ClusterDto? _nearest() {
    if (clusters.isEmpty) return null;
    final la = ctl.meLat ?? ctl.lat, lo = ctl.meLon ?? ctl.lon;
    ClusterDto? best;
    var bd = double.infinity;
    for (final c in clusters) {
      final d = (c.lat - la) * (c.lat - la) + (c.lon - lo) * (c.lon - lo);
      if (d < bd) {
        bd = d;
        best = c;
      }
    }
    return best;
  }

  double _meters(double la1, double lo1, double la2, double lo2) {
    final dy = (la2 - la1) * 111320, dx = (lo2 - lo1) * 111320 * 0.75;
    return (dx * dx + dy * dy) == 0 ? 0 : Offset(dx, dy).distance;
  }

  Future<void> _search() async {
    final l = AppLocalizations.of(context);
    final hit = await showModalBottomSheet<SearchHit>(context: context, isScrollControlled: true, builder: (_) => const _SearchSheet());
    if (hit != null) ctl.moveTo(hit.lat, hit.lon, mpp: hit.type == 'district' ? 8 : 2.5);
    if (hit == null || !mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    // l используется для доступности подсказки поиска
    assert(l.searchTitle.isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    final snap = ref.watch(recorderSnapshotProvider);
    if (snap.lat != null && snap.lon != null) {
      ctl.setMe(snap.lat, snap.lon, snap.heading);
      if (!centered) {
        centered = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => ctl.moveTo(snap.lat!, snap.lon!));
      }
    }
    final near = _nearest();
    return Stack(children: [
      Positioned.fill(child: RoadMapView(controller: ctl, filter: filter, onClusters: (v) => setState(() => clusters = v), onClusterTap: (cl) => context.push('/pothole/${cl.id}'))),
      Positioned(
        left: 16,
        right: 16,
        top: 12,
        child: SafeArea(
          bottom: false,
          child: Column(spacing: 10, children: [
            Row(spacing: 10, children: [
              Expanded(
                child: HpCard(
                  border: true,
                  padding: 14,
                  radius: 18,
                  onTap: _search,
                  child: Row(spacing: 10, children: [
                    HpSvg('search_icon', size: 22, tint: c.muted),
                    Expanded(child: Text(l.searchHint, style: HpText.s(c.muted, 15, FontWeight.w400), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ]),
                ),
              ),
              Semantics(
                button: true,
                label: 'Фильтр',
                child: Material(
                  color: c.amber,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _pickFilter,
                    child: SizedBox(width: 52, height: 52, child: Icon(Icons.filter_alt_outlined, color: c.inverse, size: 24)),
                  ),
                ),
              ),
            ]),
            SizedBox(
              height: 40,
              width: double.infinity,
              child: ListView(scrollDirection: Axis.horizontal, clipBehavior: Clip.none, children: [
                for (final f in _filters)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _FilterChip(label: f.$2, icon: f.$3, on: f.$1 == filter, onTap: () => setState(() => filter = f.$1)),
                  ),
              ]),
            ),
          ]),
        ),
      ),
      Positioned(left: 16, bottom: near == null ? 96 : 124, child: const RoughnessLegend(vertical: true)),
      Positioned(
        right: 16,
        bottom: near == null ? 96 : 124,
        child: _RoundBtn(
          icon: Icons.my_location_rounded,
          label: 'Моё место',
          onTap: () {
            final la = ctl.meLat, lo = ctl.meLon;
            if (la != null && lo != null) ctl.moveTo(la, lo, mpp: 2.5);
          },
        ),
      ),
      Positioned(
        left: 16,
        right: 16,
        bottom: 16,
        child: near == null
            ? HpCard(border: true, child: Text(l.noPotholesNearby, style: HpText.s(c.muted, 14, FontWeight.w500)))
            : _NearestCard(cluster: near, distanceM: _meters(ctl.meLat ?? ctl.lat, ctl.meLon ?? ctl.lon, near.lat, near.lon)),
      ),
    ]);
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.icon, required this.on, required this.onTap});
  final String label;
  final IconData icon;
  final bool on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    return Material(
      color: on ? c.amber : c.surface,
      shape: StadiumBorder(side: BorderSide(color: on ? c.amber : c.line)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(mainAxisSize: MainAxisSize.min, spacing: 7, children: [
            Icon(icon, size: 17, color: on ? c.inverse : c.muted),
            Text(label, style: HpText.s(on ? c.inverse : c.text, 14, FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: c.surface,
        shape: CircleBorder(side: BorderSide(color: c.line)),
        elevation: 4,
        shadowColor: Colors.black54,
        child: InkWell(customBorder: const CircleBorder(), onTap: onTap, child: SizedBox(width: 52, height: 52, child: Icon(icon, color: c.text, size: 24))),
      ),
    );
  }
}

class _NearestCard extends ConsumerWidget {
  const _NearestCard({required this.cluster, required this.distanceM});
  final ClusterDto cluster;
  final double distanceM;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    final detail = ref.watch(clusterDetailProvider(cluster.id)).value;
    final km = distanceM >= 1000;
    final major = cluster.level == 'deep' || cluster.level == 'danger';
    final tone = major ? c.crater : c.warn;
    final dist = km ? l.kmValue(fmtKm(distanceM / 1000)) : l.mValue('${distanceM.round()}');
    final title = detail?.street ?? '${cluster.lat.toStringAsFixed(4)}, ${cluster.lon.toStringAsFixed(4)}';
    return Material(
      color: c.surface,
      elevation: 8,
      shadowColor: Colors.black87,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22), side: BorderSide(color: c.line)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/pothole/${cluster.id}'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(spacing: 14, children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: tone.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(16)),
              child: Icon(cluster.type.startsWith('manhole') ? Icons.circle_outlined : (cluster.type.startsWith('bump') ? Icons.show_chart_rounded : Icons.trip_origin_rounded), color: tone, size: 28),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
                Text('$title · $dist', style: HpText.s(c.text, 17, FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                Row(spacing: 10, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(color: tone.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(999)),
                    child: Row(mainAxisSize: MainAxisSize.min, spacing: 5, children: [
                      Container(width: 7, height: 7, decoration: BoxDecoration(color: tone, shape: BoxShape.circle)),
                      Text(_levelName(l, cluster.level ?? 'light').replaceAll(RegExp(r'\s*яма$'), ''), style: HpText.s(tone, 12.5, FontWeight.w600)),
                    ]),
                  ),
                  Flexible(child: Text(l.driversCount(cluster.devices), style: HpText.s(c.muted, 13, FontWeight.w400), maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: c.muted),
          ]),
        ),
      ),
    );
  }
}

class _SearchSheet extends ConsumerStatefulWidget {
  const _SearchSheet();
  @override
  ConsumerState<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends ConsumerState<_SearchSheet> {
  final text = TextEditingController();
  List<SearchHit>? hits;
  Timer? _t;
  bool failed = false;

  @override
  void dispose() {
    _t?.cancel();
    text.dispose();
    super.dispose();
  }

  void _changed(String q) {
    _t?.cancel();
    if (q.trim().length < 2) {
      setState(() => hits = null);
      return;
    }
    _t = Timer(const Duration(milliseconds: 350), () async {
      try {
        final r = await ref.read(apiProvider).search(q.trim());
        if (mounted) {
          setState(() {
            hits = r;
            failed = false;
          });
        }
      } on ApiException {
        if (mounted) setState(() => failed = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
        TextField(
          controller: text,
          autofocus: true,
          onChanged: _changed,
          style: HpText.s(c.text, 16, FontWeight.w500),
          decoration: InputDecoration(hintText: l.searchHint, hintStyle: HpText.s(c.muted, 16, FontWeight.w400), prefixIcon: Icon(Icons.search_rounded, color: c.muted)),
        ),
        if (failed) Text(l.noConnection, style: HpText.s(c.craterText, 14, FontWeight.w500)),
        if (hits != null && hits!.isEmpty && !failed) Text(l.searchNoResults, style: HpText.s(c.muted, 14, FontWeight.w400)),
        if (hits != null)
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final h in hits!)
                ListTile(
                  leading: Icon(h.type == 'district' ? Icons.location_city_rounded : Icons.route_rounded, color: c.muted),
                  title: Text(h.name, style: HpText.s(c.text, 16, FontWeight.w500)),
                  onTap: () => Navigator.pop(context, h),
                ),
            ]),
          ),
      ]),
    );
  }
}

// ───────────────────────── Моя карта (мои поездки) ─────────────────────────
class MyMapScreen extends ConsumerStatefulWidget {
  const MyMapScreen({super.key});
  @override
  ConsumerState<MyMapScreen> createState() => _MyMapScreenState();
}

class _MyMapScreenState extends ConsumerState<MyMapScreen> {
  final ctl = RoadMapController();
  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    final trips = ref.watch(tripsProvider);
    final snap = ref.watch(recorderSnapshotProvider);
    if (snap.lat != null) ctl.setMe(snap.lat, snap.lon, snap.heading);
    return HpPage(
      child: Column(children: [
        SizedBox(height: 330, width: double.infinity, child: RoadMapView(controller: ctl, onClusterTap: (cl) => context.push('/pothole/${cl.id}'))),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Text(l.recentTrips, style: HpText.s(c.text, 18, FontWeight.w600)),
            const SizedBox(height: 12),
            if (trips.isEmpty) Text(l.tripsEmpty, style: HpText.s(c.muted, 14, FontWeight.w400)),
            for (final t in trips)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: HpListItem(tone: t.status == 'sent' ? Tone.smooth : Tone.amber, title: fmtDate(t.startedAt), subtitle: '${l.kmValue(fmtKm(t.distanceKm))} · ${l.tripPotholes}: ${t.potholes}'),
              ),
          ]),
        ),
      ]),
    );
  }
}

// ───────────────────────── Карточка ямы ─────────────────────────
class PotholeScreen extends ConsumerWidget {
  const PotholeScreen({super.key, required this.id});
  final int id;

  Future<void> _report(BuildContext context, WidgetRef ref, String state) async {
    final l = AppLocalizations.of(context);
    final m = ScaffoldMessenger.of(context);
    try {
      final api = await authedApi(ref.read(engineProvider));
      await api.reportCluster(id, state);
      m.showSnackBar(SnackBar(content: Text(l.reportThanks)));
      ref.invalidate(clusterDetailProvider(id));
    } on ApiException catch (e) {
      m.showSnackBar(SnackBar(content: Text(e.status == 429 ? l.reportAlready : l.noConnection)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    final d = ref.watch(clusterDetailProvider(id));
    return HpPage(
      child: d.when(
        loading: _loading,
        error: (_, __) => Padding(padding: const EdgeInsets.all(20), child: _Error(onRetry: () => ref.invalidate(clusterDetailProvider(id)))),
        data: (x) {
          final fixed = x.status == 'fixed';
          final statusText = fixed ? l.potholeFixed : (x.status == 'complaint' ? l.statusComplaintFiled : l.statusOpen);
          final statusColor = fixed ? c.smoothText : c.craterText;
          return HpFill(top: 20, bottom: [
            if (!fixed) HpButton(l.potholeStillThere, onPressed: () => _report(context, ref, 'present')),
            if (!fixed) HpButton(l.potholeFixed, kind: HpButtonKind.secondary, onPressed: () => _report(context, ref, 'fixed')),
            if (!fixed) HpButton(l.complaintTitle, kind: HpButtonKind.secondary, onPressed: () => context.push('/complaint/$id')),
          ], children: [
            SizedBox(height: 160, child: _MiniMap(lat: x.lat, lon: x.lon)),
            Text(x.street ?? '${x.lat.toStringAsFixed(5)}, ${x.lon.toStringAsFixed(5)}', style: HpText.s(c.text, 28, FontWeight.w700, ls: -0.42)),
            HpSub([_daysAgo(l, x.firstSeen), if (x.district != null) x.district!].join(' · ')),
            Wrap(spacing: 8, runSpacing: 8, children: [
              HpChip(_levelName(l, x.level.isEmpty ? 'light' : x.level), x.level == 'deep' || x.level == 'danger' ? Tone.major : Tone.minor),
              HpChip(l.driversCount(x.devices), Tone.smooth),
            ]),
            HpDetails([
              (l.confirmedLabel, l.driversN(x.devices), null),
              (l.statusLabel, statusText, statusColor),
              (l.complaintsFiled, '${x.complaints}', null),
              if (x.safeSpeed != null) (l.warnSlowDown, '${x.safeSpeed} ${l.kmh}', null),
            ]),
          ]);
        },
      ),
    );
  }
}

class _MiniMap extends StatefulWidget {
  const _MiniMap({required this.lat, required this.lon});
  final double lat, lon;
  @override
  State<_MiniMap> createState() => _MiniMapState();
}

class _MiniMapState extends State<_MiniMap> {
  late final ctl = RoadMapController()..moveTo(widget.lat, widget.lon, mpp: 1.2);
  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(borderRadius: BorderRadius.circular(24), child: RoadMapView(controller: ctl));
}

// ───────────────────────── Рейтинг улиц ─────────────────────────
class StreetsScreen extends ConsumerStatefulWidget {
  const StreetsScreen({super.key});
  @override
  ConsumerState<StreetsScreen> createState() => _StreetsScreenState();
}

class _StreetsScreenState extends ConsumerState<StreetsScreen> {
  int seg = 0;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    final rows = <Widget>[];
    if (seg == 0) {
      final r = ref.watch(streetsProvider((scope: 'city', district: null)));
      r.when(
        loading: () => rows.add(_loading()),
        error: (_, __) => rows.add(_Error(onRetry: () => ref.invalidate(streetsProvider))),
        data: (list) {
          if (list.isEmpty) rows.add(Text(l.streetsEmpty, style: HpText.s(c.muted, 14, FontWeight.w400)));
          final mx = list.fold<double>(1, (a, s) => s.perKm > a ? s.perKm : a);
          for (final s in list) {
            final hot = s.perKm >= mx * 0.7;
            rows.add(HpCard(
              child: Column(spacing: 8, children: [
                Row(spacing: 12, children: [
                  Text('${s.rank}', style: HpText.s(c.muted, 18, FontWeight.w700)),
                  Expanded(child: Text(s.name, style: HpText.s(c.text, 16, FontWeight.w600), overflow: TextOverflow.ellipsis)),
                  Text(fmtKm(s.perKm), style: HpText.s(hot ? c.craterText : c.warnText, 16, FontWeight.w700)),
                ]),
                HpProgress(s.perKm / mx, hot ? c.crater : c.warn),
              ]),
            ));
          }
        },
      );
    } else {
      final r = ref.watch(districtsProvider);
      r.when(
        loading: () => rows.add(_loading()),
        error: (_, __) => rows.add(_Error(onRetry: () => ref.invalidate(districtsProvider))),
        data: (rep) {
          if (rep.districts.isEmpty) rows.add(Text(l.streetsEmpty, style: HpText.s(c.muted, 14, FontWeight.w400)));
          for (final d in rep.districts) {
            rows.add(_ScoreCard(name: d.name, score: d.score));
          }
        },
      );
    }
    return HpBody(children: [
      HpTitle(l.streetsTitle),
      HpSub(l.streetsSub),
      HpSegmented(labels: [l.segCity, l.segDistrict], index: seg, onChanged: (i) => setState(() => seg = i)),
      ...rows,
    ]);
  }
}

Color _scoreColor(HpColors c, num v) => v >= 70 ? c.smoothText : v >= 60 ? c.amberText : v >= 45 ? c.warnText : c.craterText;
Color _scoreFill(HpColors c, num v) => v >= 70 ? c.smooth : v >= 60 ? c.amber : v >= 45 ? c.warn : c.crater;

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.name, required this.score});
  final String name;
  final double score;
  @override
  Widget build(BuildContext context) {
    final c = context.hp;
    return HpCard(
      child: Column(spacing: 8, children: [
        Row(children: [
          Expanded(child: Text(name, style: HpText.s(c.text, 15, FontWeight.w600))),
          Text(score.round().toString(), style: HpText.s(_scoreColor(c, score), 16, FontWeight.w700)),
        ]),
        HpProgress(score / 100, _scoreFill(c, score)),
      ]),
    );
  }
}

// ───────────────────────── Дашборд города ─────────────────────────
class CityDashboardScreen extends ConsumerWidget {
  const CityDashboardScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    final r = ref.watch(districtsProvider);
    return HpPage(
      child: HpBody(children: [
        const HpTitle('Ташкент'),
        HpSub(l.cityQuality('30 ${l.daysUnit}')),
        r.when(
          loading: _loading,
          error: (_, __) => _Error(onRetry: () => ref.invalidate(districtsProvider)),
          data: (rep) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
            HpCard(
              padding: 24,
              radius: 28,
              child: rep.cityScore == null
                  ? Text(l.cityScoreEmpty, style: HpText.s(c.muted, 15, FontWeight.w500))
                  : Row(crossAxisAlignment: CrossAxisAlignment.end, spacing: 8, children: [
                      Text('${rep.cityScore!.round()}', style: HpText.s(_scoreColor(c, rep.cityScore!), 72, FontWeight.w700, ls: -2.88, h: 1.1)),
                      Padding(padding: const EdgeInsets.only(bottom: 14), child: Text('/ 100', style: HpText.s(c.muted, 20, FontWeight.w500))),
                    ]),
            ),
            for (final d in rep.districts) _ScoreCard(name: d.name, score: d.score),
            if (rep.districts.isEmpty) Text(l.streetsEmpty, style: HpText.s(c.muted, 14, FontWeight.w400)),
          ]),
        ),
      ]),
    );
  }
}

// ───────────────────────── Отчёт недели ─────────────────────────
class WeeklyReportScreen extends ConsumerWidget {
  const WeeklyReportScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    final r = ref.watch(weeklyProvider);
    Widget box(int v, String t) => HpCard(
          padding: 20,
          child: Column(spacing: 2, children: [
            Text('$v', style: HpText.s(c.text, 28, FontWeight.w700)),
            Text(t, style: HpText.s(c.muted, 12, FontWeight.w500)),
          ]),
        );
    return HpPage(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: r.when(
            loading: _loading,
            error: (_, __) => _Error(onRetry: () => ref.invalidate(weeklyProvider)),
            data: (w) => Column(mainAxisSize: MainAxisSize.min, spacing: 20, children: [
              const HpSvg('logo80', size: 80),
              Text(l.weeklyReport.toUpperCase(), style: HpText.s(c.amberText, 14, FontWeight.w600, ls: 1.68)),
              FittedBox(fit: BoxFit.scaleDown, child: Text(l.weeklyFixedTitle(w.fixed), style: HpText.s(c.text, 72, FontWeight.w700, ls: -2.88))),
              SizedBox(width: 300, child: Text(l.weeklyFixedSub(w.fixed), textAlign: TextAlign.center, style: HpText.s(c.muted, 18, FontWeight.w400, h: 26 / 18))),
              Row(mainAxisSize: MainAxisSize.min, spacing: 10, children: [box(w.found, l.weeklyFound), box(w.complaints, l.weeklyComplaints)]),
              Text('Holescope · ${l.tagline}', textAlign: TextAlign.center, style: HpText.s(c.muted, 13, FontWeight.w500)),
            ]),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Жалоба ─────────────────────────
class _DraftArgs {
  const _DraftArgs(this.clusterId);
  final int clusterId;
  @override
  bool operator ==(Object o) => o is _DraftArgs && o.clusterId == clusterId;
  @override
  int get hashCode => clusterId;
}

final _draftProvider = FutureProvider.autoDispose.family<ComplaintDto, _DraftArgs>((ref, a) async => (await authedApi(ref.read(engineProvider))).createComplaint(a.clusterId));

class ComplaintScreen extends ConsumerWidget {
  const ComplaintScreen({super.key, required this.clusterId});
  final int clusterId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    final args = _DraftArgs(clusterId);
    final draft = ref.watch(_draftProvider(args));
    final detail = ref.watch(clusterDetailProvider(clusterId)).value;
    return HpPage(
      child: HpFill(top: 20, bottom: [
        HpButton(l.complaintSend, onPressed: draft.value == null
            ? null
            : () async {
                final m = ScaffoldMessenger.of(context);
                final router = GoRouter.of(context);
                try {
                  final sent = await (await authedApi(ref.read(engineProvider))).sendComplaint(draft.value!.id);
                  router.pushReplacement('/complaint/status/${sent.id}');
                } on ApiException {
                  m.showSnackBar(SnackBar(content: Text(l.noConnection)));
                }
              }),
      ], children: [
        const SizedBox(height: 4),
        HpTitle(l.complaintTitle),
        HpSub(l.complaintSub),
        if (detail != null)
          HpListItem(tone: detail.level == 'deep' || detail.level == 'danger' ? Tone.major : Tone.minor, title: detail.street ?? '${detail.lat.toStringAsFixed(4)}, ${detail.lon.toStringAsFixed(4)}', subtitle: '${_levelName(l, detail.level.isEmpty ? 'light' : detail.level)} · ${l.driversCount(detail.devices)}'),
        // TODO: список ведомств — из справочника complaint_channels (сервер); сейчас канал по умолчанию Xalq Nazorati.
        const Wrap(spacing: 8, runSpacing: 8, children: [HpChip('Xalq Nazorati', Tone.smooth)]),
        draft.when(
          loading: () => HpCard(padding: 18, child: Text(l.complaintTextPlaceholder, style: HpText.s(c.muted, 14, FontWeight.w400))),
          error: (_, __) => _Error(onRetry: () => ref.invalidate(_draftProvider(args))),
          data: (d) => HpCard(
            padding: 18,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 8, children: [
              Text(l.draft.toUpperCase(), style: HpText.s(c.amberText, 12, FontWeight.w600, ls: 1.44)),
              Text(d.text, style: HpText.s(c.text, 14, FontWeight.w400, h: 20 / 14)),
            ]),
          ),
        ),
        HpDetails([(l.photo, l.optional, null), (l.anonymous, l.yes, null)]),
      ]),
    );
  }
}

class ComplaintStatusScreen extends ConsumerWidget {
  const ComplaintStatusScreen({super.key, required this.id});
  final int id;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final c = context.hp;
    final r = ref.watch(complaintProvider(id));
    Widget step(Color dot, String t, String s, {bool last = false, bool todo = false}) => IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [
            SizedBox(
              width: 20,
              child: Column(children: [
                Container(width: 20, height: 20, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                if (!last) Expanded(child: Container(width: 2, color: c.line)),
              ]),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                  Text(t, style: HpText.s(todo ? c.muted : c.text, 18, FontWeight.w600)),
                  Text(s, style: HpText.s(c.muted, 14, FontWeight.w400)),
                ]),
              ),
            ),
          ]),
        );
    return HpPage(
      child: HpFill(bottom: [HpButton(l.shareChain, kind: HpButtonKind.secondary, onPressed: () {})], children: [
        const SizedBox(height: 4),
        HpTitle(l.statusChainTitle),
        r.when(
          loading: _loading,
          error: (_, __) => _Error(onRetry: () => ref.invalidate(complaintProvider(id))),
          data: (d) {
            final s = {for (final x in d.steps) x['step'] as String: x};
            final found = s['found']!, filed = s['filed']!, review = s['review']!, fixed = s['fixed']!;
            final foundAt = DateTime.tryParse(found['at'] as String? ?? '');
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              step(c.smooth, l.stepFound, l.stepFoundSub((found['drivers'] as num?)?.toInt() ?? 0, foundAt == null ? '' : _daysAgo(l, foundAt))),
              step(filed['done'] == true ? c.smooth : c.muted, l.stepFiled,
                  filed['done'] != true ? l.stepFiledNone : ((filed['number'] as String?)?.isNotEmpty == true ? l.stepFiledVia('Xalq Nazorati', filed['number'] as String) : l.stepFiledPending('Xalq Nazorati')), todo: filed['done'] != true),
              step(review['done'] == true ? c.amber : c.muted, l.stepReview, l.stepReviewWait, todo: review['done'] != true),
              step(fixed['done'] == true ? c.smooth : c.muted, l.stepFixed, fixed['done'] == true ? l.potholeFixed : l.stepFixedWait, last: true, todo: fixed['done'] != true),
            ]);
          },
        ),
      ]),
    );
  }
}
