import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String apiUrl = 'https://chefsy.xyz/api/public/ubicacion';
const String expoSecretToken = 'chefsy_expo_secure_track_99XQ';

// Bandera global para evitar llamadas concurrentes al GPS en el mismo Isolate
bool _gpsOcupado = false;

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'chefsy_tracking',
      initialNotificationTitle: '🛵 Chefsy Cadetería',
      initialNotificationContent: 'GPS activo. Podes guardar el celular en el bolsillo.',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
    ),
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  // Garantizar que el motor de Flutter esté listo en este Isolate
  DartPluginRegistrant.ensureInitialized();

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Pre-cargar SharedPreferences UNA SOLA VEZ al iniciar el servicio.
  // Evita el PlatformException de Xiaomi/Samsung al llamarlo en cada tick.
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (e) {
    // Si falla la inicialización de prefs, detener el servicio de forma ordenada
    service.stopSelf();
    return;
  }

  Timer.periodic(const Duration(seconds: 7), (timer) async {
    // Evitar llamadas concurrentes al GPS si la anterior todavía no terminó
    if (_gpsOcupado) return;
    _gpsOcupado = true;

    try {
      final cadeteId = prefs?.getString('cadete_id');
      if (cadeteId == null || cadeteId.isEmpty) {
        _gpsOcupado = false;
        return;
      }

      // Verificar que el permiso de ubicación sigue activo antes de leer el GPS
      // (el usuario puede revocarlo desde Configuración mientras el servicio está corriendo)
      final permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied || permiso == LocationPermission.deniedForever) {
        _gpsOcupado = false;
        return;
      }

      // Timeout explícito de 10 segundos para no acumular llamadas colgadas
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
      } on TimeoutException {
        // GPS tardó demasiado (celular recién encendido, zona sin señal): saltar tick
        _gpsOcupado = false;
        return;
      }

      // Filtro anti-saltos: ignorar lecturas con precisión peor a 50 metros
      if (position.accuracy > 50) {
        _gpsOcupado = false;
        return;
      }

      await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $expoSecretToken',
        },
        body: jsonEncode({
          'cadeteId': cadeteId,
          'lat': position.latitude,
          'lng': position.longitude,
          'accuracy': position.accuracy,
          'speed': position.speed >= 0 ? position.speed : 0,
          'heading': position.heading >= 0 ? position.heading : 0,
        }),
      ).timeout(const Duration(seconds: 8));

      service.invoke('updatePosition', {
        'lat': position.latitude,
        'lng': position.longitude,
      });
    } catch (e) {
      // Silencioso: fallos de red, GPS no disponible, etc. no deben matar el servicio
    } finally {
      // SIEMPRE liberar la bandera aunque haya error para que el siguiente tick funcione
      _gpsOcupado = false;
    }
  });
}
