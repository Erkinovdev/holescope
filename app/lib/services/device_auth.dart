import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';
import 'config.dart';

abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String token);
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? s]) : _s = s ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;
  static const _k = 'device_token';
  @override
  Future<String?> read() => _s.read(key: _k);
  @override
  Future<void> write(String token) => _s.write(key: _k, value: token);
}

class MemoryTokenStore implements TokenStore {
  String? _t;
  @override
  Future<String?> read() async => _t;
  @override
  Future<void> write(String token) async => _t = token;
}

/// Анонимная регистрация устройства: токен хранится в защищённом хранилище, без почты и номера.
class DeviceAuth {
  DeviceAuth(this.store);
  final TokenStore store;
  String? lastNickname; // ник, выданный сервером при регистрации

  Future<String> ensureRegistered(ApiClient api, {String platform = '', String phoneModel = '', String lang = 'ru', String role = 'driver'}) async {
    final t = await store.read();
    if (t != null && t.isNotEmpty) {
      api.token = t;
      return t;
    }
    final r = await api.register(platform: platform, phoneModel: phoneModel, appVersion: AppConfig.appVersion, lang: lang, role: role);
    await store.write(r.token);
    lastNickname = r.nickname;
    api.token = r.token;
    return r.token;
  }
}
