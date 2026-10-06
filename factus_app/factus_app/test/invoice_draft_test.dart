import 'package:factus_facturacion/models/invoice_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('totales por línea en centavos (IVA 19% y descuento)', () {
    final items = [
      DraftItem(code: 'A', name: 'A', quantity: 1, price: 10000, taxRate: 19),
      DraftItem(code: 'B', name: 'B', quantity: 3, price: 20000, taxRate: 19),
    ];
    // Ejemplo oficial de Factus: base 70.000 + IVA 13.300 = 83.300
    expect(sumBase(items), 7000000);
    expect(sumTax(items), 1330000);
    expect(sumTotal(items), 8330000);
  });

  test('descuento porcentual se aplica antes del IVA', () {
    final i = DraftItem(
      code: 'X',
      name: 'X',
      quantity: 1,
      price: 50000,
      discountRate: 20,
      taxRate: 19,
    );
    expect(i.baseCents, 4000000);
    expect(i.taxCents, 760000);
    expect(i.totalCents, 4760000);
  });

  test('payload: monto de pago igual al total y due_date solo a crédito', () {
    final items = [
      DraftItem(code: 'A', name: 'A', quantity: 1, price: 10000, taxRate: 19),
    ];
    final customer = DraftCustomer(
      docType: '31',
      identification: '900.123.456',
      orgCode: '1',
      name: 'Empresa SAS',
    );
    final cash = buildBillPayload(
      reference: 'R1',
      customer: customer,
      items: items,
      paymentForm: '1',
      paymentMethod: '10',
      dueDate: DateTime(2026, 12, 31),
    );
    final pay = (cash['payment_details'] as List).first as Map;
    expect(pay['amount'], '11900.00');
    expect(pay.containsKey('due_date'), false);
    expect((cash['customer'] as Map)['identification'], '900123456');
    expect((cash['customer'] as Map)['company'], 'Empresa SAS');

    final credit = buildBillPayload(
      reference: 'R2',
      customer: customer,
      items: items,
      paymentForm: '2',
      paymentMethod: '42',
      dueDate: DateTime(2026, 12, 31),
    );
    final cpay = (credit['payment_details'] as List).first as Map;
    expect(cpay['due_date'], '2026-12-31');
  });
}
