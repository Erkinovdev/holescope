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
