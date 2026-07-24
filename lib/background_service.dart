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

  // Variables en memoria para joystick en tiempo real
  double? _liveSimLat;
  double? _liveSimLng;

  // --- Lógica de Auto-Pausa en el local ---
  // Modo pausa: el cadete no se movió, dejamos de reportar al servidor.
  bool _enModoPausa = false;
  // Punto donde detectamos que se detuvo.
  Position? _posicionDetencion;
  // Marca de tiempo desde cuando está quieto.
  DateTime? _tiempoDetenido;

  // Umbrales de comportamiento
  static const double _metrosParaPausarRastreo = 30.0;   // Si se mueve menos de esto → considera que está quieto
  static const double _metrosParaReanudarRastreo = 80.0;  // Si se aleja más de esto del punto de pausa → reanuda
  static const Duration _tiempoSinMovimientoParaPausar = Duration(minutes: 2); // Tiempo quieto antes de pausar

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _simulacionActiva = _prefs?.getBool('simulacion_activa') ?? false;

      if (!_simulacionActiva) {
        final modoAhorro = _prefs?.getBool('modo_ahorro') ?? false;

        final positionStream = Geolocator.getPositionStream(
          locationSettings: LocationSettings(
            accuracy: modoAhorro ? LocationAccuracy.low : LocationAccuracy.high,
            distanceFilter: modoAhorro ? 60 : 15,
          ),
        );

        _positionStreamSub = positionStream.listen(
          (Position position) {
            _procesarPosicion(position);
          },
          onError: (_) {},
        );
      }
    } catch (_) {}
  }

  /// Evalúa la posición recibida y decide si reportarla o pausar.
  void _procesarPosicion(Position position) {
    // Si estamos en modo pausa, verificar si el cadete se alejó suficiente para reanudar
    if (_enModoPausa) {
      if (_posicionDetencion != null) {
        final distanciaDesdeDetencion = Geolocator.distanceBetween(
          _posicionDetencion!.latitude,
          _posicionDetencion!.longitude,
          position.latitude,
          position.longitude,
        );

        if (distanciaDesdeDetencion >= _metrosParaReanudarRastreo) {
          // ¡El cadete se movió! Reanudamos el rastreo
          _enModoPausa = false;
          _posicionDetencion = null;
          _tiempoDetenido = null;
          FlutterForegroundTask.updateService(
            notificationTitle: '🛵 Chefsy Cadetería',
            notificationText: 'GPS activo. Transmitiendo ubicación.',
          );
          _enviarUbicacionReal(position);
        }
        // Si no se alejó suficiente, seguimos en pausa (no reportamos)
      }
      return;
    }

    // --- Modo activo: evaluar si el cadete está quieto ---
    if (_posicionDetencion != null) {
      final distanciaActual = Geolocator.distanceBetween(
        _posicionDetencion!.latitude,
        _posicionDetencion!.longitude,
        position.latitude,
        position.longitude,
      );

      if (distanciaActual < _metrosParaPausarRastreo) {
        // Sigue en el mismo lugar, actualizar tiempo
        _tiempoDetenido ??= DateTime.now();
        final tiempoQuieto = DateTime.now().difference(_tiempoDetenido!);

        if (tiempoQuieto >= _tiempoSinMovimientoParaPausar) {
          // Lleva 3+ minutos quieto → pausar reportes
          _enModoPausa = true;
          FlutterForegroundTask.updateService(
            notificationTitle: '🛵 Chefsy — En espera',
            notificationText: 'GPS pausado. Se reanudará al moverte.',
          );
          return;
        }
      } else {
        // Se movió, resetear el contador
        _posicionDetencion = position;
        _tiempoDetenido = null;
      }
    } else {
      // Primera posición recibida
      _posicionDetencion = position;
    }

    // Reportar normalmente
    _enviarUbicacionReal(position);
  }

  @override
  void onReceiveData(Object data) {
    if (data is String) {
      try {
        final mapa = jsonDecode(data);
        if (mapa['sim_lat'] != null && mapa['sim_lng'] != null) {
          _liveSimLat = (mapa['sim_lat'] as num).toDouble();
          _liveSimLng = (mapa['sim_lng'] as num).toDouble();
        }
      } catch (_) {}
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) async {
    if (_ocupado) return;

    try {
      final simActiva = _prefs?.getBool('simulacion_activa') ?? false;
      
      if (simActiva) {
        _ocupado = true;
        
        final cadeteId = _prefs?.getString('cadete_id');
        if (cadeteId == null || cadeteId.isEmpty) return;

        final double lat = _liveSimLat ?? _prefs?.getDouble('sim_lat') ?? -32.8894;
        final double lng = _liveSimLng ?? _prefs?.getDouble('sim_lng') ?? -68.8458;

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
            'accuracy': 5.0,
            'speed': 25.0,
            'heading': 90.0,
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
    if (_ultimoReporteTime != null &&
        ahora.difference(_ultimoReporteTime!) < const Duration(seconds: 12)) {
      return;
    }
    _ultimoReporteTime = ahora;

    if (_ocupado) return;
    _ocupado = true;

    try {
      final cadeteId = _prefs?.getString('cadete_id');
      if (cadeteId == null || cadeteId.isEmpty) return;

      if (position.accuracy > 100) return;

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
