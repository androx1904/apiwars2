import 'package:flutter/material.dart';

import '../api/api_error.dart';
import '../api/factus_api.dart';
import '../api/factus_pay_api.dart';
import '../app_services.dart';
import '../models/invoice_draft.dart';
import 'invoice_detail_page.dart';
import 'widgets.dart';

class InvoiceFormPage extends StatefulWidget {
  const InvoiceFormPage({super.key});

  @override
  State<InvoiceFormPage> createState() => _InvoiceFormPageState();
}

class _InvoiceFormPageState extends State<InvoiceFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _id = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _muni = TextEditingController(text: '11001');
  final _obs = TextEditingController();

  String _docType = '13';
  String _org = '2';
  String _payForm = '1';
  String _payMethod = '10';
  DateTime _due = DateTime.now().add(const Duration(days: 30));
  bool _sendEmail = false;
  bool _withCollection = true;
  bool _submitting = false;
  int _resetCount = 0;
  final List<DraftItem> _items = [];

  List<NumberingRange> _ranges = [];
  int? _rangeId;
  String? _rangesNote;
  bool _loadingRanges = false;

  /// Se fija antes de enviar y se reutiliza si hay que reintentar: así Factus
  /// nunca emite dos facturas por un mismo intento (idempotencia).
  String _reference = _newReference();

  static String _newReference() {
    final n = DateTime.now();
    String p(int v) => v.toString().padLeft(2, '0');
    return 'APP-${n.year}${p(n.month)}${p(n.day)}-${p(n.hour)}${p(n.minute)}${p(n.second)}-${n.millisecond}';
  }

  static const _docTypes = {
    '13': 'Cédula de ciudadanía',
    '22': 'Cédula de extranjería',
    '31': 'NIT',
    '41': 'Pasaporte',
  };
  static const _payMethods = {
    '10': 'Efectivo',
    '42': 'Consignación bancaria',
    '47': 'Transferencia débito bancaria',
    '48': 'Tarjeta crédito',
    '49': 'Tarjeta débito',
  };

  @override
  void initState() {
    super.initState();
    AppServices.instance.addListener(_loadRanges);
    _loadRanges();
  }

  @override
  void dispose() {
    AppServices.instance.removeListener(_loadRanges);
    for (final c in [_id, _name, _email, _phone, _address, _muni, _obs]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadRanges() async {
    final svc = AppServices.instance;
    if (!svc.settings.factusConfigured) {
      setState(() {
        _ranges = [];
        _rangeId = null;
        _rangesNote = 'Configura las credenciales de Factus para emitir facturas.';
      });
      return;
    }
    setState(() => _loadingRanges = true);
    try {
      final list = await svc.factus.numberingRanges();
      if (!mounted) return;
      setState(() {
        _ranges = list;
        _rangesNote = list.isEmpty
            ? 'No se encontraron rangos activos; se usará el rango por defecto de Factus.'
            : null;
        final invoiceLike = list.where((r) => r.looksLikeInvoice).toList();
        final pick = invoiceLike.isNotEmpty ? invoiceLike.first : (list.isNotEmpty ? list.first : null);
        _rangeId = _ranges.any((r) => r.id == _rangeId) ? _rangeId : pick?.id;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ranges = [];
        _rangeId = null;
        _rangesNote =
            'No se pudieron leer los rangos de numeración (${ApiError.from(e).message}). '
            'Si tu cuenta tiene un solo rango, igual podrás facturar.';
      });
    } finally {
      if (mounted) setState(() => _loadingRanges = false);
    }
  }

  int get _total => sumTotal(_items);

  bool get _canCollect =>
      AppServices.instance.settings.payConfigured &&
      FactusPayApi.amountInRange(_total / 100);

  Future<void> _addItem() async {
    final item = await showDialog<DraftItem>(
      context: context,
      builder: (_) => _ItemDialog(nextIndex: _items.length + 1),
    );
    if (item != null) setState(() => _items.add(item));
  }

  Future<void> _pickDue() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _due,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (d != null) setState(() => _due = d);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_items.isEmpty) {
      showMessage(context, 'Agrega al menos un ítem.', error: true);
      return;
    }
    final svc = AppServices.instance;
    if (!svc.settings.factusConfigured) {
      showMessage(context, 'Configura las credenciales de Factus primero.', error: true);
      return;
    }
    if (svc.settings.production) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Emitir en PRODUCCIÓN'),
          content: Text(
            'Se emitirá una factura real ante la DIAN por ${cop(_total / 100)}. '
            'Una factura validada no se puede borrar. ¿Continuar?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Emitir')),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _submitting = true);
    try {
      final payload = buildBillPayload(
        reference: _reference,
        rangeId: _rangeId,
        customer: DraftCustomer(
          docType: _docType,
          identification: _id.text,
          orgCode: _org,
          name: _name.text,
          email: _email.text,
          phone: _phone.text,
          address: _address.text,
          municipality: _muni.text,
        ),
        items: _items,
        paymentForm: _payForm,
        paymentMethod: _payMethod,
        dueDate: _due,
        observation: _obs.text,
        sendEmail: _sendEmail,
      );
      final totalPesos = _total / 100;
      final wantCollection = _withCollection && _canCollect;

      final bill = await svc.factus.createBill(payload);
      final number = pickText(bill, ['number']);

      String? collectionNote;
      if (wantCollection) {
        try {
          await svc.pay.createCollection(_reference, totalPesos);
        } catch (e) {
          collectionNote =
              'La factura se emitió, pero el cobro no se pudo crear: ${ApiError.from(e).message}';
        }
      }

      svc.invoicesTick.value++;
      if (!mounted) return;
      _resetForm();
      showMessage(
        context,
        collectionNote ?? 'Factura $number emitida correctamente.',
        error: collectionNote != null,
      );
      if (number.isNotEmpty) {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => InvoiceDetailPage(number: number)),
        );
      }
    } catch (e) {
      // Se conserva _reference: un reintento es idempotente.
      if (mounted) showMessage(context, ApiError.from(e).full, error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _resetForm() {
    setState(() {
      for (final c in [_id, _name, _email, _phone, _address, _obs]) {
        c.clear();
      }
      _muni.text = '11001';
      _items.clear();
      _docType = '13';
      _org = '2';
      _payForm = '1';
      _payMethod = '10';
      _sendEmail = false;
      _resetCount++;
      _reference = _newReference();
    });
  }

  Widget _text(
    TextEditingController c,
    String label, {
    bool required = false,
    TextInputType? keyboard,
    double width = 280,
    String? helper,
  }) {
    return SizedBox(
      width: width,
      child: TextFormField(
        controller: c,
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          helperText: helper,
          helperMaxLines: 2,
          border: const OutlineInputBorder(),
        ),
        validator: required
            ? (v) => (v == null || v.trim().isEmpty) ? 'Campo obligatorio' : null
            : null,
      ),
    );
  }

  Widget _dropdown(
    String label,
    String value,
    Map<String, String> options,
    ValueChanged<String> onChanged, {
    double width = 280,
  }) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<String>(
        key: ValueKey('$label-$value-$_resetCount'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        items: [
          for (final e in options.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sub = sumBase(_items);
    final tax = sumTax(_items);
    final total = _total;
    final canCollect = _canCollect;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Nueva factura electrónica', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          sectionCard(
            context,
            'Cliente',
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _dropdown('Tipo de documento', _docType, _docTypes, (v) => setState(() => _docType = v)),
                _text(_id, 'Número de documento', required: true, helper: 'Para NIT, sin dígito de verificación'),
                _dropdown(
                  'Tipo de persona',
                  _org,
                  const {'2': 'Persona natural', '1': 'Persona jurídica'},
                  (v) => setState(() => _org = v),
                ),
                _text(_name, _org == '1' ? 'Razón social' : 'Nombres y apellidos', required: true, width: 400),
                _text(_email, 'Correo electrónico', keyboard: TextInputType.emailAddress),
                _text(_phone, 'Teléfono', keyboard: TextInputType.phone),
                _text(_address, 'Dirección', width: 400),
                _text(
                  _muni,
                  'Código del municipio (DIVIPOLA)',
                  helper: 'Ej.: 11001 Bogotá, 05001 Medellín, 76001 Cali',
                ),
              ],
            ),
          ),
          sectionCard(
            context,
            'Ítems',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < _items.length; i++)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(_items[i].name),
                    subtitle: Text(
                      '${_items[i].quantity} × ${cop(_items[i].price)}'
                      '${_items[i].discountRate > 0 ? '  −${_items[i].discountRate}%' : ''}'
                      '  ·  IVA ${_items[i].taxRate}%',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(cop(_items[i].totalCents / 100)),
                        IconButton(
                          tooltip: 'Quitar',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => setState(() => _items.removeAt(i)),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _addItem,
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar ítem'),
                ),
                const Divider(height: 32),
                _totalRow('Subtotal', cop(sub / 100)),
                _totalRow('IVA', cop(tax / 100)),
                _totalRow('Total a pagar', cop(total / 100), bold: true),
              ],
            ),
          ),
          sectionCard(
            context,
            'Pago y numeración',
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _dropdown(
                  'Forma de pago',
                  _payForm,
                  const {'1': 'Contado', '2': 'Crédito'},
                  (v) => setState(() => _payForm = v),
                ),
                _dropdown('Medio de pago', _payMethod, _payMethods, (v) => setState(() => _payMethod = v)),
                if (_payForm == '2')
                  SizedBox(
                    width: 280,
                    child: OutlinedButton.icon(
                      onPressed: _pickDue,
                      icon: const Icon(Icons.event),
                      label: Text('Vence: ${formatDate(_due)}'),
                    ),
                  ),
                if (_loadingRanges)
                  const SizedBox(width: 280, child: LinearProgressIndicator())
                else if (_ranges.isNotEmpty)
                  SizedBox(
                    width: 420,
                    child: DropdownButtonFormField<int>(
                      key: ValueKey('range-$_rangeId-${_ranges.length}'),
                      initialValue: _rangeId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Rango de numeración',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final r in _ranges) DropdownMenuItem(value: r.id, child: Text(r.label)),
                      ],
                      onChanged: (v) => setState(() => _rangeId = v),
                    ),
                  ),
                if (_rangesNote != null) SizedBox(width: 600, child: Text(_rangesNote!)),
                _text(_obs, 'Observación (máx. 500 caracteres)', width: 600),
              ],
            ),
          ),
          sectionCard(
            context,
            'Opciones',
            Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Generar cobro con QR en Factus Pay'),
                  subtitle: Text(
                    !AppServices.instance.settings.payConfigured
                        ? 'Configura las credenciales de Factus Pay para activarlo.'
                        : (FactusPayApi.amountInRange(total / 100) || total == 0
                            ? 'Usa la misma referencia y el total de la factura.'
                            : 'El total debe estar entre \$10.000 y \$12.000.000.'),
                  ),
                  value: _withCollection && canCollect,
                  onChanged: canCollect ? (v) => setState(() => _withCollection = v) : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enviar la factura por correo al cliente'),
                  subtitle: const Text('Factus solo envía correos en producción.'),
                  value: _sendEmail,
                  onChanged: (v) => setState(() => _sendEmail = v),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: Text(_submitting ? 'Emitiendo…' : 'Emitir factura'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _totalRow(String label, String value, {bool bold = false}) {
    final style = bold ? Theme.of(context).textTheme.titleMedium : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _ItemDialog extends StatefulWidget {
  const _ItemDialog({required this.nextIndex});

  final int nextIndex;

  @override
  State<_ItemDialog> createState() => _ItemDialogState();
}

class _ItemDialogState extends State<_ItemDialog> {
  late final TextEditingController _code =
      TextEditingController(text: 'ITEM-${widget.nextIndex}');
  final _name = TextEditingController();
  final _qty = TextEditingController(text: '1');
  final _price = TextEditingController();
  final _disc = TextEditingController(text: '0');
  int _tax = 19;
  String? _error;

  @override
  void dispose() {
    for (final c in [_code, _name, _qty, _price, _disc]) {
      c.dispose();
    }
    super.dispose();
  }

  void _accept() {
    final qty = parseNum(_qty.text);
    final price = parseNum(_price.text);
    final disc = parseNum(_disc.text) ?? 0;
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Escribe el nombre del producto o servicio.');
    } else if (qty == null || qty <= 0) {
      setState(() => _error = 'La cantidad debe ser mayor que 0.');
    } else if (price == null || price < 0) {
      setState(() => _error = 'Escribe un precio válido.');
    } else if (disc < 0 || disc > 100) {
      setState(() => _error = 'El descuento debe estar entre 0 y 100.');
    } else {
      Navigator.pop(
        context,
        DraftItem(
          code: _code.text.trim().isEmpty ? 'ITEM-${widget.nextIndex}' : _code.text.trim(),
          name: _name.text.trim(),
          quantity: qty,
          price: price,
          discountRate: disc,
          taxRate: _tax,
        ),
      );
    }
  }

  Widget _f(TextEditingController c, String label, {double width = 160, String? helper}) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: c,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Agregar ítem'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _f(_code, 'Código', width: 140),
                  _f(_name, 'Nombre / descripción', width: 340),
                  _f(_qty, 'Cantidad'),
                  _f(_price, 'Precio unitario', helper: 'Sin IVA. Usa punto o coma solo para decimales'),
                  _f(_disc, 'Descuento %'),
                  SizedBox(
                    width: 160,
                    child: DropdownButtonFormField<int>(
                      initialValue: _tax,
                      decoration: const InputDecoration(
                        labelText: 'IVA',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 19, child: Text('19 %')),
                        DropdownMenuItem(value: 5, child: Text('5 %')),
                        DropdownMenuItem(value: 0, child: Text('0 %')),
                      ],
                      onChanged: (v) => setState(() => _tax = v ?? 19),
                    ),
                  ),
                ],
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _accept, child: const Text('Agregar')),
      ],
    );
  }
}
