import 'package:flutter/foundation.dart';

import 'api/factus_api.dart';
import 'api/factus_pay_api.dart';
import 'settings.dart';

/// Punto único de acceso a configuración y clientes de API.
class AppServices extends ChangeNotifier {
  AppServices._();
  static final AppServices instance = AppServices._();

  final SettingsStore store = SettingsStore();

  /// Se incrementa cuando hay facturas nuevas para que el listado se recargue.
  final ValueNotifier<int> invoicesTick = ValueNotifier<int>(0);

  AppSettings settings = AppSettings.defaults();
  late FactusApi factus;
  late FactusPayApi pay;

  Future<void> init() async {
    settings = await store.load();
    _rebuild();
  }

  Future<void> update(AppSettings next) async {
    await store.save(next);
    if (next.payEmail != settings.payEmail ||
        next.payBaseUrl != settings.payBaseUrl) {
      await store.clearPayToken();
    }
    settings = next;
    _rebuild();
    notifyListeners();
  }

  void _rebuild() {
    factus = FactusApi(settings);
    pay = FactusPayApi(settings, store);
  }
}
