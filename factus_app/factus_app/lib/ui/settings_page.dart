import 'package:flutter/material.dart';

import '../api/api_error.dart';
import '../app_services.dart';
import '../settings.dart';
import 'widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late bool _production;
  late final TextEditingController _fUrl, _fId, _fSecret, _fUser, _fPass;
  late final TextEditingController _pUrl, _pEmail, _pPass;
  bool _busy = false;
  final List<String> _testLog = [];

  @override
  void initState() {
    super.initState();
    final s = AppServices.instance.settings;
    _production = s.production;
    _fUrl = TextEditingController(text: s.factusBaseUrl);
    _fId = TextEditingController(text: s.factusClientId);
    _fSecret = TextEditingController(text: s.factusClientSecret);
    _fUser = TextEditingController(text: s.factusUsername);
    _fPass = TextEditingController(text: s.factusPassword);
    _pUrl = TextEditingController(text: s.payBaseUrl);
    _pEmail = TextEditingController(text: s.payEmail);
    _pPass = TextEditingController(text: s.payPassword);
  }

  @override
  void dispose() {
    for (final c in [_fUrl, _fId, _fSecret, _fUser, _fPass, _pUrl, _pEmail, _pPass]) {
      c.dispose();
    }
    super.dispose();
  }

  AppSettings _current() => AppSettings(
        production: _production,
        factusBaseUrl: _fUrl.text.trim().replaceAll(RegExp(r'/+$'), ''),
        factusClientId: _fId.text.trim(),
        factusClientSecret: _fSecret.text.trim(),
        factusUsername: _fUser.text.trim(),
        factusPassword: _fPass.text,
        payBaseUrl: _pUrl.text.trim().replaceAll(RegExp(r'/+$'), ''),
        payEmail: _pEmail.text.trim(),
        payPassword: _pPass.text,
      );

  void _onEnvironment(bool production) {
    setState(() {
      _production = production;
      _fUrl.text = production ? AppSettings.productionFactus : AppSettings.sandboxFactus;
      _pUrl.text = production ? AppSettings.productionPay : AppSettings.sandboxPay;
    });
  }

  Future<void> _save({bool silent = false}) async {
    await AppServices.instance.update(_current());
    if (!silent && mounted) showMessage(context, 'Configuración guardada.');
  }

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _testLog.clear();
    });
    await _save(silent: true);
    final svc = AppServices.instance;

    if (svc.settings.factusConfigured) {
      try {
        await svc.factus.testLogin();
        _testLog.add('✔ Factus: autenticación correcta.');
        try {
          final ranges = await svc.factus.numberingRanges();
          _testLog.add('✔ Factus: ${ranges.length} rango(s) de numeración activo(s).');
        } catch (e) {
          _testLog.add('⚠ Factus: no se pudieron leer los rangos (${ApiError.from(e).message}).');
        }
      } catch (e) {
        _testLog.add('✘ Factus: ${ApiError.from(e).full}');
      }
    } else {
      _testLog.add('— Factus: faltan credenciales.');
    }

    if (svc.settings.payConfigured) {
      try {
        await svc.pay.testLogin();
        _testLog.add('✔ Factus Pay: autenticación correcta.');
      } catch (e) {
        _testLog.add('✘ Factus Pay: ${ApiError.from(e).full}');
      }
    } else {
      _testLog.add('— Factus Pay: sin credenciales (la app funciona sin cobros).');
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _tf(TextEditingController c, String label,
      {bool secret = false, double width = 360}) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: c,
        obscureText: secret,
        enableSuggestions: !secret,
        autocorrect: false,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Configuración', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        sectionCard(
          context,
          'Ambiente',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Sandbox (pruebas)')),
                  ButtonSegment(value: true, label: Text('Producción')),
                ],
                selected: {_production},
                onSelectionChanged: (v) => _onEnvironment(v.first),
              ),
              if (_production)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Producción: las facturas que emitas tienen validez ante la DIAN '
                    'y los cobros mueven dinero real.',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              const SizedBox(height: 8),
              const Text(
                'Cambiar el ambiente rellena las URLs por defecto; puedes editarlas abajo.',
              ),
            ],
          ),
        ),
        sectionCard(
          context,
          'Factus API (facturación electrónica)',
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _tf(_fUrl, 'URL base', width: 740),
              _tf(_fId, 'Client ID'),
              _tf(_fSecret, 'Client Secret', secret: true),
              _tf(_fUser, 'Usuario (correo)'),
              _tf(_fPass, 'Contraseña', secret: true),
            ],
          ),
        ),
        sectionCard(
          context,
          'Factus Pay (cobros con QR) · opcional',
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _tf(_pUrl, 'URL base', width: 740),
              _tf(_pEmail, 'Correo'),
              _tf(_pPass, 'Contraseña', secret: true),
            ],
          ),
        ),
        Wrap(
          spacing: 12,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : () => _save(),
              icon: const Icon(Icons.save),
              label: const Text('Guardar'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _test,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_tethering),
              label: const Text('Guardar y probar conexión'),
            ),
          ],
        ),
        if (_testLog.isNotEmpty) ...[
          const SizedBox(height: 16),
          for (final line in _testLog) SelectableText(line),
        ],
        const SizedBox(height: 24),
        const Text(
          'Las credenciales se guardan cifradas en el almacén seguro de Windows de este equipo.',
        ),
      ],
    );
  }
}
