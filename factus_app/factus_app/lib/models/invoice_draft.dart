/// Borrador de factura y construcción del payload de `POST /v2/bills/validate`.
/// Los importes se calculan en centavos enteros para evitar errores de flotantes
/// y se redondean por línea (como hace la representación gráfica de la DIAN).
class DraftItem {
  DraftItem({
    required this.code,
    required this.name,
    required this.quantity,
    required this.price,
    this.discountRate = 0,
    this.taxRate = 19,
  });

  final String code;
  final String name;
  final double quantity;

  /// Precio unitario sin impuestos ni descuentos.
  final double price;

  /// Porcentaje de descuento (0–100).
  final double discountRate;

  /// Tarifa de IVA: 0, 5 o 19.
  final int taxRate;

  int get baseCents {
    final gross = (quantity * price * 100).round();
    final discount = (gross * discountRate / 100).round();
    return gross - discount;
  }

  int get taxCents => (baseCents * taxRate / 100).round();
  int get totalCents => baseCents + taxCents;

  Map<String, dynamic> toJson() => {
        'code_reference': code,
        'name': name,
        'quantity': quantity.toStringAsFixed(2),
        'discount_rate': discountRate.toStringAsFixed(2),
        'price': price.toStringAsFixed(2),
        'unit_measure_code': '94', // unidad
        'standard_code': '999', // estándar de adopción del contribuyente
        'taxes': [
          {'code': '01', 'rate': taxRate.toStringAsFixed(2)}, // 01 = IVA
        ],
      };
}

class DraftCustomer {
  DraftCustomer({
    required this.docType,
    required this.identification,
    required this.orgCode,
    required this.name,
    this.email = '',
    this.phone = '',
    this.address = '',
    this.municipality = '',
  });

  /// Código DIAN del tipo de documento (13 CC, 22 CE, 31 NIT, 41 pasaporte…).
  final String docType;
  final String identification;

  /// 1 = persona jurídica, 2 = persona natural.
  final String orgCode;
  final String name;
  final String email;
  final String phone;
  final String address;
  final String municipality;

  Map<String, dynamic> toJson() {
    final id = docType == '31'
        ? identification.replaceAll(RegExp(r'\D'), '')
        : identification.trim();
    final m = <String, dynamic>{
      'identification_document_code': docType,
      'identification': id,
      'legal_organization_code': orgCode,
      'tribute_code': 'ZZ',
      'country_code': 'CO',
      if (orgCode == '1') 'company': name.trim() else 'names': name.trim(),
    };
    if (address.trim().isNotEmpty) m['address'] = address.trim();
    if (email.trim().isNotEmpty) m['email'] = email.trim();
    if (phone.trim().isNotEmpty) m['phone'] = phone.trim();
    if (municipality.trim().isNotEmpty) {
      m['municipality_code'] = municipality.trim();
    }
    return m;
  }
}

int sumBase(List<DraftItem> items) =>
    items.fold(0, (sum, i) => sum + i.baseCents);
int sumTax(List<DraftItem> items) =>
    items.fold(0, (sum, i) => sum + i.taxCents);
int sumTotal(List<DraftItem> items) =>
    items.fold(0, (sum, i) => sum + i.totalCents);

String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String formatDate(DateTime d) => _date(d);

Map<String, dynamic> buildBillPayload({
  required String reference,
  required DraftCustomer customer,
  required List<DraftItem> items,
  required String paymentForm, // 1 contado, 2 crédito
  required String paymentMethod,
  int? rangeId,
  DateTime? dueDate,
  String observation = '',
  bool sendEmail = false,
}) {
  final total = sumTotal(items);
  return {
    'reference_code': reference,
    'document': '01', // factura electrónica de venta
    'operation_type': '10', // estándar
    if (rangeId != null) 'numbering_range_id': rangeId,
    if (observation.trim().isNotEmpty) 'observation': observation.trim(),
    'send_email': sendEmail,
    'payment_details': [
      {
        'payment_form': paymentForm,
        'payment_method_code': paymentMethod,
        'amount': (total / 100).toStringAsFixed(2),
        if (paymentForm == '2' && dueDate != null) 'due_date': _date(dueDate),
      },
    ],
    'customer': customer.toJson(),
    'items': items.map((i) => i.toJson()).toList(),
  };
}
