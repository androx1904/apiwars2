import 'dart:async';

import 'package:dio/dio.dart';

import '../settings.dart';
import 'api_error.dart';
import 'http.dart';

/// Login de Factus Pay: POST /auth (sin prefijo /v1) con email y contraseña.
/// El token no expira y solo hay uno activo por usuario: se persiste y solo se
/// vuelve a pedir si la API responde 401.
class PayAuth implements TokenSource {
  PayAuth(this.s, this.store)
      : _plain = Dio(
          BaseOptions(
            baseUrl: s.payBaseUrl,
            connectTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(seconds: 30),
            headers: {'Accept': 'application/json'},
            contentType: Headers.jsonContentType,
          ),
        );

  final AppSettings s;
  final SettingsStore store;
  final Dio _plain;
  String? _token;
  Future<String>? _inflight;

  String get _scope => '${s.payBaseUrl}|${s.payEmail}';

  @override
  Future<String> getToken({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      _token ??= await store.readPayToken(_scope);
      final t = _token;
      if (t != null) return t;
    }
    return _inflight ??= _login().whenComplete(() => _inflight = null);
  }

  Future<String> _login() async {
    if (!s.payConfigured) {
      throw ApiError('Faltan las credenciales de Factus Pay. Ve a Configuración.');
    }
    try {
      final r = await _plain.post<dynamic>(
        '/auth',
        data: {'email': s.payEmail, 'password': s.payPassword},
      );
      final token = asMap(r.data)['token'] as String;
      _token = token;
      await store.writePayToken(_scope, token);
      return token;
    } catch (e) {
      final err = ApiError.from(e);
      if (err.status == 401) {
        throw ApiError(
          'Factus Pay rechazó el correo o la contraseña.',
          status: 401,
        );
      }
      throw err;
    }
  }
}

class PayCollection {
  PayCollection({
    required this.reference,
    required this.amount,
    required this.status,
    this.createdAt,
    this.qr,
  });

  final String reference;
  final double amount;

  /// started → ready → paid
  final String status;
  final String? createdAt;

  /// data:image/png;base64,... (null mientras se genera)
  final String? qr;

  bool get paid => status == 'paid';

  factory PayCollection.fromJson(Map<String, dynamic> m) => PayCollection(
        reference: '${m['reference_code']}',
        amount: (m['amount'] is num)
            ? (m['amount'] as num).toDouble()
            : double.tryParse('${m['amount']}') ?? 0,
        status: '${m['status']}',
        createdAt: m['created_at'] as String?,
        qr: m['qr'] as String?,
      );
}

class FactusPayApi {
  FactusPayApi(AppSettings s, SettingsStore store) : _auth = PayAuth(s, store) {
    dio = buildDio(s.payBaseUrl, _auth);
  }

  static const minAmount = 10000;
  static const maxAmount = 12000000;

  final PayAuth _auth;
  late final Dio dio;

  static bool amountInRange(num amount) =>
      amount >= minAmount && amount <= maxAmount;

  Future<void> testLogin() async {
    try {
      await _auth.getToken(forceRefresh: true);
    } catch (e) {
      throw ApiError.from(e);
    }
  }

  /// Idempotente por `reference_code`: si ya existe devuelve el existente.
  Future<PayCollection> createCollection(String reference, num amount) async {
    if (!amountInRange(amount)) {
      throw ApiError(
        'El monto del cobro debe estar entre \$10.000 y \$12.000.000 COP.',
      );
    }
    try {
      final r = await dio.post<dynamic>(
        '/v1/collections',
        data: {'reference_code': reference, 'amount': amount},
      );
      return PayCollection.fromJson(asMap(asMap(r.data)['data']));
    } catch (e) {
      throw ApiError.from(e);
    }
  }

  Future<PayCollection> getCollection(String reference) async {
    try {
      final r = await dio.get<dynamic>(
        '/v1/collections/${Uri.encodeComponent(reference)}',
      );
      return PayCollection.fromJson(asMap(asMap(r.data)['data']));
    } catch (e) {
      throw ApiError.from(e);
    }
  }

  Future<List<PayCollection>> listCollections({int page = 1}) async {
    try {
      final r = await dio.get<dynamic>(
        '/v1/collections',
        queryParameters: {'page': page},
      );
      final body = asMap(r.data);
      final d = body['data'];
      List rows = const [];
      if (d is List) {
        rows = d;
      } else if (d is Map && d['data'] is List) {
        rows = d['data'] as List;
      }
      return rows
          .whereType<Map>()
          .map((e) => PayCollection.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (e) {
      throw ApiError.from(e);
    }
  }
}
