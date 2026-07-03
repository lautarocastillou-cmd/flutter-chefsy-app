import 'dart:async';
import 'dart:convert';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String apiUrl = 'https://chefsy.xyz/api/public/ubicacion';
const String secretToken = 'chefsy_expo_secure_track_99XQ';

void initForegroundTask() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'chefsy_gps_tracking',
      channelName: 'Rastreo GPS Chefsy',
      channelDescription: 'GPS activo. Podés guardar el celular en el bolsillo.',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: true,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(4000), // Bucle de 4s para reportar simulación y checkouts
      autoRunOnBoot: false,
      allowWakeLock: true,
    ),
  );
}

@pragma('vm:entry-point')
class GpsTaskHandler extends TaskHandler {
  SharedPreferences? _prefs;
  bool _ocupado = false;
  StreamSubscription<Position>? _positionStreamSub;
  DateTime? _ultimoReporteTime;
  bool _simulacionActiva = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _simulacionActiva = _prefs?.getBool('simulacion_activa') ?? false;

      if (!_simulacionActiva) {
        // --- MODO REAL: Suscripción reactiva al stream del GPS ---
        final positionStream = Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high, // Consumo optimizado (no bestForNavigation)
            distanceFilter: 10,             // Notificar si se desplaza al menos 10 metros
          ),
        );

        _positionStreamSub = positionStream.listen(
          (Position position) {
            _enviarUbicacionReal(position);
          },
          onError: (_) {},
        );
      }
    } catch (_) {}
  }

  @override
  void onRepeatEvent(DateTime timestamp) async {
    if (_ocupado) return;

    try {
      // Recargar preferencias por si cambia el estado dinámicamente
      final simActiva = _prefs?.getBool('simulacion_activa') ?? false;
      
      if (simActiva) {
        _ocupado = true;
        
        final cadeteId = _prefs?.getString('cadete_id');
        if (cadeteId == null || cadeteId.isEmpty) return;

        final double lat = _prefs?.getDouble('sim_lat') ?? -32.8894;
        final double lng = _prefs?.getDouble('sim_lng') ?? -68.8458;

        // Transmitir ubicación simulada
        await http.post(
          Uri.parse(apiUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $secretToken',
          },
          body: jsonEncode({
            'cadeteId': cadeteId,
            'lat': lat,
            'lng': lng,
            'accuracy': 5.0, // Alta precisión simulada
            'speed': 25.0,   // Velocidad simulada de moto
            'heading': 90.0, // Dirección simulada (Este)
          }),
        ).timeout(const Duration(seconds: 4));
      }
    } catch (_) {
    } finally {
      _ocupado = false;
    }
  }

  void _enviarUbicacionReal(Position position) async {
    final ahora = DateTime.now();
    // Throttling: máximo un reporte cada 4 segundos para evitar spam al servidor
    if (_ultimoReporteTime != null &&
        ahora.difference(_ultimoReporteTime!) < const Duration(seconds: 4)) {
      return;
    }
    _ultimoReporteTime = ahora;

    if (_ocupado) return;
    _ocupado = true;

    try {
      final cadeteId = _prefs?.getString('cadete_id');
      if (cadeteId == null || cadeteId.isEmpty) return;

      // Filtrado estricto de drifts
      if (position.accuracy > 35) return;

      await http.post(
        Uri.parse(apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $secretToken',
        },
        body: jsonEncode({
          'cadeteId': cadeteId,
          'lat': position.latitude,
          'lng': position.longitude,
          'accuracy': position.accuracy,
          'speed': position.speed >= 0 ? position.speed : 0,
          'heading': position.heading >= 0 ? position.heading : 0,
        }),
      ).timeout(const Duration(seconds: 4));
    } catch (_) {
    } finally {
      _ocupado = false;
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    await _positionStreamSub?.cancel();
  }
}

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(GpsTaskHandler());
}
