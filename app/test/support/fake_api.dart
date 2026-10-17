import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:holescope/services/api_client.dart';

/// Подменяет сеть: отвечает как сервер (форматы совпадают с backend/api).
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter({this.fail = false});
  final bool fail;
  final calls = <String>[];

  static const cluster = {
    'id': 1, 'lat': 41.3270, 'lon': 69.2284, 'heading': 90.0, 'type': 'pothole', 'level': 'deep', 'status': 'confirmed', 'passes': 7, 'devices': 7,
    'confidence': 0.9, 'safe_speed': 30, 'first_seen': '2026-10-14T10:00:00+00:00', 'last_hit': '2026-10-16T10:00:00+00:00', 'fixed_at': null, 'complaints': 0,
    'street': 'ул. Навои', 'road': 'A001', 'segment': 'A001-0012', 'district': 'Юнусабадский район',
  };

  Map<String, dynamic> _complaint(String status) => {
        'id': 1, 'cluster_id': 1, 'channel': 'xalq_nazorati', 'status': status, 'anonymous': true, 'number': status == 'draft' ? '' : '48217', 'created': '2026-10-17T10:00:00+00:00',
        'text': 'На ул. Навои, Юнусабадский район обнаружена глубокая яма. Подтверждена 7 водителями.',
        'steps': [
          {'step': 'found', 'done': true, 'at': '2026-10-14T10:00:00+00:00', 'drivers': 7},
          {'step': 'filed', 'done': status != 'draft', 'at': null, 'number': status == 'draft' ? '' : '48217', 'channel': 'xalq_nazorati'},
          {'step': 'review', 'done': false, 'due': null},
          {'step': 'fixed', 'done': false, 'at': null},
        ],
      };

  Object? _route(RequestOptions o) {
    final p = o.path;
    if (p.endsWith('/devices/register')) return {'token': 'test-token', 'nickname': 'Тихий Сокол #4821'};
    if (p.endsWith('/map/segments')) {
      return {'fields': [], 'limit': 5000, 'segments': [
        [1, 41.3270, 69.2270, 41.3270, 69.2284, 'A', 'A', 1],
        [2, 41.3270, 69.2284, 41.3270, 69.2298, 'D', 'A', 1],
        [3, 41.3270, 69.2298, 41.3270, 69.2312, '', 'B', 1],
        [4, 41.3280, 69.2270, 41.3280, 69.2312, '', 'C', -1],
      ]};
    }
    if (p.endsWith('/map/clusters')) {
      return {'clusters': [{'id': 1, 'lat': 41.3270, 'lon': 69.2284, 'heading': 90.0, 'type': 'pothole', 'level': 'deep', 'status': 'confirmed', 'passes': 7, 'devices': 7, 'confidence': 0.9, 'safe_speed': 30}]};
    }
    if (RegExp(r'/clusters/\d+$').hasMatch(p)) return cluster;
    if (p.contains('/clusters/') && p.endsWith('/report')) return {'ok': true, 'status': 'confirmed', 'fixed': false};
    if (p.endsWith('/rankings/streets')) {
      return {'streets': [
        {'rank': 1, 'road': 'A003', 'name': 'ул. Бабура', 'covered_km': 3.2, 'potholes': 45, 'per_km': 14.2},
        {'rank': 2, 'road': 'R01', 'name': 'Кичик халка йули', 'covered_km': 5.1, 'potholes': 60, 'per_km': 11.8},
        {'rank': 3, 'road': 'B010', 'name': 'ул. Беруни', 'covered_km': 2.0, 'potholes': 19, 'per_km': 9.4},
      ]};
    }
    if (p.endsWith('/rankings/districts')) {
      return {'city_score': 62.0, 'districts': [
        {'code': 'UZ-TSH-YUN', 'name': 'Юнусабадский район', 'score': 78.0, 'segments': 900},
        {'code': 'UZ-TSH-SER', 'name': 'Сергелийский район', 'score': 38.0, 'segments': 700},
      ]};
    }
    if (p.endsWith('/reports/weekly')) return {'found': 128, 'fixed': 31, 'complaints': 47, 'drivers': 12, 'km': 840.5};
    if (p.endsWith('/complaints') && o.method == 'POST') return _complaint('draft');
    if (p.endsWith('/send')) return _complaint('filed');
    if (RegExp(r'/complaints/\d+$').hasMatch(p)) return _complaint('filed');
    if (p.endsWith('/me/stats')) return {'nickname': 'Тихий Сокол #4821', 'found': 128, 'confirmed': 342, 'km': 1460.0, 'trips': 30, 'trust': 0.8};
    if (p.endsWith('/search')) return {'results': [{'type': 'road', 'name': 'ул. Бабура', 'lat': 41.3, 'lon': 69.25}, {'type': 'district', 'name': 'Юнусабадский район', 'lat': 41.36, 'lon': 69.28}]};
    if (p.endsWith('/questions/next')) return {'questions': []};
    return {};
  }

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls.add('${options.method} ${options.path}');
    if (fail) {
      throw DioException(requestOptions: options, type: DioExceptionType.connectionError, message: 'offline');
    }
    final body = jsonEncode(_route(options));
    return ResponseBody.fromString(body, 200, headers: {Headers.contentTypeHeader: ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

ApiClient fakeApi({bool fail = false, FakeAdapter? adapter}) {
  final dio = Dio(BaseOptions(baseUrl: 'http://fake', contentType: 'application/json'))..httpClientAdapter = adapter ?? FakeAdapter(fail: fail);
  return ApiClient('http://fake', dio: dio);
}
