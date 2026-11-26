import 'dart:async';
import 'dart:convert';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String apiUrl = 'https://chefsy.xyz/api/public/ubicacion';
const String secretToken = 'chefsy_expo_secure_track_99XQ';

// En movimiento se reporta cada 2.5s y 3m para un tracking fluido en vivo.
// Estando detenido, entra en reposo enviando solo un heartbeat cada 60s para ahorrar batería y cuota.
const Duration intervaloMinimoMovimiento = Duration(milliseconds: 2500);
const Duration heartbeatGpsQuieto = Duration(seconds: 60);
const Duration watchdogStreamStale = Duration(seconds: 16);
const double distanciaMinimaMovimientoMetros = 3.0;

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
  bool _sondeoGpsEnCurso = false;
  StreamSubscription<Position>? _positionStreamSub;
  DateTime? _ultimoReporteTime;
  DateTime? _ultimoFixStreamTime;
  DateTime? _ultimoSondeoWatchdogTime;
  Position? _ultimaPosicionValida;
  Position? _ultimaPosicionEnviada;
  double? _ultimaLatitudSimuladaEnviada;
  double? _ultimaLongitudSimuladaEnviada;
  bool _simulacionActiva = false;
  final Battery _battery = Battery();

  // Buffer local en memoria para tolerancia a cortes de señal 4G (Cola Offline)
  final List<Map<String, dynamic>> _bufferPuntos = [];

  // Variables en memoria para joystick en tiempo real
  double? _liveSimLat;
  double? _liveSimLng;

  // Control de pedidos en segundo plano
  int _ticksChequeoPedidos = 0;
  bool _turnoActivoUltimo = true;
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
          _ultimoFixStreamTime = DateTime.now();
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

        // 2. Escuchar cambios continuos de posición con configuración Android activa
        _iniciarStreamPosicion();
      } else {
        _enviarUbicacionSimulada();
      }
    } catch (_) {}
  }

  /// Inicia o reinicia la suscripción al stream continuo de GPS.
  /// En Android usa AndroidSettings con intervalDuration explícito para que
  /// FusedLocationProvider no duerma el rastreo al frenar con pantalla apagada.
  void _iniciarStreamPosicion() {
    _positionStreamSub?.cancel();
    _positionStreamSub = null;

    final LocationSettings settings = defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 3,
            intervalDuration: const Duration(seconds: 3),
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 3,
          );

    final positionStream = Geolocator.getPositionStream(locationSettings: settings);

    _positionStreamSub = positionStream.listen(
      (Position position) {
        _ultimaPosicionValida = position;
        _ultimoFixStreamTime = DateTime.now();
        _enviarUbicacionReal(position);
      },
      onError: (_) {
        // Si Android corta el stream (pérdida momentánea de señal/Doze),
        // lo marcamos nulo para que el watchdog lo recupere automáticamente.
        _positionStreamSub?.cancel();
        _positionStreamSub = null;
      },
      onDone: () {
        _positionStreamSub = null;
      },
      cancelOnError: false,
    );
  }

  /// Watchdog anti-congelamiento: si el stream lleva >16s sin emitir un fix nuevo,
  /// fuerza una lectura fresca del chip GPS; si el cadete se desplazó mientras
  /// el stream estaba dormido, envía la posición nueva y reinicia el stream.
  Future<void> _sondearGpsFrescoSiCongelado() async {
    if (_sondeoGpsEnCurso) return;
    final ahora = DateTime.now();

    if (_positionStreamSub == null) {
      _iniciarStreamPosicion();
    }

    final streamSinDatos = _ultimoFixStreamTime == null ||
        ahora.difference(_ultimoFixStreamTime!) >= watchdogStreamStale;
    if (!streamSinDatos) return;

    final puedeSondear = _ultimoSondeoWatchdogTime == null ||
        ahora.difference(_ultimoSondeoWatchdogTime!) >= watchdogStreamStale;
    if (!puedeSondear) return;

    _sondeoGpsEnCurso = true;
    _ultimoSondeoWatchdogTime = ahora;

    try {
      final posFresca = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 6),
      );

      final anterior = _ultimaPosicionValida;
      final seDesplazoSinStream = anterior != null &&
          Geolocator.distanceBetween(
                anterior.latitude,
                anterior.longitude,
                posFresca.latitude,
                posFresca.longitude,
              ) >=
              8.0;

      _ultimaPosicionValida = posFresca;
      _ultimoFixStreamTime = DateTime.now();
      _enviarUbicacionReal(posFresca, forzar: seDesplazoSinStream);

      // El cadete se movió y el stream no lo había reportado: reiniciar suscripción Android
      if (seDesplazoSinStream) {
        _iniciarStreamPosicion();
      }
    } catch (_) {
      // Si el fix activo falló (ej. bajo techo), intentamos al menos re-suscribir si murió
      if (_positionStreamSub == null) {
        _iniciarStreamPosicion();
      }
    } finally {
      _sondeoGpsEnCurso = false;
    }
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
        if (data is Map && data.containsKey('turno_activo')) {
          _turnoActivoUltimo = data['turno_activo'] == true;
        }
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
      if (data == 'apagar_gps' || data.contains('"comando":"apagar_gps"') || data.contains('"apagar_gps"')) {
        _positionStreamSub?.cancel();
        _positionStreamSub = null;
        FlutterForegroundTask.stopService();
        return;
      }
      try {
        final mapa = jsonDecode(data);
        if (mapa['comando'] == 'apagar_gps') {
          _positionStreamSub?.cancel();
          _positionStreamSub = null;
          FlutterForegroundTask.stopService();
          return;
        }
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
    // 0. Si el usuario desactivó el rastreo desde la app, no emitir ningún reporte y detener servicio
    _prefs ??= await SharedPreferences.getInstance();
    final rastreoHabilitado = _prefs?.getBool('rastreo_habilitado') ?? true;
    if (!rastreoHabilitado) {
      _positionStreamSub?.cancel();
      _positionStreamSub = null;
      FlutterForegroundTask.stopService();
      return;
    }

    // 1. Chequeo inteligente de nuevos pedidos asignados:
    // Si el turno está abierto, chequea cada ~24 segundos (6 ticks de 4s).
    // Si el turno está cerrado, entra en ahorro extremo chequeando cada ~100s (25 ticks).
    final int ticksNecesarios = _turnoActivoUltimo ? 6 : 25;
    _ticksChequeoPedidos++;
    if (_ticksChequeoPedidos >= ticksNecesarios) {
      _ticksChequeoPedidos = 0;
      _verificarNuevosPedidosEnSegundoPlano();
    }

    if (_ocupado) return;

    final simActiva = _simulacionActiva || (_prefs?.getBool('simulacion_activa') ?? false);

    if (simActiva) {
      _enviarUbicacionSimulada();
    } else {
      // 1. Watchdog: detecta si Android durmió o cortó el stream GPS tras frenar en una entrega
      await _sondearGpsFrescoSiCongelado();

      // 2. Revaluar el último punto en cada tick para despachar buffer o heartbeat quieto
      if (_ultimaPosicionValida != null) {
        _enviarUbicacionReal(_ultimaPosicionValida!);
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
      final ahora = DateTime.now();
      final tiempoDesdeReporte = _ultimoReporteTime == null
          ? heartbeatGpsQuieto
          : ahora.difference(_ultimoReporteTime!);
      final distanciaDesdeUltimoEnvio = _ultimaLatitudSimuladaEnviada == null ||
              _ultimaLongitudSimuladaEnviada == null
          ? double.infinity
          : Geolocator.distanceBetween(
              _ultimaLatitudSimuladaEnviada!,
              _ultimaLongitudSimuladaEnviada!,
              lat,
              lng,
            );
      final seMovio = distanciaDesdeUltimoEnvio >= distanciaMinimaMovimientoMetros;
      if (seMovio
          ? tiempoDesdeReporte < intervaloMinimoMovimiento
          : tiempoDesdeReporte < heartbeatGpsQuieto) {
        return;
      }

      int? batteryLevel;
      try {
        batteryLevel = await _battery.batteryLevel;
      } catch (_) {}

      _ultimoReporteTime = ahora;

      final res = await http.post(
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
      if (res.statusCode == 200) {
        _ultimaLatitudSimuladaEnviada = lat;
        _ultimaLongitudSimuladaEnviada = lng;
      }
    } catch (_) {
    } finally {
      _ocupado = false;
    }
  }

  void _encolarPuntoSiCorresponde(Position position, DateTime timestamp) {
    final ultimo = _bufferPuntos.isNotEmpty ? _bufferPuntos.last : null;
    final referencia = ultimo ?? (_ultimaPosicionEnviada == null
        ? null
        : {
            'lat': _ultimaPosicionEnviada!.latitude,
            'lng': _ultimaPosicionEnviada!.longitude,
          });
    if (referencia != null && referencia['lat'] is num && referencia['lng'] is num) {
      final distancia = Geolocator.distanceBetween(
        (referencia['lat'] as num).toDouble(),
        (referencia['lng'] as num).toDouble(),
        position.latitude,
        position.longitude,
      );
      if (distancia < distanciaMinimaMovimientoMetros) return;
    }

    _bufferPuntos.add({
      'lat': position.latitude,
      'lng': position.longitude,
      'accuracy': position.accuracy,
      'speed': position.speed >= 0 ? position.speed : 0,
      'heading': position.heading >= 0 ? position.heading : 0,
      't': timestamp.toUtc().toIso8601String(),
    });
    if (_bufferPuntos.length > 50) {
      _bufferPuntos.removeAt(0);
    }
  }

  void _enviarUbicacionReal(Position position, {bool forzar = false}) async {
    final ahora = DateTime.now();
    _encolarPuntoSiCorresponde(position, ahora);

    final ultimoReporte = _ultimoReporteTime;
    final tiempoDesdeReporte = ultimoReporte == null
        ? heartbeatGpsQuieto
        : ahora.difference(ultimoReporte);
    final ultimaPosicion = _ultimaPosicionEnviada;
    final distanciaDesdeUltimoEnvio = ultimaPosicion == null
        ? double.infinity
        : Geolocator.distanceBetween(
            ultimaPosicion.latitude,
            ultimaPosicion.longitude,
            position.latitude,
            position.longitude,
          );
    final seMovio = distanciaDesdeUltimoEnvio >= distanciaMinimaMovimientoMetros;

    // No se pierde ningún punto relevante: los puntos intermedios quedan en
    // _bufferPuntos y se envían junto con el próximo movimiento/heartbeat.
    final puedeEnviarPorMovimiento = tiempoDesdeReporte >= intervaloMinimoMovimiento &&
        (seMovio || _bufferPuntos.isNotEmpty);
    final puedeEnviarHeartbeat = tiempoDesdeReporte >= heartbeatGpsQuieto;
    if (!forzar && !puedeEnviarPorMovimiento && !puedeEnviarHeartbeat) return;

    if (_ocupado) return;
    _ocupado = true;
    _ultimoReporteTime = ahora;

    try {
      _prefs ??= await SharedPreferences.getInstance();
      final rastreoHabilitado = _prefs?.getBool('rastreo_habilitado') ?? true;
      if (!rastreoHabilitado) {
        _positionStreamSub?.cancel();
        _positionStreamSub = null;
        FlutterForegroundTask.stopService();
        return;
      }

      final cadeteId = _prefs?.getString('cadete_id');
      if (cadeteId == null || cadeteId.isEmpty) return;

      int? batteryLevel;
      try {
        batteryLevel = await _battery.batteryLevel;
      } catch (_) {}

      final rafagaAEnviar = List<Map<String, dynamic>>.from(_bufferPuntos);

      final response = await http.post(
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
          if (rafagaAEnviar.isNotEmpty) 'bufferPuntos': rafagaAEnviar,
        }),
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        // Al confirmar entrega exitosa por el servidor, remover solo los puntos enviados
        // evitando descartar puntos nuevos capturados mientras la petición estuvo en vuelo
        if (_bufferPuntos.length >= rafagaAEnviar.length) {
          _bufferPuntos.removeRange(0, rafagaAEnviar.length);
        } else {
          _bufferPuntos.clear();
        }

        _ultimaPosicionEnviada = position;

        final data = jsonDecode(response.body);
        if (data['comando'] == 'apagar_gps' || data['gps_activo'] == false) {
          FlutterForegroundTask.sendDataToMain('apagar_gps');
          await FlutterForegroundTask.stopService();
        }
      }
    } catch (_) {
      // En caso de corte de señal 4G o timeout, _bufferPuntos permanece intacto
      // para enviar la ráfaga completa en cuanto se recupere la conexión.
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
