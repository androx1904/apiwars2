import 'dart:async';

import 'package:dio/dio.dart';

import '../settings.dart';
import 'api_error.dart';
import 'http.dart';

/// OAuth2 de Factus (grant password + refresh_token).
/// Un solo request de token en vuelo aunque lleguen llamadas en paralelo.
class FactusAuth implements TokenSource {
  FactusAuth(this.s)
      : _plain = Dio(
          BaseOptions(
            baseUrl: s.factusBaseUrl,
            connectTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(seconds: 30),
            headers: {'Accept': 'application/json'},
          ),
        );

  final AppSettings s;
  final Dio _plain;
  String? _access;
  String? _refresh;
  DateTime? _expires;
  Future<String>? _inflight;

  @override
  Future<String> getToken({bool forceRefresh = false}) {
    final a = _access;
    final e = _expires;
    if (!forceRefresh && a != null && e != null && DateTime.now().isBefore(e)) {
      return Future.value(a);
    }
    return _inflight ??= _renew().whenComplete(() => _inflight = null);
  }

  Future<String> _renew() async {
    if (!s.factusConfigured) {
      throw ApiError('Faltan las credenciales de Factus. Ve a Configuración.');
    }
    try {
      final refresh = _refresh;
      if (refresh != null) {
        try {
          return await _grant({
            'grant_type': 'refresh_token',
            'client_id': s.factusClientId,
            'client_secret': s.factusClientSecret,
            'refresh_token': refresh,
          });
        } catch (_) {
          _refresh = null; // cae a login completo
        }
      }
      return await _grant({
        'grant_type': 'password',
        'client_id': s.factusClientId,
        'client_secret': s.factusClientSecret,
        'username': s.factusUsername,
        'password': s.factusPassword,
      });
    } catch (e) {
      final err = ApiError.from(e);
      if (err.status == 400 || err.status == 401) {
        throw ApiError(
          'Factus rechazó las credenciales. Revisa client id, client secret, '
          'usuario y contraseña (y que el ambiente sea el correcto).',
          status: err.status,
        );
      }
      throw err;
    }
  }

  Future<String> _grant(Map<String, String> form) async {
    final r = await _plain.post<dynamic>(
      '/oauth/token',
      data: form,
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );
    final d = asMap(r.data);
    final token = d['access_token'] as String;
    _refresh = (d['refresh_token'] as String?) ?? _refresh;
    final secs = int.tryParse('${d['expires_in']}') ?? 600;
    _access = token;
    _expires = DateTime.now().add(
      Duration(seconds: secs > 60 ? secs - 30 : secs ~/ 2),
    );
    return token;
  }
}

class NumberingRange {
  NumberingRange({
    required this.id,
    required this.prefix,
    required this.document,
    required this.current,
    required this.to,
  });

  final int id;
  final String prefix;
  final String document;
  final int? current;
  final int? to;

  String get label {
    final doc = document.isEmpty ? '' : ' · $document';
    final left = (current != null && to != null) ? ' · ${to! - current!} folios libres' : '';
    return '$prefix$doc$left';
  }

  bool get looksLikeInvoice =>
      document.toLowerCase().contains('factura') || document == '21';

  factory NumberingRange.fromJson(Map<String, dynamic> m) => NumberingRange(
        id: int.tryParse('${m['id']}') ?? 0,
        prefix: '${m['prefix'] ?? ''}',
        document: '${m['document'] ?? m['document_name'] ?? ''}',
        current: int.tryParse('${m['current']}'),
        to: int.tryParse('${m['to']}'),
      );
}

class BillPage {
  BillPage(this.rows, this.page, this.lastPage);
  final List<Map<String, dynamic>> rows;
  final int page;
  final int lastPage;
}

class PdfFile {
  PdfFile(this.name, this.base64);
  final String name;
  final String base64;
}

class FactusApi {
  FactusApi(AppSettings s) : _auth = FactusAuth(s) {
    dio = buildDio(s.factusBaseUrl, _auth);
  }

  final FactusAuth _auth;
  late final Dio dio;

  /// Fuerza el login (sirve para "Probar conexión").
  Future<void> testLogin() async {
    try {
      await _auth.getToken(forceRefresh: true);
    } catch (e) {
      throw ApiError.from(e);
    }
  }

  Future<List<NumberingRange>> numberingRanges() async {
    try {
      final r = await dio.get<dynamic>(
        '/v2/numbering-ranges',
        queryParameters: {'filter[is_active]': 1},
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
          .map((e) => Map<String, dynamic>.from(e))
          .where((m) => m['is_expired'] != true)
          .map(NumberingRange.fromJson)
          .where((n) => n.id != 0)
          .toList();
    } catch (e) {
      throw ApiError.from(e);
    }
  }

  /// Crea y valida la factura ante la DIAN. Es idempotente por `reference_code`:
  /// si ya se procesó, Factus devuelve la factura existente.
  Future<Map<String, dynamic>> createBill(Map<String, dynamic> payload) async {
    Future<Map<String, dynamic>> send() async {
      final r = await dio.post<dynamic>('/v2/bills/validate', data: payload);
      return asMap(asMap(r.data)['data']);
    }

    try {
      return await send();
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        // Hay una factura pendiente por enviar a la DIAN con esa referencia:
        // según la documentación se elimina y se vuelve a crear.
        await deleteByReference(payload['reference_code'] as String);
        try {
          return await send();
        } catch (e2) {
          throw ApiError.from(e2);
        }
      }
      throw ApiError.from(e);
    } catch (e) {
      throw ApiError.from(e);
    }
  }

  Future<BillPage> listBills({
    int page = 1,
    int perPage = 15,
    String? field,
    String? query,
    int? status,
  }) async {
    try {
      final q = <String, dynamic>{'page': page, 'filter[per_page]': perPage};
      if (status != null) q['filter[status]'] = status;
      if (field != null && query != null && query.trim().isNotEmpty) {
        q['filter[$field]'] = query.trim();
      }
      final r = await dio.get<dynamic>('/v2/bills', queryParameters: q);
      final body = asMap(r.data);
      final d = body['data'];
      List rows = const [];
      Map? meta;
      if (d is List) {
        rows = d;
        meta = body['pagination'] is Map ? body['pagination'] as Map : null;
      } else if (d is Map) {
        if (d['data'] is List) rows = d['data'] as List;
        meta = d['pagination'] is Map ? d['pagination'] as Map : d;
      }
      final last = int.tryParse('${meta?['last_page']}') ?? page;
      return BillPage(
        rows.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(),
        page,
        last < 1 ? 1 : last,
      );
    } catch (e) {
      throw ApiError.from(e);
    }
  }

  Future<Map<String, dynamic>> getBill(String number) async {
    try {
      final r = await dio.get<dynamic>(
        '/v2/bills/${Uri.encodeComponent(number)}',
      );
      final d = asMap(asMap(r.data)['data']);
      return d['bill'] is Map ? asMap(d['bill']) : d;
    } catch (e) {
      throw ApiError.from(e);
    }
  }

  Future<PdfFile> downloadPdf(String number) async {
    try {
      final r = await dio.get<dynamic>(
        '/v2/bills/${Uri.encodeComponent(number)}/download-pdf',
      );
      final body = asMap(r.data);
      final d = body['data'] is Map ? asMap(body['data']) : body;
      final b64 = d['pdf_base_64_encoded'] as String?;
      if (b64 == null || b64.isEmpty) {
        throw ApiError('Factus no devolvió el PDF de la factura.');
      }
      final name = (d['file_name'] ?? d['filename'] ?? 'factura_$number') as String;
      return PdfFile(name, b64);
    } catch (e) {
      throw ApiError.from(e);
    }
  }

  /// Solo para facturas NO validadas por la DIAN.
  Future<void> deleteByReference(String reference) async {
    try {
      await dio.delete<dynamic>(
        '/v2/bills/destroy/reference/${Uri.encodeComponent(reference)}',
      );
    } catch (e) {
      throw ApiError.from(e);
    }
  }
}
