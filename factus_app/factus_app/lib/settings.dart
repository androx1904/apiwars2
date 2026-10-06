import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Configuración de la app (credenciales y URLs). Se guarda cifrada en el
/// almacén seguro del sistema (Windows Credential Locker / DPAPI).
class AppSettings {
  const AppSettings({
    required this.production,
    required this.factusBaseUrl,
    required this.factusClientId,
    required this.factusClientSecret,
    required this.factusUsername,
    required this.factusPassword,
    required this.payBaseUrl,
    required this.payEmail,
    required this.payPassword,
  });

  static const sandboxFactus = 'https://api-sandbox.factus.com.co';
  static const productionFactus = 'https://api.factus.com.co';
  static const sandboxPay = 'https://pay-api-sandbox.factus.com.co';
  static const productionPay = 'https://pay-api.factus.com.co';

  final bool production;
  final String factusBaseUrl;
  final String factusClientId;
  final String factusClientSecret;
  final String factusUsername;
  final String factusPassword;
  final String payBaseUrl;
  final String payEmail;
  final String payPassword;

  factory AppSettings.defaults() => const AppSettings(
        production: false,
        factusBaseUrl: sandboxFactus,
        factusClientId: '',
        factusClientSecret: '',
        factusUsername: '',
        factusPassword: '',
        payBaseUrl: sandboxPay,
        payEmail: '',
        payPassword: '',
      );

  bool get factusConfigured =>
      factusClientId.isNotEmpty &&
      factusClientSecret.isNotEmpty &&
      factusUsername.isNotEmpty &&
      factusPassword.isNotEmpty;

  bool get payConfigured => payEmail.isNotEmpty && payPassword.isNotEmpty;

  AppSettings copyWith({
    bool? production,
    String? factusBaseUrl,
    String? factusClientId,
    String? factusClientSecret,
    String? factusUsername,
    String? factusPassword,
    String? payBaseUrl,
    String? payEmail,
    String? payPassword,
  }) {
    return AppSettings(
      production: production ?? this.production,
      factusBaseUrl: factusBaseUrl ?? this.factusBaseUrl,
      factusClientId: factusClientId ?? this.factusClientId,
      factusClientSecret: factusClientSecret ?? this.factusClientSecret,
      factusUsername: factusUsername ?? this.factusUsername,
      factusPassword: factusPassword ?? this.factusPassword,
      payBaseUrl: payBaseUrl ?? this.payBaseUrl,
      payEmail: payEmail ?? this.payEmail,
      payPassword: payPassword ?? this.payPassword,
    );
  }

  Map<String, dynamic> toJson() => {
        'production': production,
        'factusBaseUrl': factusBaseUrl,
        'factusClientId': factusClientId,
        'factusClientSecret': factusClientSecret,
        'factusUsername': factusUsername,
        'factusPassword': factusPassword,
        'payBaseUrl': payBaseUrl,
        'payEmail': payEmail,
        'payPassword': payPassword,
      };

  factory AppSettings.fromJson(Map<String, dynamic> j) {
    final d = AppSettings.defaults();
    String s(String key, String fallback) {
      final v = j[key];
      return v is String ? v : fallback;
    }

    return AppSettings(
      production: j['production'] == true,
      factusBaseUrl: s('factusBaseUrl', d.factusBaseUrl),
      factusClientId: s('factusClientId', ''),
      factusClientSecret: s('factusClientSecret', ''),
      factusUsername: s('factusUsername', ''),
      factusPassword: s('factusPassword', ''),
      payBaseUrl: s('payBaseUrl', d.payBaseUrl),
      payEmail: s('payEmail', ''),
      payPassword: s('payPassword', ''),
    );
  }
}

class SettingsStore {
  static const _kSettings = 'settings_v1';
  static const _kPayToken = 'pay_token_v1';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  Future<AppSettings> load() async {
    try {
      final raw = await _storage.read(key: _kSettings);
      if (raw == null) return AppSettings.defaults();
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return AppSettings.defaults();
    }
  }

  Future<void> save(AppSettings s) =>
      _storage.write(key: _kSettings, value: jsonEncode(s.toJson()));

  /// El token de Factus Pay no expira y solo puede existir uno activo por
  /// usuario, por eso se persiste (evita revocar el token en cada arranque).
  Future<String?> readPayToken(String scope) async {
    try {
      final raw = await _storage.read(key: _kPayToken);
      if (raw == null) return null;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return m['scope'] == scope ? m['token'] as String? : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> writePayToken(String scope, String token) => _storage.write(
        key: _kPayToken,
        value: jsonEncode({'scope': scope, 'token': token}),
      );

  Future<void> clearPayToken() => _storage.delete(key: _kPayToken);
}
