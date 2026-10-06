import 'package:dio/dio.dart';

/// Fuente de tokens. `forceRefresh` se usa tras un 401.
abstract class TokenSource {
  Future<String> getToken({bool forceRefresh = false});
}

/// Cliente Dio con Bearer automático y un único reintento ante 401.
Dio buildDio(String baseUrl, TokenSource tokens) {
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 60),
      headers: {'Accept': 'application/json'},
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        try {
          final token = await tokens.getToken();
          options.headers['Authorization'] = 'Bearer $token';
          handler.next(options);
        } catch (e) {
          handler.reject(
            DioException(
              requestOptions: options,
              error: e,
              type: DioExceptionType.unknown,
            ),
          );
        }
      },
      onError: (err, handler) async {
        final req = err.requestOptions;
        if (err.response?.statusCode == 401 && req.extra['retried'] != true) {
          try {
            final token = await tokens.getToken(forceRefresh: true);
            req.headers['Authorization'] = 'Bearer $token';
            req.extra['retried'] = true;
            final response = await dio.fetch<dynamic>(req);
            return handler.resolve(response);
          } on DioException catch (e) {
            return handler.next(e);
          } catch (_) {
            return handler.next(err);
          }
        }
        handler.next(err);
      },
    ),
  );
  return dio;
}

Map<String, dynamic> asMap(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
