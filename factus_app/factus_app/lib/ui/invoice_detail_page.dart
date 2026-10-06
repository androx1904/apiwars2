import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api_error.dart';
import '../app_services.dart';
import 'widgets.dart';

class InvoiceDetailPage extends StatefulWidget {
  const InvoiceDetailPage({super.key, required this.number});

  final String number;

  @override
  State<InvoiceDetailPage> createState() => _InvoiceDetailPageState();
}

class _InvoiceDetailPageState extends State<InvoiceDetailPage> {
  Map<String, dynamic>? _bill;
  ApiError? _error;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final b = await AppServices.instance.factus.getBill(widget.number);
      if (!mounted) return;
      setState(() {
        _bill = b;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ApiError.from(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _downloadPdf() async {
    setState(() => _busy = true);
    try {
      final pdf = await AppServices.instance.factus.downloadPdf(widget.number);
      final docs = await getApplicationDocumentsDirectory();
      final folder = Directory('${docs.path}${Platform.pathSeparator}Facturas');
      await folder.create(recursive: true);
      var name = pdf.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      if (!name.toLowerCase().endsWith('.pdf')) name = '$name.pdf';
      final file = File('${folder.path}${Platform.pathSeparator}$name');
      await file.writeAsBytes(base64Decode(pdf.base64));
      if (!mounted) return;
      showMessage(context, 'PDF guardado en ${file.path}');
      await launchUrl(Uri.file(file.path));
    } catch (e) {
      if (mounted) showMessage(context, ApiError.from(e).full, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(String reference) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Eliminar factura'),
        content: Text(
          'Se eliminará la factura con referencia $reference, que aún no está validada por la DIAN. '
          'No se puede deshacer.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await AppServices.instance.factus.deleteByReference(reference);
      AppServices.instance.invoicesTick.value++;
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showMessage(context, ApiError.from(e).full, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final b = _bill;
    return Scaffold(
      appBar: AppBar(title: Text('Factura ${widget.number}')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!.full),
                        const SizedBox(height: 12),
                        OutlinedButton(onPressed: _load, child: const Text('Reintentar')),
                      ],
                    ),
                  ),
                )
              : b == null
                  ? const SizedBox.shrink()
                  : _content(context, b),
    );
  }

  Widget _content(BuildContext context, Map<String, dynamic> b) {
    final validated = billValidated(b);
    final reference = pickText(b, ['reference_code']);
    final total = billTotal(b);
    final links = b['links'] is Map ? Map<String, dynamic>.from(b['links'] as Map) : <String, dynamic>{};
    final items = b['items'] is List ? (b['items'] as List).whereType<Map>().toList() : const [];
    final cufe = pickText(b, ['cufe']);
    final dianNotes = b['errors'] is Map ? Map<String, dynamic>.from(b['errors'] as Map) : <String, dynamic>{};

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        sectionCard(
          context,
          validated ? 'Validada por la DIAN' : 'Pendiente de validación',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText('Número: ${widget.number}'),
              SelectableText('Referencia: $reference'),
              SelectableText('Cliente: ${billCustomer(b)}'),
              if (cufe.isNotEmpty) SelectableText('CUFE: $cufe'),
              const SizedBox(height: 8),
              Text(cop(total), style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : _downloadPdf,
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('Descargar PDF'),
                  ),
                  if ('${links['public_url'] ?? ''}'.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => _open('${links['public_url']}'),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Ver en Factus'),
                    ),
                  if ('${links['qr'] ?? ''}'.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => _open('${links['qr']}'),
                      icon: const Icon(Icons.verified_user),
                      label: const Text('Consultar en la DIAN'),
                    ),
                  if (!validated && reference.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _delete(reference),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Eliminar (no validada)'),
                    ),
                ],
              ),
              if (validated)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Una factura validada no se puede borrar: para corregirla o anularla '
                    'hay que emitir una nota crédito.',
                  ),
                ),
            ],
          ),
        ),
        if (dianNotes.isNotEmpty)
          sectionCard(
            context,
            'Notificaciones de la DIAN',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final e in dianNotes.entries) SelectableText('${e.key}: ${e.value}'),
              ],
            ),
          ),
        sectionCard(
          context,
          'Ítems',
          Column(
            children: [
              for (final it in items)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text('${it['name'] ?? ''}'),
                  subtitle: Text('Cantidad: ${it['quantity'] ?? ''}'),
                  trailing: Text(
                    it['total'] == null ? '' : cop(double.tryParse('${it['total']}') ?? 0),
                  ),
                ),
            ],
          ),
        ),
        if (reference.isNotEmpty && AppServices.instance.settings.payConfigured)
          sectionCard(
            context,
            'Cobro con Factus Pay',
            CollectionPanel(reference: reference, createAmount: total),
          ),
      ],
    );
  }
}
