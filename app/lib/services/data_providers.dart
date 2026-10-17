import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'engine.dart';
import 'providers.dart';

/// Данные с сервера для экранов. Ошибки сети пробрасываются как AsyncError — экраны показывают «нет связи».
typedef StreetsQuery = ({String scope, String? district});

final streetsProvider = FutureProvider.autoDispose.family<List<StreetRank>, StreetsQuery>((ref, q) => ref.watch(apiProvider).rankingsStreets(scope: q.scope, district: q.district));
final districtsProvider = FutureProvider.autoDispose<DistrictsReport>((ref) => ref.watch(apiProvider).rankingsDistricts());
final weeklyProvider = FutureProvider.autoDispose<WeeklyReport>((ref) => ref.watch(apiProvider).weekly());
final clusterDetailProvider = FutureProvider.autoDispose.family<ClusterDetail, int>((ref, id) => ref.watch(apiProvider).cluster(id));

/// Запросы с авторизацией устройства: сначала регистрация (один раз), токен — в защищённом хранилище.
Future<ApiClient> authedApi(RecorderEngine eng) async {
  await eng.auth.ensureRegistered(eng.api);
  return eng.api;
}

final myStatsProvider = FutureProvider.autoDispose<MyStats>((ref) async => (await authedApi(ref.read(engineProvider))).myStats());
final complaintProvider = FutureProvider.autoDispose.family<ComplaintDto, int>((ref, id) async => (await authedApi(ref.read(engineProvider))).complaint(id));
