import 'package:flutter/material.dart';

import '../app_services.dart';
import 'collections_page.dart';
import 'invoice_form_page.dart';
import 'invoices_page.dart';
import 'settings_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late int _index;

  @override
  void initState() {
    super.initState();
    // Sin credenciales, arranca en Configuración.
    _index = AppServices.instance.settings.factusConfigured ? 0 : 3;
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 1000;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: wide,
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Icon(Icons.receipt_long,
                  size: 32, color: Theme.of(context).colorScheme.primary),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.list_alt_outlined),
                selectedIcon: Icon(Icons.list_alt),
                label: Text('Facturas'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.note_add_outlined),
                selectedIcon: Icon(Icons.note_add),
                label: Text('Nueva factura'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.qr_code_2_outlined),
                selectedIcon: Icon(Icons.qr_code_2),
                label: Text('Cobros'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('Configuración'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: const [
                InvoicesPage(),
                InvoiceFormPage(),
                CollectionsPage(),
                SettingsPage(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
