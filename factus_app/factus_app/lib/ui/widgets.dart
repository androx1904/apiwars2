import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../api/api_error.dart';
import '../api/factus_pay_api.dart';
import '../app_services.dart';

/// Formato de pesos colombianos: $ 1.234.567 (con decimales solo si existen).
String cop(num value) {
  final negative = value < 0;
  final cents = (value.abs() * 100).round();
  final whole = (cents ~/ 100).toString();
  final frac = cents % 100;
  final buf = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buf.write('.');
    buf.write(whole[i]);
  }
  final sign = negative ? '-' : '';
  final decimals = frac == 0 ? '' : ',${frac.toString().padLeft(2, '0')}';
  return '$sign\$ $buf$decimals';
}

double? parseNum(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

void showMessage(BuildContext context, String text, {bool error = false}) {
  final scheme = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? scheme.error : null,
        duration: Duration(seconds: error ? 8 : 4),
      ),
    );
}

String pickText(Map<String, dynamic> m, List<String> keys) {
  for (final k in keys) {
    final v = m[k];
    if (v != null && '$v'.isNotEmpty && v is! Map && v is! List) return '$v';
  }
  return '';
}

String billCustomer(Map<String, dynamic> m) {
  final direct = pickText(m, ['graphic_representation_name', 'names', 'company']);
  if (direct.isNotEmpty) return direct;
  final c = m['customer'];
  if (c is Map) {
    return pickText(Map<String, dynamic>.from(c),
        ['graphic_representation_name', 'names', 'company']);
  }
  return '';
}

double billTotal(Map<String, dynamic> m) {
  dynamic v = m['total'];
  if (v == null && m['totals'] is Map) v = (m['totals'] as Map)['total'];
  if (v is num) return v.toDouble();
  return double.tryParse('$v') ?? 0;
}

bool billValidated(Map<String, dynamic> m) {
  if (m['is_validated'] != null) {
    final v = m['is_validated'];
    return v == true || v == 1 || v == '1';
  }
  final s = '${m['status']}';
  return s == '1' || s == 'validated';
}

Widget sectionCard(BuildContext context, String title, Widget child) {
  return Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}

/// Muestra un QR entregado como `data:image/png;base64,...`.
class QrDataImage extends StatelessWidget {
  const QrDataImage(this.dataUri, {super.key, this.size = 240});

  final String dataUri;
  final double size;

  @override
  Widget build(BuildContext context) {
    try {
      final i = dataUri.indexOf(',');
      final bytes = base64Decode(i >= 0 ? dataUri.substring(i + 1) : dataUri);
      return Container(
        padding: const EdgeInsets.all(12),
        color: Colors.white, // contraste alto para que el banco lo lea bien
        child: Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.none,
        ),
      );
    } catch (_) {
      return const Text('No se pudo mostrar el código QR.');
    }
  }
}

/// Estado del cobro en Factus Pay con QR. Consulta cada 4 s hasta que se pague.
/// Si el cobro no existe y se pasa [createAmount], ofrece crearlo.
class CollectionPanel extends StatefulWidget {
  const CollectionPanel({super.key, required this.reference, this.createAmount});

  final String reference;
  final num? createAmount;

  @override
  State<CollectionPanel> createState() => _CollectionPanelState();
}

class _CollectionPanelState extends State<CollectionPanel> {
  PayCollection? _c;
  ApiError? _error;
  bool _loading = true;
  bool _creating = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    _timer?.cancel();
    try {
      final c = await AppServices.instance.pay.getCollection(widget.reference);
      if (!mounted) return;
      setState(() {
        _c = c;
        _error = null;
        _loading = false;
      });
      if (!c.paid) _timer = Timer(const Duration(seconds: 4), _load);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiError.from(e);
        _loading = false;
      });
    }
  }

  Future<void> _create() async {
    setState(() => _creating = true);
    try {
      await AppServices.instance.pay
          .createCollection(widget.reference, widget.createAmount!);
      if (!mounted) return;
      setState(() => _loading = true);
      await _load();
    } catch (e) {
      if (mounted) showMessage(context, ApiError.from(e).full, error: true);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final err = _error;
    if (err != null) {
      final notFound = err.status == 404;
      final amount = widget.createAmount;
      if (notFound && amount != null) {
        final ok = FactusPayApi.amountInRange(amount);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(ok
                ? 'Esta factura aún no tiene cobro en Factus Pay.'
                : 'El total (${cop(amount)}) está fuera de los límites de Factus Pay '
                    '(\$10.000 – \$12.000.000), no se puede generar cobro.'),
            const SizedBox(height: 8),
            if (ok)
              FilledButton.icon(
                onPressed: _creating ? null : _create,
                icon: const Icon(Icons.qr_code_2),
                label: Text('Crear cobro por ${cop(amount)}'),
              ),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(err.full, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              setState(() => _loading = true);
              _load();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      );
    }
    final c = _c!;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Chip(
              avatar: Icon(
                c.paid ? Icons.check_circle : Icons.schedule,
                color: c.paid ? Colors.green : scheme.primary,
              ),
              label: Text(c.paid
                  ? 'Pagado'
                  : (c.qr == null ? 'Generando QR…' : 'Esperando pago')),
            ),
            Text(cop(c.amount), style: Theme.of(context).textTheme.titleLarge),
            Text('Ref: ${c.reference}'),
          ],
        ),
        const SizedBox(height: 12),
        if (!c.paid && c.qr != null) QrDataImage(c.qr!),
        if (!c.paid && c.qr != null)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('El cliente escanea este QR con la app de su banco.'),
          ),
      ],
    );
  }
}
