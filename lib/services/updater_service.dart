import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import 'api_service.dart';

class UpdaterService {
  final ShorebirdCodePush _shorebirdCodePush = ShorebirdCodePush();

  /// Verifica automáticamente si hay parches de Shorebird o nuevas versiones de APK disponibles.
  /// Llama a [onStatus] con un mensaje descriptivo y un booleano indicando si está listo para reiniciar.
  Future<void> verificarYDescargarActualizaciones({
    required Function(String mensaje, bool listoParaReiniciar) onStatus,
  }) async {
    // 1. Verificación en vivo mediante Shorebird (Code Push)
    try {
      final isShorebird = _shorebirdCodePush.isShorebirdAvailable();
      if (isShorebird) {
        final patchNumber = await _shorebirdCodePush.currentPatchNumber();
        debugPrint('[Shorebird] Parche actual: ${patchNumber ?? "ninguno (APK base)"}');

        // Comprobamos si ya hay un parche descargado listo para instalarse al reiniciar
        final readyToInstall = await _shorebirdCodePush.isNewPatchReadyToInstall();
        if (readyToInstall) {
          onStatus('⚡ Actualización lista. Reiniciá la app para aplicar la nueva versión.', true);
          return;
        }

        // Comprobamos si hay un parche nuevo en la nube disponible para descargar
        final isUpdateAvailable = await _shorebirdCodePush.isNewPatchAvailableForDownload();
        if (isUpdateAvailable) {
          onStatus('📥 Descargando mejoras en segundo plano...', false);
          await _shorebirdCodePush.downloadUpdateIfAvailable();
          
          final ahoraListo = await _shorebirdCodePush.isNewPatchReadyToInstall();
          if (ahoraListo) {
            onStatus('✅ ¡Listo! Nueva versión descargada. Reiniciá la app para activarla.', true);
          }
          return;
        }
      } else {
        debugPrint('[Shorebird] No está activo (ejecutando en modo normal / no-shorebird).');
      }
    } catch (e) {
      debugPrint('[Shorebird] Error al verificar actualizaciones: $e');
    }

    // 2. Verificación de versión mayor del APK desde el servidor de Chefsy (Fallback opcional)
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersionCode = int.tryParse(packageInfo.buildNumber) ?? 1;

      final res = await http.get(
        Uri.parse('https://chefsy.xyz/api/public/app-version'),
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final int serverVersionCode = data['versionCode'] ?? 1;
        final String apkUrl = data['apkUrl'] ?? 'https://chefsy.xyz/cadeteria';
        final String notas = data['notas'] ?? 'Mejoras y correcciones en la aplicación.';

        if (serverVersionCode > currentVersionCode) {
          onStatus('🚀 Nueva versión mayor disponible ($apkUrl)|$notas', false);
        }
      }
    } catch (_) {
      // Ignoramos errores de red silenciosamente
    }
  }
}
