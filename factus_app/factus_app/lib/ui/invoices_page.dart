import 'package:flutter/material.dart';

import '../api/api_error.dart';
import '../api/factus_api.dart';
import '../app_services.dart';
import 'invoice_detail_page.dart';
import 'widgets.dart';

class InvoicesPage extends StatefulWidget {
  const InvoicesPage({super.key});

  @override
  State<InvoicesPage> createState() => _InvoicesPageState();
}

class _InvoicesPageState extends State<InvoicesPage> {
  final _search = TextEditingController();
  String _field = 'names';
  int? _status;
  int _page = 1;
  BillPage? _data;
  ApiError? _error;
  bool _loading = false;

  static const _fields = {
    'names': 'Cliente',
    'identification': 'Identificación',
    'number': 'Número',
    'reference_code': 'Referencia',
  };

  @override
  void initState() {
    super.initState();
    AppServices.instance.invoicesTick.addListener(_reload);
    AppServices.instance.addListener(_reload);
    _load();
  }

  @override
  void dispose() {
    AppServices.instance.invoicesTick.removeListener(_reload);
    AppServices.instance.removeListener(_reload);
    _search.dispose();
    super.dispose();
  }

  void _reload() {
    _page = 1;
    _load();
  }

  Future<void> _load() async {
    if (!AppServices.instance.settings.factusConfigured) {
      setState(() {
        _data = null;
        _error = ApiError('Configura las credenciales de Factus para ver tus facturas.');
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final d = await AppServices.instance.factus.listBills(
        page: _page,
        field: _field,
        query: _search.text,
        status: _status,
      );
      if (!mounted) return;
      setState(() {
        _data = d;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = ApiError.from(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Facturas', style: Theme.of(context).textTheme.headlineSmall),
              const Spacer(),
              IconButton(
                tooltip: 'Actualizar',
                onPressed: _loading ? null : _reload,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<String>(
                value: _field,
                items: [
                  for (final e in _fields.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _field = v ?? 'names'),
              ),
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _search,
                  decoration: const InputDecoration(
                    hintText: 'Buscar…',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _reload(),
                ),
              ),
              DropdownButton<int?>(
                value: _status,
                items: const [
                  DropdownMenuItem(value: null, child: Text('Todas')),
                  DropdownMenuItem(value: 1, child: Text('Validadas')),
                  DropdownMenuItem(value: 0, child: Text('Pendientes')),
                ],
                onChanged: (v) {
                  setState(() => _status = v);
                  _reload();
                },
              ),
              FilledButton(onPressed: _reload, child: const Text('Buscar')),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                _error!.full,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: data == null
                ? const SizedBox.shrink()
                : data.rows.isEmpty
                    ? const Center(child: Text('No hay facturas para mostrar.'))
                    : Card(
                        child: ListView.separated(
                          itemCount: data.rows.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final b = data.rows[i];
                            final number = pickText(b, ['number']);
                            final ok = billValidated(b);
                            return ListTile(
                              leading: Icon(
                                ok ? Icons.verified : Icons.hourglass_empty,
                                color: ok ? Colors.green : Colors.orange,
                              ),
                              title: Text(number.isEmpty ? '(sin número)' : number),
                              subtitle: Text(
                                '${billCustomer(b)}  ·  Ref: ${pickText(b, ['reference_code'])}',
                              ),
                              trailing: Text(
                                cop(billTotal(b)),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              onTap: number.isEmpty
                                  ? null
                                  : () => Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => InvoiceDetailPage(number: number),
                                        ),
                                      ),
                            );
                          },
                        ),
                      ),
          ),
          if (data != null)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _page > 1 && !_loading
                      ? () {
                          _page--;
                          _load();
                        }
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('Página ${data.page} de ${data.lastPage}'),
                IconButton(
                  onPressed: _page < data.lastPage && !_loading
                      ? () {
                          _page++;
                          _load();
                        }
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
