import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import 'api_service.dart';

class UpdaterService {
  final ShorebirdUpdater _shorebirdUpdater = ShorebirdUpdater();

  /// Verifica automáticamente si hay parches de Shorebird o nuevas versiones de APK disponibles.
  /// Llama a [onStatus] con un mensaje descriptivo y un booleano indicando si está listo para reiniciar.
  Future<void> verificarYDescargarActualizaciones({
    required Function(String mensaje, bool listoParaReiniciar) onStatus,
  }) async {
    // 1. Verificación en vivo mediante Shorebird (Code Push v2)
    try {
      if (_shorebirdUpdater.isAvailable) {
        final currentPatch = await _shorebirdUpdater.readCurrentPatch();
        debugPrint('[Shorebird] Parche actual: ${currentPatch?.number ?? "ninguno (APK base)"}');

        final status = await _shorebirdUpdater.checkForUpdate();
        if (status == UpdateStatus.restartRequired) {
          onStatus('⚡ Actualización lista. Reiniciá la app para aplicar la nueva versión.', true);
          return;
        } else if (status == UpdateStatus.outdated) {
          onStatus('📥 Descargando mejoras en segundo plano...', false);
          await _shorebirdUpdater.update();
          onStatus('✅ ¡Listo! Nueva versión descargada. Reiniciá la app para activarla.', true);
          return;
        }
      } else {
        debugPrint('[Shorebird] No está activo en este entorno de compilación.');
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
