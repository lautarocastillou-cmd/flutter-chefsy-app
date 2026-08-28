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
      channelName: 'Rastreo y Pedidos Chefsy',
      channelDescription: 'Avisos de nuevos pedidos y GPS activo.',
      channelImportance: NotificationChannelImportance.HIGH,
      priority: NotificationPriority.HIGH,
      playSound: true,
      enableVibration: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: true,
      playSound: true,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(4000), // cada 4 seg
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
  Position? _ultimaPosicionValida;
  bool _simulacionActiva = false;
  final Battery _battery = Battery();

  // Variables en memoria para joystick en tiempo real
  double? _liveSimLat;
  double? _liveSimLng;

  // Control de pedidos en segundo plano
  int _ticksChequeoPedidos = 0;
  Set<String> _pedidosConocidosIds = {};

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _simulacionActiva = _prefs?.getBool('simulacion_activa') ?? false;

      // Cargar lista inicial de pedidos para no notificar pedidos ya existentes al abrir
      _verificarNuevosPedidosEnSegundoPlano(esInicial: true);

      if (!_simulacionActiva) {
        // 1. Obtener y enviar de inmediato la primera posición y batería
        try {
          final initialPos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 4),
          );
          _ultimaPosicionValida = initialPos;
          _enviarUbicacionReal(initialPos);
        } catch (_) {
          try {
            final lastKnown = await Geolocator.getLastKnownPosition();
            if (lastKnown != null) {
              _ultimaPosicionValida = lastKnown;
              _enviarUbicacionReal(lastKnown);
            }
          } catch (_) {}
        }

        // 2. Escuchar cambios continuos de posición con filtro sensible
        final positionStream = Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          ),
        );

        _positionStreamSub = positionStream.listen(
          (Position position) {
            _ultimaPosicionValida = position;
            _enviarUbicacionReal(position);
          },
          onError: (_) {},
        );
      } else {
        _enviarUbicacionSimulada();
      }
    } catch (_) {}
  }

  /// Verifica si hay pedidos recién asignados mientras la app corre en segundo plano
  Future<void> _verificarNuevosPedidosEnSegundoPlano({bool esInicial = false}) async {
    try {
      final cadeteId = _prefs?.getString('cadete_id');
      if (cadeteId == null || cadeteId.isEmpty) return;

      final res = await http.get(
        Uri.parse('https://chefsy.xyz/api/public/pedidos?cadeteId=$cadeteId'),
        headers: {'Authorization': 'Bearer $secretToken'},
      ).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = (data['pedidos'] as List? ?? [])
            .where((p) => p['estado'] != 'entregado' && p['estado'] != 'cancelado')
            .toList();

        final currentIds = list.map((p) => p['id'].toString()).toSet();

        if (!esInicial && _pedidosConocidosIds.isNotEmpty) {
          final nuevos = list.where((p) => !_pedidosConocidosIds.contains(p['id'].toString())).toList();
          if (nuevos.isNotEmpty) {
            final nuevo = nuevos.first;
            final cliente = nuevo['cliente']?.toString() ?? 'Cliente';
            final dir = nuevo['direccion']?.toString() ?? 'Domicilio';
            
            FlutterForegroundTask.updateService(
              notificationTitle: '🛵 ¡Nuevo pedido asignado!',
              notificationText: '$cliente • $dir',
            );
          }
        }
        _pedidosConocidosIds = currentIds;
      }
    } catch (_) {}
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
    // 1. Chequeo de nuevos pedidos asignados cada ~8 segundos (2 ticks)
    _ticksChequeoPedidos++;
    if (_ticksChequeoPedidos >= 2) {
      _ticksChequeoPedidos = 0;
      _verificarNuevosPedidosEnSegundoPlano();
    }

    if (_ocupado) return;

    final simActiva = _simulacionActiva || (_prefs?.getBool('simulacion_activa') ?? false);

    if (simActiva) {
      _enviarUbicacionSimulada();
    } else {
      // Modo Real: Heartbeat periódico cada 15 segundos si está quieto en el local
      final ahora = DateTime.now();
      if (_ultimoReporteTime == null ||
          ahora.difference(_ultimoReporteTime!) >= const Duration(seconds: 15)) {
        if (_ultimaPosicionValida != null) {
          _enviarUbicacionReal(_ultimaPosicionValida!, forzar: true);
        } else {
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
  }

  void _enviarUbicacionSimulada() async {
    if (_ocupado) return;
    _ocupado = true;

    try {
      _prefs ??= await SharedPreferences.getInstance();
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
          'accuracy': 5.0,
          'speed': 25.0,
          'heading': 90.0,
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
      _prefs ??= await SharedPreferences.getInstance();
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

/// Envía inmediatamente la ubicación GPS actual y batería al servidor.
Future<bool> reportarUbicacionAhora([String? idCadete]) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final cadeteId = idCadete ?? prefs.getString('cadete_id');
    if (cadeteId == null || cadeteId.isEmpty) return false;

    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 4),
      );
    } catch (_) {
      position = await Geolocator.getLastKnownPosition();
    }

    if (position == null) return false;

    int? batteryLevel;
    try {
      batteryLevel = await Battery().batteryLevel;
    } catch (_) {}

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
        if (batteryLevel != null) 'batteryLevel': batteryLevel,
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
