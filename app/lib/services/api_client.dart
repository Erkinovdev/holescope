import 'dart:io';

import 'package:dio/dio.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.status, this.retryable = true});
  final String message;
  final int? status;
  final bool retryable; // false: 4xx (кроме 408/429) — повтор бессмыслен
  @override
  String toString() => 'ApiException($status): $message';
}

class AheadWarning {
  AheadWarning({required this.id, required this.distanceM, required this.side, required this.level, required this.type, required this.confidence, required this.safeSpeed});
  final int id, distanceM;
  final String side, type;
  final String? level;
  final double confidence;
  final int? safeSpeed;

  factory AheadWarning.fromJson(Map<String, dynamic> j) => AheadWarning(
        id: j['id'] as int,
        distanceM: (j['distance_m'] as num).round(),
        side: j['side'] as String,
        level: j['level'] as String?,
        type: j['type'] as String,
        confidence: (j['confidence'] as num).toDouble(),
        safeSpeed: (j['safe_speed'] as num?)?.toInt(),
      );
}

class ClusterDto {
  ClusterDto({required this.id, required this.lat, required this.lon, required this.type, required this.level, required this.status, required this.passes, required this.devices, required this.confidence, required this.safeSpeed, this.heading});
  final int id, passes, devices;
  final double lat, lon, confidence;
  final double? heading;
  final String type, status;
  final String? level;
  final int? safeSpeed;

  factory ClusterDto.fromJson(Map<String, dynamic> j) => ClusterDto(
        id: j['id'] as int,
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
        heading: (j['heading'] as num?)?.toDouble(),
        type: j['type'] as String,
        level: (j['level'] as String?)?.isEmpty == true ? null : j['level'] as String?,
        status: j['status'] as String,
        passes: j['passes'] as int,
        devices: j['devices'] as int,
        confidence: (j['confidence'] as num).toDouble(),
        safeSpeed: (j['safe_speed'] as num?)?.toInt(),
      );
}

class QuestionDto {
  QuestionDto({required this.id, required this.lat, required this.lon, required this.speedKmh, required this.wave, required this.guess, required this.options});
  final int id;
  final double lat, lon, speedKmh;
  final List<double> wave;
  final String guess;
  final List<String> options;

  factory QuestionDto.fromJson(Map<String, dynamic> j) => QuestionDto(
        id: j['id'] as int,
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
        speedKmh: (j['speed_kmh'] as num).toDouble(),
        wave: [for (final x in (j['wave'] as List? ?? const [])) (x as num).toDouble()],
        guess: j['guess'] as String? ?? 'pothole',
        options: [for (final o in (j['options'] as List)) o as String],
      );
}

class SegmentDto {
  const SegmentDto(this.id, this.latA, this.lonA, this.latB, this.lonB, this.cls, this.roadClass, this.direction);
  final int id, direction;
  final double latA, lonA, latB, lonB;
  final String cls, roadClass; // cls: A..E или пусто

  factory SegmentDto.fromRow(List<dynamic> r) => SegmentDto(r[0] as int, (r[1] as num).toDouble(), (r[2] as num).toDouble(), (r[3] as num).toDouble(), (r[4] as num).toDouble(), r[5] as String, r[6] as String, r[7] as int);
}

class StreetRank {
  const StreetRank(this.rank, this.road, this.name, this.coveredKm, this.potholes, this.perKm);
  final int rank, potholes;
  final String road, name;
  final double coveredKm, perKm;
}

class DistrictScore {
  const DistrictScore(this.code, this.name, this.score, this.segments);
  final String code, name;
  final double score;
  final int segments;
}

class DistrictsReport {
  const DistrictsReport(this.cityScore, this.districts);
  final double? cityScore;
  final List<DistrictScore> districts;
}

class WeeklyReport {
  const WeeklyReport(this.found, this.fixed, this.complaints, this.drivers, this.km);
  final int found, fixed, complaints, drivers;
  final double km;
}

class ClusterDetail {
  const ClusterDetail({required this.id, required this.lat, required this.lon, required this.level, required this.status, required this.devices, required this.passes, required this.firstSeen, required this.complaints, this.street, this.district, this.segment, this.safeSpeed});
  final int id, devices, passes, complaints;
  final double lat, lon;
  final String level, status;
  final DateTime firstSeen;
  final String? street, district, segment;
  final int? safeSpeed;

  factory ClusterDetail.fromJson(Map<String, dynamic> j) => ClusterDetail(
        id: j['id'] as int,
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
        level: (j['level'] as String?) ?? '',
        status: j['status'] as String,
        devices: j['devices'] as int,
        passes: j['passes'] as int,
        firstSeen: DateTime.parse(j['first_seen'] as String),
        complaints: j['complaints'] as int,
        street: j['street'] as String?,
        district: j['district'] as String?,
        segment: j['segment'] as String?,
        safeSpeed: (j['safe_speed'] as num?)?.toInt(),
      );
}

class ComplaintDto {
  const ComplaintDto({required this.id, required this.clusterId, required this.status, required this.text, required this.number, required this.steps});
  final int id, clusterId;
  final String status, text, number;
  final List<Map<String, dynamic>> steps;

  factory ComplaintDto.fromJson(Map<String, dynamic> j) => ComplaintDto(
        id: j['id'] as int,
        clusterId: j['cluster_id'] as int,
        status: j['status'] as String,
        text: j['text'] as String,
        number: (j['number'] as String?) ?? '',
        steps: [for (final s in j['steps'] as List) Map<String, dynamic>.from(s as Map)],
      );
}

class SearchHit {
  const SearchHit(this.type, this.name, this.lat, this.lon);
  final String type, name;
  final double lat, lon;
}

class MyStats {
  const MyStats(this.found, this.confirmed, this.km, this.trips);
  final int found, confirmed, trips;
  final double km;
}

/// HTTP-клиент API v1 (backend/api). Заголовок авторизации — X-Device-Token (анонимный токен устройства).
class ApiClient {
  ApiClient(String baseUrl, {this.token, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(baseUrl: baseUrl, connectTimeout: const Duration(seconds: 10), sendTimeout: const Duration(seconds: 60), receiveTimeout: const Duration(seconds: 30), contentType: 'application/json'));

  final Dio _dio;
  String? token;

  Options get _auth => Options(headers: {if (token != null) 'X-Device-Token': token});

  Future<T> _run<T>(Future<Response<dynamic>> Function() call, T Function(dynamic data) parse) async {
    try {
      final r = await call();
      return parse(r.data);
    } on DioException catch (e) {
      final s = e.response?.statusCode;
      final retry = s == null || s >= 500 || s == 408 || s == 429;
      throw ApiException(e.message ?? e.type.name, status: s, retryable: retry);
    }
  }

  Future<({String token, String nickname})> register({String platform = '', String phoneModel = '', String appVersion = '', String lang = 'ru', String role = 'driver'}) =>
      _run(
        () => _dio.post('/api/v1/devices/register', data: {'platform': platform, 'phone_model': phoneModel, 'app_version': appVersion, 'lang': lang, 'role': role}),
        (d) => (token: d['token'] as String, nickname: d['nickname'] as String),
      );

  Future<void> sendMarks(List<Map<String, dynamic>> marks) => _run(() => _dio.post('/api/v1/marks', data: {'marks': marks}, options: _auth), (_) {});

  /// Распознавание речи на сервере: короткий WAV → текст.
  Future<String> transcribe(File wav, String lang) => _run(
        () async => _dio.post('/api/v1/voice/transcribe',
            data: FormData.fromMap({'file': await MultipartFile.fromFile(wav.path, filename: 'speech.wav'), 'lang': lang}),
            options: Options(headers: {if (token != null) 'X-Device-Token': token}, sendTimeout: const Duration(seconds: 20), receiveTimeout: const Duration(seconds: 25))),
        (d) => (d['text'] as String?) ?? '',
      );

  /// Варианты ответа «что это было?» с названиями ru/uz и группами.
  Future<Map<String, dynamic>> taxonomy() => _run(() => _dio.get('/api/v1/taxonomy'), (d) => Map<String, dynamic>.from(d as Map));

  Future<Map<String, dynamic>> algoParams() => _run(() => _dio.get('/api/v1/algo/params'), (d) => Map<String, dynamic>.from(d as Map));

  Future<void> patchVehicle(Map<String, dynamic> body) => _run(() => _dio.patch('/api/v1/me/vehicle', data: body, options: _auth), (_) {});

  Future<({int tripId, int events, int questions})> uploadTrip(Map<String, dynamic> payload) => _run(
        () => _dio.post('/api/v1/trips', data: payload, options: _auth),
        (d) => (tripId: d['trip_id'] as int, events: d['events'] as int, questions: d['questions'] as int),
      );

  /// Сырой CSV (только исследовательские устройства), gzip.
  Future<int> uploadRaw(File file, String filename) => _run(
        () async => _dio.post('/api/v1/trips/raw', data: FormData.fromMap({'file': await MultipartFile.fromFile(file.path, filename: filename)}), options: _auth),
        (d) => d['raw_id'] as int,
      );

  Future<List<QuestionDto>> questionsNext() => _run(
        () => _dio.get('/api/v1/questions/next', options: _auth),
        (d) => [for (final q in d['questions'] as List) QuestionDto.fromJson(q as Map<String, dynamic>)],
      );

  Future<void> answerQuestion(int id, String answer) => _run(() => _dio.post('/api/v1/questions/$id/answer', data: {'answer': answer}, options: _auth), (_) {});

  Future<List<ClusterDto>> mapClusters({required double minLat, required double minLon, required double maxLat, required double maxLon}) => _run(
        () => _dio.get('/api/v1/map/clusters', queryParameters: {'bbox': '$minLat,$minLon,$maxLat,$maxLon'}),
        (d) => [for (final c in d['clusters'] as List) ClusterDto.fromJson(c as Map<String, dynamic>)],
      );

  Future<List<AheadWarning>> ahead({required double lat, required double lon, required double heading, int dist = 300}) => _run(
        () => _dio.get('/api/v1/drive/ahead', queryParameters: {'lat': lat, 'lon': lon, 'heading': heading, 'dist': dist}),
        (d) => [for (final a in d['ahead'] as List) AheadWarning.fromJson(a as Map<String, dynamic>)],
      );

  Future<List<SegmentDto>> mapSegments({required double minLat, required double minLon, required double maxLat, required double maxLon, bool scored = false, int limit = 4000}) => _run(
        () => _dio.get('/api/v1/map/segments', queryParameters: {'bbox': '$minLat,$minLon,$maxLat,$maxLon', 'scored': scored ? 1 : 0, 'limit': limit}),
        (d) => [for (final r in d['segments'] as List) SegmentDto.fromRow(r as List)],
      );

  /// Одна ячейка карты 0.01°: целые смещения от угла ячейки в миллионных долях градуса (компактно, кэшируется).
  /// [set]: major — только магистрали, main — плюс местные, all — все дороги.
  Future<List<SegmentDto>> mapCell(int i, int j, {String set = 'all', bool scored = false}) => _run(
        () => _dio.get('/api/v1/map/cell', queryParameters: {'i': i, 'j': j, 'set': set, if (scored) 'scored': 1}),
        (d) {
          final o = d['o'] as List;
          final la0 = (o[0] as num).toDouble(), lo0 = (o[1] as num).toDouble();
          const u = 1e-6;
          return [
            for (final r in d['s'] as List)
              SegmentDto((r as List)[0] as int, la0 + (r[1] as num) * u, lo0 + (r[2] as num) * u, la0 + (r[3] as num) * u, lo0 + (r[4] as num) * u, r[5] as String, r[6] as String, r[7] as int),
          ];
        },
      );

  Future<List<StreetRank>> rankingsStreets({String scope = 'city', String? district, int days = 30, int limit = 20}) => _run(
        () => _dio.get('/api/v1/rankings/streets', queryParameters: {'scope': scope, if (district != null) 'district': district, 'days': days, 'limit': limit}),
        (d) => [
          for (final r in d['streets'] as List)
            StreetRank(r['rank'] as int, r['road'] as String, r['name'] as String, (r['covered_km'] as num).toDouble(), r['potholes'] as int, (r['per_km'] as num).toDouble())
        ],
      );

  Future<DistrictsReport> rankingsDistricts({int days = 30}) => _run(
        () => _dio.get('/api/v1/rankings/districts', queryParameters: {'days': days}),
        (d) => DistrictsReport((d['city_score'] as num?)?.toDouble(), [
          for (final r in d['districts'] as List) DistrictScore(r['code'] as String, r['name'] as String, (r['score'] as num).toDouble(), r['segments'] as int)
        ]),
      );

  Future<WeeklyReport> weekly({int days = 7}) => _run(
        () => _dio.get('/api/v1/reports/weekly', queryParameters: {'days': days}),
        (d) => WeeklyReport(d['found'] as int, d['fixed'] as int, d['complaints'] as int, d['drivers'] as int, (d['km'] as num).toDouble()),
      );

  Future<ClusterDetail> cluster(int id) => _run(() => _dio.get('/api/v1/clusters/$id'), (d) => ClusterDetail.fromJson(d as Map<String, dynamic>));

  /// state: present | fixed
  Future<void> reportCluster(int id, String state) => _run(() => _dio.post('/api/v1/clusters/$id/report', data: {'state': state}, options: _auth), (_) {});

  Future<ComplaintDto> createComplaint(int clusterId) => _run(() => _dio.post('/api/v1/complaints', data: {'cluster_id': clusterId}, options: _auth), (d) => ComplaintDto.fromJson(d as Map<String, dynamic>));
  Future<ComplaintDto> sendComplaint(int id) => _run(() => _dio.post('/api/v1/complaints/$id/send', options: _auth), (d) => ComplaintDto.fromJson(d as Map<String, dynamic>));
  Future<ComplaintDto> complaint(int id) => _run(() => _dio.get('/api/v1/complaints/$id', options: _auth), (d) => ComplaintDto.fromJson(d as Map<String, dynamic>));

  Future<List<SearchHit>> search(String q) => _run(
        () => _dio.get('/api/v1/search', queryParameters: {'q': q}),
        (d) => [for (final r in d['results'] as List) SearchHit(r['type'] as String, r['name'] as String, (r['lat'] as num).toDouble(), (r['lon'] as num).toDouble())],
      );

  Future<MyStats> myStats() => _run(() => _dio.get('/api/v1/me/stats', options: _auth), (d) => MyStats(d['found'] as int, d['confirmed'] as int, (d['km'] as num).toDouble(), d['trips'] as int));
}
