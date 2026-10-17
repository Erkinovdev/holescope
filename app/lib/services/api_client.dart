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
}
