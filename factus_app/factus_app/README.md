# Factus Facturación (Windows)

Aplicación de escritorio en Flutter para facturación electrónica (DIAN) con **Factus API v2** y cobros por QR con **Factus Pay**.

## Qué hace

- Crea facturas de venta y las valida ante la DIAN (`/v2/bills/validate`), con `reference_code` fijo para no duplicar en reintentos.
- Lista, busca, consulta y descarga el PDF de las facturas.
- Elimina facturas **no validadas** (las validadas requieren nota crédito, que no está incluida).
- Genera cobros con QR en Factus Pay (monto entre $10.000 y $12.000.000) y consulta su estado cada 4 s.
- Guarda las credenciales en el almacén seguro del sistema.

## Requisitos para compilar

- Windows 10/11
- Flutter estable reciente (3.33 o superior)
- Visual Studio 2022 con la carga de trabajo "Desarrollo para el escritorio con C++" (y componente ATL)

## Compilar el .exe

```
cd factus_app
flutter create . --platforms=windows --project-name factus_facturacion
flutter pub get
flutter test
flutter run -d windows            # para probar
flutter build windows --release   # genera el ejecutable
```

El resultado queda en `build\windows\x64\runner\Release\` (`factus_facturacion.exe` junto a sus DLL y la carpeta `data`; hay que distribuir la carpeta completa).

### Sin Windows: GitHub Actions

Sube este proyecto a un repositorio de GitHub y ejecuta el workflow **Build Windows (.exe)** (pestaña Actions). Al terminar, descarga el artefacto `FactusFacturacion-windows.zip`.

## Configuración

Abre la pestaña **Configuración**:

1. Elige **Sandbox** (por defecto) o **Producción**.
2. Factus: client id, client secret, usuario (email) y contraseña.
3. Factus Pay: email y contraseña (opcional; solo si usarás cobros QR).
4. "Guardar y probar conexión".

Empieza siempre en sandbox. En producción la app pide confirmación antes de emitir.

## Advertencias

- **El código no fue compilado ni probado** en el entorno donde se escribió (no había Flutter/Dart). Puede haber errores de compilación menores; corre `flutter analyze` y `flutter test` primero.
- Verifica contra la documentación de Factus: URLs de producción, forma de la respuesta de rangos de numeración y del listado de cobros de Pay, y los códigos de forma/medio de pago y tipo de documento.
- Factus limita a 80 solicitudes por minuto.
- Fuera de alcance: notas crédito/débito, documento soporte, nómina.

## Documentación

- https://developers.factus.com.co
- https://pay-developers.factus.com.co
