import 'dart:async';
import 'dart:convert';
import 'package:battery_plus/battery_plus.dart';
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
      eventAction: ForegroundTaskEventAction.repeat(4000),
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
  final Battery _battery = Battery();

  // Última posición válida conocida
  Position? _ultimaPosicionValida;

  // Variables en memoria para joystick en tiempo real
  double? _liveSimLat;
  double? _liveSimLng;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _simulacionActiva = _prefs?.getBool('simulacion_activa') ?? false;

      // Intentar obtener última posición conocida al arrancar
      try {
        _ultimaPosicionValida = await Geolocator.getLastKnownPosition();
        if (_ultimaPosicionValida != null && !_simulacionActiva) {
          _enviarUbicacionReal(_ultimaPosicionValida!);
        }
      } catch (_) {}

      // Iniciar stream de GPS con filtro sensible (5 metros)
      final positionStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      );

      _positionStreamSub = positionStream.listen(
        (Position position) {
          _procesarPosicion(position);
        },
        onError: (_) {},
      );

      // Si es simulador, disparar primer envío simulado
      if (_simulacionActiva) {
        _enviarUbicacionSimulada();
      }
    } catch (_) {}
  }

  void _procesarPosicion(Position position) {
    if (_simulacionActiva) return;
    _ultimaPosicionValida = position;
    _enviarUbicacionReal(position);
  }

  @override
  void onReceiveData(Object data) {
    if (data is String) {
      try {
        final mapa = jsonDecode(data);
        if (mapa.containsKey('simulacion_activa')) {
          _simulacionActiva = mapa['simulacion_activa'] == true;
        }
        if (mapa['sim_lat'] != null && mapa['sim_lng'] != null) {
          _liveSimLat = (mapa['sim_lat'] as num).toDouble();
          _liveSimLng = (mapa['sim_lng'] as num).toDouble();
          _simulacionActiva = true;
          _enviarUbicacionSimulada();
        }
      } catch (_) {}
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) async {
    final ahora = DateTime.now();

    // 1. MODO SIMULACIÓN: reportar cada 4 segundos la posición del joystick
    if (_simulacionActiva) {
      _enviarUbicacionSimulada();
      return;
    }

    // 2. MODO REAL: Heartbeat cada 15 segundos si el cadete está quieto
    // Esto garantiza que Torre de Control SIEMPRE lo mantenga ONLINE y con su batería actualizada
    final tiempoDesdeUltimoReporte = _ultimoReporteTime == null
        ? const Duration(seconds: 999)
        : ahora.difference(_ultimoReporteTime!);

    if (tiempoDesdeUltimoReporte >= const Duration(seconds: 15)) {
      if (_ultimaPosicionValida != null) {
        _enviarUbicacionReal(_ultimaPosicionValida!, forzar: true);
      } else {
        // Intentar consultar posición actual
        try {
          final pos = await Geolocator.getLastKnownPosition() ??
              await Geolocator.getCurrentPosition(
                desiredAccuracy: LocationAccuracy.medium,
                timeLimit: const Duration(seconds: 3),
              );
          _ultimaPosicionValida = pos;
          _enviarUbicacionReal(pos, forzar: true);
        } catch (_) {}
      }
    }
  }

  void _enviarUbicacionSimulada() async {
    if (_ocupado) return;
    _ocupado = true;

    try {
      final cadeteId = _prefs?.getString('cadete_id');
      if (cadeteId == null || cadeteId.isEmpty) return;

      final double lat = _liveSimLat ?? _prefs?.getDouble('sim_lat') ?? -28.46281;
      final double lng = _liveSimLng ?? _prefs?.getDouble('sim_lng') ?? -65.77850;

      int? batteryLevel;
      try {
        batteryLevel = await _battery.batteryLevel;
      } catch (_) {}

      _ultimoReporteTime = DateTime.now();

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
          'accuracy': 3.0,
          'speed': 20.0,
          'heading': 90.0,
          'gps_activo': true,
          if (batteryLevel != null) 'batteryLevel': batteryLevel,
        }),
      ).timeout(const Duration(seconds: 4));
    } catch (_) {
    } finally {
      _ocupado = false;
    }
  }

  void _enviarUbicacionReal(Position position, {bool forzar = false}) async {
    final ahora = DateTime.now();
    if (!forzar &&
        _ultimoReporteTime != null &&
        ahora.difference(_ultimoReporteTime!) < const Duration(seconds: 3)) {
      return;
    }
    _ultimoReporteTime = ahora;

    if (_ocupado) return;
    _ocupado = true;

    try {
      final cadeteId = _prefs?.getString('cadete_id');
      if (cadeteId == null || cadeteId.isEmpty) return;

      int? batteryLevel;
      try {
        batteryLevel = await _battery.batteryLevel;
      } catch (_) {}

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
          'gps_activo': true,
          if (batteryLevel != null) 'batteryLevel': batteryLevel,
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

/// Envía inmediatamente la ubicación GPS actual al servidor.
/// Útil al presionar "COMENZAR VIAJE" para que los clientes vean el mapa al instante.
Future<bool> reportarUbicacionAhora() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final cadeteId = prefs.getString('cadete_id');
    if (cadeteId == null || cadeteId.isEmpty) return false;

    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    if (position.accuracy > 45) return false;

    final res = await http.post(
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
    ).timeout(const Duration(seconds: 5));

    return res.statusCode == 200;
  } catch (_) {
    return false;
  }
}

@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(GpsTaskHandler());
}
