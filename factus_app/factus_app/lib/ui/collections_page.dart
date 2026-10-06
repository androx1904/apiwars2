import 'package:flutter/material.dart';

import '../api/api_error.dart';
import '../api/factus_pay_api.dart';
import '../app_services.dart';
import 'widgets.dart';

/// Cobros sueltos con QR de Factus Pay (no necesariamente ligados a una factura).
class CollectionsPage extends StatefulWidget {
  const CollectionsPage({super.key});

  @override
  State<CollectionsPage> createState() => _CollectionsPageState();
}

class _CollectionsPageState extends State<CollectionsPage> {
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _lookup = TextEditingController();
  String? _active;
  bool _creating = false;
  bool _loadingList = false;
  String? _listNote;
  List<PayCollection> _list = [];

  @override
  void initState() {
    super.initState();
    AppServices.instance.addListener(_loadList);
    _loadList();
  }

  @override
  void dispose() {
    AppServices.instance.removeListener(_loadList);
    _amount.dispose();
    _reference.dispose();
    _lookup.dispose();
    super.dispose();
  }

  Future<void> _loadList() async {
    if (!AppServices.instance.settings.payConfigured) {
      setState(() {
        _list = [];
        _listNote = 'Configura las credenciales de Factus Pay para crear y consultar cobros.';
      });
      return;
    }
    setState(() => _loadingList = true);
    try {
      final l = await AppServices.instance.pay.listCollections();
      if (!mounted) return;
      setState(() {
        _list = l;
        _listNote = l.isEmpty ? 'Aún no hay cobros.' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _listNote = 'No se pudo listar los cobros: ${ApiError.from(e).message}');
    } finally {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  Future<void> _create() async {
    final amount = parseNum(_amount.text);
    if (amount == null || !FactusPayApi.amountInRange(amount)) {
      showMessage(context, 'El monto debe estar entre \$10.000 y \$12.000.000 COP.', error: true);
      return;
    }
    final ref = _reference.text.trim().isEmpty
        ? 'COBRO-${DateTime.now().millisecondsSinceEpoch}'
        : _reference.text.trim();
    if (ref.length > 100) {
      showMessage(context, 'La referencia no puede superar 100 caracteres.', error: true);
      return;
    }
    setState(() => _creating = true);
    try {
      await AppServices.instance.pay.createCollection(ref, amount);
      if (!mounted) return;
      setState(() => _active = ref);
      _amount.clear();
      _reference.clear();
      _loadList();
    } catch (e) {
      if (mounted) showMessage(context, ApiError.from(e).full, error: true);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final configured = AppServices.instance.settings.payConfigured;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Cobros con QR (Factus Pay)', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        sectionCard(
          context,
          'Nuevo cobro',
          Wrap(
            spacing: 16,
            runSpacing: 16,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Monto (COP)',
                    helperText: 'Entre \$10.000 y \$12.000.000',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _reference,
                  decoration: const InputDecoration(
                    labelText: 'Referencia (opcional)',
                    helperText: 'Única por cobro; si se omite se genera',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: (!configured || _creating) ? null : _create,
                icon: const Icon(Icons.qr_code_2),
                label: Text(_creating ? 'Creando…' : 'Generar QR'),
              ),
            ],
          ),
        ),
        sectionCard(
          context,
          'Consultar por referencia',
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 320,
                child: TextField(
                  controller: _lookup,
                  decoration: const InputDecoration(
                    labelText: 'Referencia del cobro',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (v) => setState(() => _active = v.trim().isEmpty ? null : v.trim()),
                ),
              ),
              OutlinedButton(
                onPressed: !configured
                    ? null
                    : () => setState(() =>
                        _active = _lookup.text.trim().isEmpty ? null : _lookup.text.trim()),
                child: const Text('Consultar'),
              ),
            ],
          ),
        ),
        if (_active != null)
          sectionCard(
            context,
            'Cobro: $_active',
            CollectionPanel(key: ValueKey(_active), reference: _active!),
          ),
        sectionCard(
          context,
          'Cobros recientes',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_loadingList) const LinearProgressIndicator(),
              if (_listNote != null) Text(_listNote!),
              for (final c in _list)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    c.paid ? Icons.check_circle : Icons.schedule,
                    color: c.paid ? Colors.green : null,
                  ),
                  title: Text(c.reference),
                  subtitle: Text(c.paid ? 'Pagado' : (c.qr == null ? 'Generando QR' : 'Esperando pago')),
                  trailing: Text(cop(c.amount)),
                  onTap: () => setState(() => _active = c.reference),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _loadingList ? null : _loadList,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Actualizar'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
