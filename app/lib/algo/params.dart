/// Параметры алгоритма (порт backend/holescope_algo/params.py). Значения по умолчанию совпадают с Python.
class AlgoParams {
  const AlgoParams({
    this.gravAlpha = 0.015,
    this.smoothSamples = 2,
    this.floor = 2.0,
    this.kNoise = 4.0,
    this.minSpeedMs = 1.0,
    this.lowConfSpeedMs = 2.8,
    this.v0Ms = 11.1,
    this.speedAlpha = 0.8,
    this.mergeGapS = 1.0,
    this.wheelbaseM = 2.6,
    this.segLenM = 50.0,
    this.riBeta = 1.0,
    this.riBounds = const [0.03, 0.05, 0.08, 0.13],
    this.minSpeedRiMs = 3.0,
  });

  /// Параметры, которыми считает запись сейчас: по умолчанию встроенные, после синхронизации — с сервера (`/algo/params`).
  static AlgoParams current = const AlgoParams();

  /// Разбор ответа сервера. Неизвестные поля пропускаются, значения вне допустимых диапазонов (те же, что проверяет сервер) заменяются встроенными.
  factory AlgoParams.fromJson(Map<String, dynamic> j) {
    const d = AlgoParams();
    double pick(String k, double def, double lo, double hi) {
      final v = j[k];
      return v is num && v.isFinite && v >= lo && v <= hi ? v.toDouble() : def;
    }

    var bounds = d.riBounds;
    final b = j['ri_bounds'];
    if (b is List && b.length == 4 && b.every((x) => x is num && x.isFinite && x > 0)) {
      final l = b.map((x) => (x as num).toDouble()).toList();
      bool sorted = true;
      for (var i = 1; i < 4; i++) {
        if (l[i] < l[i - 1]) sorted = false;
      }
      if (sorted) bounds = l;
    }
    return AlgoParams(
      gravAlpha: pick('grav_alpha', d.gravAlpha, 0.001, 0.2),
      smoothSamples: pick('smooth_samples', d.smoothSamples.toDouble(), 1, 8).round(),
      floor: pick('floor', d.floor, 0.5, 10),
      kNoise: pick('k_noise', d.kNoise, 1, 10),
      minSpeedMs: pick('min_speed_ms', d.minSpeedMs, 0.2, 5),
      lowConfSpeedMs: pick('low_conf_speed_ms', d.lowConfSpeedMs, 0.5, 8),
      v0Ms: pick('v0_ms', d.v0Ms, 3, 20),
      speedAlpha: pick('speed_alpha', d.speedAlpha, 0, 2),
      mergeGapS: pick('merge_gap_s', d.mergeGapS, 0.2, 5),
      wheelbaseM: d.wheelbaseM,
      segLenM: pick('seg_len_m', d.segLenM, 10, 200),
      riBeta: pick('ri_beta', d.riBeta, 0, 2),
      riBounds: bounds,
      minSpeedRiMs: pick('min_speed_ri_ms', d.minSpeedRiMs, 0.5, 10),
    );
  }

  final double gravAlpha;
  final int smoothSamples;
  final double floor, kNoise, minSpeedMs, lowConfSpeedMs, v0Ms, speedAlpha, mergeGapS;
  final double wheelbaseM;
  final double segLenM, riBeta, minSpeedRiMs;
  final List<double> riBounds;

  AlgoParams copyWith({double? wheelbaseM, double? floor, double? kNoise}) => AlgoParams(
        gravAlpha: gravAlpha,
        smoothSamples: smoothSamples,
        floor: floor ?? this.floor,
        kNoise: kNoise ?? this.kNoise,
        minSpeedMs: minSpeedMs,
        lowConfSpeedMs: lowConfSpeedMs,
        v0Ms: v0Ms,
        speedAlpha: speedAlpha,
        mergeGapS: mergeGapS,
        wheelbaseM: wheelbaseM ?? this.wheelbaseM,
        segLenM: segLenM,
        riBeta: riBeta,
        riBounds: riBounds,
        minSpeedRiMs: minSpeedRiMs,
      );
}

const algoVersion = '2.0.0';
