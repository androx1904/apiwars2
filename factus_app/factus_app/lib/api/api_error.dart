import 'package:dio/dio.dart';

/// Error de API ya traducido a un mensaje legible para el usuario.
class ApiError implements Exception {
  ApiError(this.message, {this.status, this.details = const []});

  final String message;
  final int? status;
  final List<String> details;

  String get full => details.isEmpty
      ? message
      : '$message\n${details.map((d) => '• $d').join('\n')}';

  @override
  String toString() => full;

  static ApiError from(Object e) {
    if (e is ApiError) return e;
    if (e is DioException) {
      if (e.error is ApiError) return e.error as ApiError;
      final r = e.response;
      if (r == null) {
        return ApiError(
          'No se pudo conectar con el servidor. Revisa tu conexión a internet.',
        );
      }
      var msg = 'Error ${r.statusCode}';
      final details = <String>[];
      final data = r.data;
      if (data is Map) {
        final m = data['message'];
        if (m is String && m.isNotEmpty) msg = m;
        _collect(data['errors'], details);
        final inner = data['data'];
        if (inner is Map) _collect(inner['errors'], details);
      }
      if (r.statusCode == 429) {
        msg = 'Demasiadas solicitudes (límite de 80 por minuto). '
            'Espera un momento e inténtalo de nuevo.';
      }
      return ApiError(msg, status: r.statusCode, details: details.take(8).toList());
    }
    return ApiError(e.toString());
  }

  static void _collect(dynamic errors, List<String> out) {
    if (errors is Map) {
      errors.forEach((k, v) {
        if (v is List) {
          for (final x in v) {
            out.add('$k: $x');
          }
        } else if (v != null) {
          out.add('$k: $v');
        }
      });
    } else if (errors is List) {
      for (final x in errors) {
        out.add('$x');
      }
    }
  }
}
