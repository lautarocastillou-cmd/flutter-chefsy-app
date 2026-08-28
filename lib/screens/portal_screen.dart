import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:restart_app/restart_app.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/pedido_model.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/tarjeta_pedido.dart';
import '../background_service.dart';
import '../services/updater_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
class PortalScreen extends StatefulWidget {
  final String cadeteId;
  final String cadeteNombre;
  final VoidCallback onLogout;

  const PortalScreen({
    super.key,
    required this.cadeteId,
    required this.cadeteNombre,
    required this.onLogout,
  });

  @override
  State<PortalScreen> createState() => _PortalScreenState();
}

class _PortalScreenState extends State<PortalScreen> {
  bool _estaRastreando = false;
  List<PedidoModel> _pedidosListos = [];
  bool _cargandoPedidos = false;
  String _ultimaUbicacionTexto = 'Esperando señal GPS...';
  Timer? _pollingTimer;
  RealtimeChannel? _pedidosChannel;
  bool _mostrarControlesSimulacion = false;
  bool _simulacionActiva = false;
  double _simLat = -28.46281; // Coordenadas reales del local Chefsy
  double _simLng = -65.77850;
  bool _modoAhorro = false;
  Timer? _joystickTimer;
  String _vistaActiva = 'activos';
  bool _alertasSonoras = true;
  int _ultimoCambioLocalMs = 0;
  final Set<String> _cambiandoEstadoIds = {};

  SharedPreferences? _prefs;

  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final UpdaterService _updaterService = UpdaterService();

  String? _mensajeActualizacion;
  bool _listoParaReiniciar = false;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
    _pollingTimer = Timer.periodic(
        const Duration(seconds: 15), (_) => _fetchPedidosSilencioso());
    _pedidosChannel = Supabase.instance.client
        .channel('public:pedidos:cadete_${widget.cadeteId}')
        .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'pedidos',
            callback: (payload) {
              _fetchPedidosSilencioso();
            })
        .subscribe();
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _pedidosChannel?.unsubscribe();
    _joystickTimer?.cancel();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    final isRunning = await FlutterForegroundTask.isRunningService;
    final simActiva = await _authService.isSimulacionActiva();
    final simCoords = await _authService.obtenerSimCoordenadas();
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;
    await prefs.setString('cadete_id', widget.cadeteId);

    setState(() {
      _estaRastreando = isRunning;
      _simulacionActiva = simActiva;
      _modoAhorro = prefs.getBool('modo_ahorro') ?? false;
      _alertasSonoras = true;
      _simLat = simCoords['lat']!;
      _simLng = simCoords['lng']!;
      if (isRunning) {
        _ultimaUbicacionTexto = simActiva
            ? 'Simulador activo: [$_simLat, $_simLng]'
            : 'Transmitiendo GPS...';
      } else {
        _ultimaUbicacionTexto = 'Rastreo pausado.';
      }
    });

    _fetchPedidos();
    _verificarActualizaciones();
  }

  Future<void> _verificarActualizaciones() async {
    await _updaterService.verificarYDescargarActualizaciones(
      onStatus: (mensaje, listo) {
        if (mounted) {
          setState(() {
            _mensajeActualizacion = mensaje;
            _listoParaReiniciar = listo;
          });
        }
      },
    );
  }

  Future<void> _aplicarActualizacionYReiniciar() async {
    try {
      // 1. Detener servicio en segundo plano para permitir que Android destruya el proceso anterior
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
      await Future.delayed(const Duration(milliseconds: 250));

      // 2. Reiniciar proceso nativo para cargar el nuevo parche de Shorebird
      await Restart.restartApp();
    } catch (_) {
      SystemNavigator.pop();
    }
  }

  Future<void> _toggleAlertas() async {
    final nuevo = !_alertasSonoras;
    await _prefs?.setBool('alertas_sonoras', nuevo);
    setState(() {
      _alertasSonoras = nuevo;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(nuevo
              ? '🔔 Alertas de nuevos pedidos ACTIVADAS'
              : '🔕 Alertas de nuevos pedidos SILENCIADAS')),
    );
  }

  Future<void> _cerrarSesion() async {
    if (_estaRastreando) {
      await _detenerRastreo();
    }
    await _authService.borrarSesion();
    widget.onLogout();
  }

  Future<bool> _verificarPermisosGps() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      return false;
    }
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  Future<void> _iniciarRastreo() async {
    final notifPerm = await FlutterForegroundTask.checkNotificationPermission();
    if (notifPerm != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    if (!_simulacionActiva) {
      final gpsOk = await _verificarPermisosGps();
      if (!gpsOk) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('❌ Necesitamos permiso de ubicación para rastrear.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }
    }

    try {
      await _prefs?.setString('cadete_id', widget.cadeteId);
      await FlutterForegroundTask.startService(
        serviceId: 888,
        notificationTitle: _simulacionActiva
            ? '🛠️ Chefsy GPS (SIMULADO)'
            : '🛵 Chefsy Cadetería',
        notificationText: _simulacionActiva
            ? 'Simulación activa: [$_simLat, $_simLng]'
            : 'GPS activo. Podés guardar el celular en el bolsillo.',
        callback: startCallback,
      );

      // Reporte inicial inmediato
      if (!_simulacionActiva) {
        reportarUbicacionAhora(widget.cadeteId);
      }

      if (mounted) {
        setState(() {
          _estaRastreando = true;
          _ultimaUbicacionTexto = _simulacionActiva
              ? 'Simulador activo: [$_simLat, $_simLng]'
              : 'Transmitiendo GPS...';
        });
      }

      // Disparar reporte HTTP inmediato al servidor para aparecer online en 0 segundos
      if (_simulacionActiva) {
        _apiService.reportarUbicacion(
          cadeteId: widget.cadeteId,
          lat: _simLat,
          lng: _simLng,
          gpsActivo: true,
        );
      } else {
        try {
          final pos = await Geolocator.getLastKnownPosition() ??
              await Geolocator.getCurrentPosition(
                desiredAccuracy: LocationAccuracy.medium,
                timeLimit: const Duration(seconds: 3),
              );
          _apiService.reportarUbicacion(
            cadeteId: widget.cadeteId,
            lat: pos.latitude,
            lng: pos.longitude,
            accuracy: pos.accuracy,
            gpsActivo: true,
          );
        } catch (_) {}
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al iniciar rastreo: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _detenerRastreo() async {
    // Notificar al servidor que el GPS fue apagado intencionalmente
    final cadeteId = _prefs?.getString('cadete_id') ?? '';
    if (cadeteId.isNotEmpty) {
      try {
        await http
            .post(
              Uri.parse('https://chefsy.xyz/api/public/ubicacion'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer chefsy_expo_secure_track_99XQ',
              },
              body: jsonEncode({'cadeteId': cadeteId, 'gps_activo': false}),
            )
            .timeout(const Duration(seconds: 4));
      } catch (_) {}
    }
    await FlutterForegroundTask.stopService();
    if (mounted) {
      setState(() {
        _estaRastreando = false;
        _ultimaUbicacionTexto = 'Rastreo pausado.';
      });
    }
  }

  void _toggleRastreo() {
    if (_estaRastreando) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('¿Detener rastreo?'),
          content: const Text(
              '¿Estás seguro de que querés dejar de compartir tu ubicación?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _detenerRastreo();
              },
              child: const Text('Detener'),
            ),
          ],
        ),
      );
    } else {
      _iniciarRastreo();
    }
  }

  Future<void> _fetchPedidos() async {
    setState(() => _cargandoPedidos = true);
    final list = await _apiService.fetchPedidos(widget.cadeteId);
    if (mounted) {
      setState(() {
        _pedidosListos = list;
        _cargandoPedidos = false;
      });
    }
  }

  Future<void> _fetchPedidosSilencioso() async {
    final list = await _apiService.fetchPedidos(widget.cadeteId);
    if (mounted) {
      if (_alertasSonoras) {
        final esCambioLocalReciente =
            (DateTime.now().millisecondsSinceEpoch - _ultimoCambioLocalMs) < 6000;
        if (!esCambioLocalReciente) {
          final oldIds = _pedidosListos.map((p) => p.id).toSet();
          final nuevos = list.where((p) => p.estado != 'entregado' && !oldIds.contains(p.id)).toList();
          if (_pedidosListos.isNotEmpty && nuevos.isNotEmpty) {
            SystemSound.play(SystemSoundType.alert);
            HapticFeedback.heavyImpact();
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.delivery_dining, color: Colors.white, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('🛵 ¡Nuevo Pedido Asignado!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text('${nuevos.first.cliente} • ${nuevos.first.direccion}', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                  ],
                ),
                backgroundColor: const Color(0xFF059669),
                duration: const Duration(seconds: 5),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
            );
          }
        }
      }
      setState(() {
        _pedidosListos = list;
      });
    }
  }

  Future<void> _cambiarEstadoPedido(String id, String nuevoEstado) async {
    if (!_estaRastreando) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.location_off_rounded, color: Colors.white, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text('⚠️ Debes activar el GPS para operar con este pedido.',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFDC2626),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          action: SnackBarAction(
            label: 'ACTIVAR',
            textColor: Colors.white,
            onPressed: _iniciarRastreo,
          ),
        ),
      );
      return;
    }

    if (_cambiandoEstadoIds.contains(id)) return;

    setState(() {
      _cambiandoEstadoIds.add(id);
      _ultimoCambioLocalMs = DateTime.now().millisecondsSinceEpoch;
      // Actualización optimista instantánea local (0ms lag)
      final idx = _pedidosListos.indexWhere((p) => p.id == id);
      if (idx != -1) {
        _pedidosListos[idx] = _pedidosListos[idx].copyWith(estado: nuevoEstado);
      }
    });

    try {
      final ok = await _apiService.cambiarEstadoPedido(id, nuevoEstado);
      if (ok) {
        if (nuevoEstado == 'en_camino') {
          // Disparar reporte inmediato de GPS al servidor
          reportarUbicacionAhora();
        }
        _fetchPedidosSilencioso();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo actualizar el estado.')),
          );
          _fetchPedidosSilencioso();
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _cambiandoEstadoIds.remove(id);
        });
      }
    }
  }

  Future<void> _abrirWhatsApp(String telefono, String cliente) async {
    var tel = telefono.replaceAll(RegExp(r'\D'), '');
    if (tel.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('El cliente no tiene teléfono registrado')),
      );
      return;
    }
    if (!tel.startsWith('549') && !tel.startsWith('54')) {
      if (tel.startsWith('0')) tel = tel.substring(1);
      tel = '549$tel';
    }
    final mensaje = "Hola, estoy en camino!";

    final uris = [
      Uri.parse(
          'whatsapp://send?phone=$tel&text=${Uri.encodeComponent(mensaje)}'),
      Uri.parse('https://wa.me/$tel?text=${Uri.encodeComponent(mensaje)}'),
    ];

    bool abierto = false;
    for (final u in uris) {
      try {
        if (await launchUrl(u, mode: LaunchMode.externalApplication)) {
          abierto = true;
          break;
        } else if (await launchUrl(u, mode: LaunchMode.platformDefault)) {
          abierto = true;
          break;
        }
      } catch (_) {
        // Continuar intentando
      }
    }

    if (!abierto && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No se pudo abrir WhatsApp en este dispositivo.')),
      );
    }
  }

  // --- Funciones del Simulador de GPS ---
  Future<void> _toggleSimulacion(bool activa) async {
    await _authService.setSimulacionActiva(activa);
    setState(() {
      _simulacionActiva = activa;
    });

    if (_estaRastreando) {
      FlutterForegroundTask.sendDataToTask(jsonEncode({
        'simulacion_activa': activa,
        if (activa) 'sim_lat': _simLat,
        if (activa) 'sim_lng': _simLng,
      }));
    }
  }

  Future<void> _actualizarSimCoords(double lat, double lng) async {
    await _authService.guardarSimCoordenadas(lat, lng);
    setState(() {
      _simLat = lat;
      _simLng = lng;
      if (_estaRastreando && _simulacionActiva) {
        _ultimaUbicacionTexto = 'Simulador activo: [$_simLat, $_simLng]';
      }
    });

    if (_estaRastreando && _simulacionActiva) {
      // 1. Enviar los datos instantáneamente al hilo de fondo en memoria
      FlutterForegroundTask.sendDataToTask(jsonEncode({
        'sim_lat': lat,
        'sim_lng': lng,
        'simulacion_activa': true,
      }));

      // 2. Disparar reporte HTTP directo desde UI para respuesta inmediata
      _apiService.reportarUbicacion(
        cadeteId: widget.cadeteId,
        lat: lat,
        lng: lng,
        accuracy: 3.0,
        speed: 20.0,
        heading: 90.0,
        gpsActivo: true,
      );

      // 3. Actualizar notificación visualmente
      await FlutterForegroundTask.updateService(
        notificationTitle: '🛠️ Chefsy GPS (SIMULADO)',
        notificationText:
            'Simulación activa: [${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}]',
      );
    }
  }

  void _moverSimulador(double deltaLat, double deltaLng) {
    _actualizarSimCoords(_simLat + deltaLat, _simLng + deltaLng);
  }

  void _iniciarMovimiento(double deltaLat, double deltaLng) {
    _moverSimulador(deltaLat, deltaLng);
    _joystickTimer?.cancel();
    _joystickTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      _moverSimulador(deltaLat, deltaLng);
    });
  }

  void _detenerMovimiento() {
    _joystickTimer?.cancel();
    _joystickTimer = null;
  }

  void _teletransportarLocal() {
    // Coordenadas reales del local de Chefsy en Frías, Santiago del Estero
    _actualizarSimCoords(-28.46281, -65.77850);
  }

  void _teletransportarCliente() {
    if (_pedidosListos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('No hay pedidos activos para teletransportar.')),
      );
      return;
    }
    // Teletransportar al cliente del primer pedido que tenga coordenadas
    for (var p in _pedidosListos) {
      if (p.coordenadas != null && p.coordenadas!.latitud != 0.0) {
        _actualizarSimCoords(p.coordenadas!.latitud, p.coordenadas!.longitud);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Teletransportado a cliente: ${p.cliente}')),
        );
        return;
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text(
              'Ninguno de los pedidos activos tiene coordenadas válidas.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF014B44),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF014B44),
              Color(0xFF002723),
            ],
          ),
        ),
        child: WithForegroundTask(
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cabecera compacta con Logo Chefsy y Moto
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onDoubleTap: () {
                          setState(() {
                            _mostrarControlesSimulacion = !_mostrarControlesSimulacion;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(_mostrarControlesSimulacion
                                  ? '🛠️ Panel Dev Activado'
                                  : '🛠️ Panel Dev Oculto'),
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        },
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(3),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(9),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.25),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.asset(
                                  'assets/logo.png',
                                  height: 24,
                                  width: 24,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.restaurant_menu,
                                    size: 20,
                                    color: Color(0xFF014B44),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text('Chefsy 🛵',
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 22,
                                    letterSpacing: 0.5,
                                    color: Colors.white)),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _estaRastreando
                                    ? const Color(0xFF10B981).withValues(alpha: 0.25)
                                    : Colors.white12,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _estaRastreando ? 'VIVO' : 'PAUSADO',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: _estaRastreando
                                        ? const Color(0xFF10B981)
                                        : Colors.white70),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.refresh_rounded, size: 22, color: Colors.white),
                        onPressed: _fetchPedidos,
                      ),
                    ],
                  ),
                  
                  // Info Sesión (compacta)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 20),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Repartidor: ${widget.cadeteNombre.toUpperCase()}',
                          style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.bold),
                        ),
                        GestureDetector(
                          onTap: _cerrarSesion,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.logout_rounded, size: 12, color: Colors.white70),
                                SizedBox(width: 4),
                                Text(
                                  'Cerrar sesión',
                                  style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Banner de Actualización Shorebird / OTA
                  if (_mensajeActualizacion != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: _listoParaReiniciar
                            ? const Color(0xFF10B981)
                            : const Color(0xFF3B82F6),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: (_listoParaReiniciar
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFF3B82F6))
                                .withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _listoParaReiniciar
                                ? Icons.system_update_rounded
                                : Icons.cloud_download_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _mensajeActualizacion!.split('|').first,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13),
                            ),
                          ),
                          if (_listoParaReiniciar)
                            ElevatedButton(
                              onPressed: _aplicarActualizacionYReiniciar,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFF10B981),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text('Aplicar y Reiniciar',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w900, fontSize: 12)),
                            ),
                        ],
                      ),
                    ),

                  // Botón compacto de Rastreo en Bolsillo Activo (Superior y más chico)
                  GestureDetector(
                    onTap: _toggleRastreo,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.symmetric(
                          vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: _estaRastreando
                              ? [const Color(0xFF10B981), const Color(0xFF047857)]
                              : [
                                  const Color(0xFF028073),
                                  const Color(0xFF014B44),
                                ],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: (_estaRastreando
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFF014B44))
                                .withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 300),
                            child: Icon(
                              _estaRastreando
                                  ? Icons.gps_fixed_rounded
                                  : Icons.play_circle_fill_rounded,
                              key: ValueKey(_estaRastreando),
                              size: 32,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _estaRastreando
                                      ? 'RASTREO EN SEGUNDO PLANO ACTIVO'
                                      : 'ACTIVAR RASTREO GPS',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _estaRastreando
                                      ? 'La Torre de Control te ve en vivo. Podés bloquear la pantalla.'
                                      : 'Tocá para iniciar tu turno y compartir ubicación.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white.withValues(alpha: 0.8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Switch.adaptive(
                            value: _estaRastreando,
                            onChanged: (_) => _toggleRastreo(),
                            activeColor: Colors.white,
                            activeTrackColor: const Color(0xFF059669),
                            inactiveThumbColor: Colors.white70,
                            inactiveTrackColor: Colors.white12,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Banner de Aviso: Fuera de Turno (GPS Inactivo)
                  if (!_estaRastreando)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFFF87171), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDC2626).withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.location_off_rounded,
                                color: Color(0xFFDC2626), size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                Text(
                                  'ESTÁS FUERA DE TURNO (GPS APAGADO)',
                                  style: TextStyle(
                                    color: Color(0xFF991B1B),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                SizedBox(height: 3),
                                Text(
                                  'El local no podrá asignarte pedidos hasta que actives el interruptor de rastreo superior.',
                                  style: TextStyle(
                                    color: Color(0xFFB91C1C),
                                    fontSize: 11,
                                    height: 1.3,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                // Panel de Simulación (si está activo)
                if (_mostrarControlesSimulacion) ...[
                  Container(
                    padding: const EdgeInsets.all(14),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: const Color(0xFF3B82F6), width: 1.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.bug_report_rounded,
                                    color: Colors.blueAccent, size: 20),
                                SizedBox(width: 6),
                                Text(
                                  'MODO SIMULACIÓN GPS',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.blueAccent),
                                ),
                              ],
                            ),
                            Switch(
                              value: _simulacionActiva,
                              onChanged: _toggleSimulacion,
                              activeColor: Colors.blueAccent,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (_simulacionActiva) ...[
                          Text(
                            'Coords: [${_simLat.toStringAsFixed(5)}, ${_simLng.toStringAsFixed(5)}]',
                            style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                color: Colors.white70),
                          ),
                          const SizedBox(height: 10),
                          // Botones de teletransporte
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        Colors.blue.withValues(alpha: 0.2),
                                    foregroundColor: Colors.blue,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 8),
                                  ),
                                  onPressed: _teletransportarLocal,
                                  child: const Text('Local Chefsy',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        Colors.pink.withValues(alpha: 0.2),
                                    foregroundColor: Colors.pinkAccent,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 8),
                                  ),
                                  onPressed: _teletransportarCliente,
                                  child: const Text('Cliente Pedido',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          // Controles de dirección (Joystick de flechas)
                          Center(
                            child: Column(
                              children: [
                                GestureDetector(
                                  onPanDown: (_) =>
                                      _iniciarMovimiento(0.00015, 0.0), // Norte
                                  onPanEnd: (_) => _detenerMovimiento(),
                                  onPanCancel: _detenerMovimiento,
                                  child: const Padding(
                                    padding: EdgeInsets.all(8.0),
                                    child: Icon(Icons.arrow_upward_rounded,
                                        size: 36, color: Colors.white),
                                  ),
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    GestureDetector(
                                      onPanDown: (_) => _iniciarMovimiento(
                                          0.0, -0.00015), // Oeste
                                      onPanEnd: (_) => _detenerMovimiento(),
                                      onPanCancel: _detenerMovimiento,
                                      child: const Padding(
                                        padding: EdgeInsets.all(8.0),
                                        child: Icon(Icons.arrow_back_rounded,
                                            size: 36, color: Colors.white),
                                      ),
                                    ),
                                    const SizedBox(
                                        width: 40,
                                        child: Icon(Icons.navigation,
                                            color: Colors.blueAccent,
                                            size: 24)),
                                    GestureDetector(
                                      onPanDown: (_) => _iniciarMovimiento(
                                          0.0, 0.00015), // Este
                                      onPanEnd: (_) => _detenerMovimiento(),
                                      onPanCancel: _detenerMovimiento,
                                      child: const Padding(
                                        padding: EdgeInsets.all(8.0),
                                        child: Icon(Icons.arrow_forward_rounded,
                                            size: 36, color: Colors.white),
                                      ),
                                    ),
                                  ],
                                ),
                                GestureDetector(
                                  onPanDown: (_) =>
                                      _iniciarMovimiento(-0.00015, 0.0), // Sur
                                  onPanEnd: (_) => _detenerMovimiento(),
                                  onPanCancel: _detenerMovimiento,
                                  child: const Padding(
                                    padding: EdgeInsets.all(8.0),
                                    child: Icon(Icons.arrow_downward_rounded,
                                        size: 36, color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                // Botón grande de rastreo movido a la parte superior en formato compacto

                // Pedidos asignados
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('📦 MIS PEDIDOS',
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            letterSpacing: 1,
                            color: Colors.white60)),
                    if (_cargandoPedidos)
                      const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                  ],
                ),
                const SizedBox(height: 12),

                // Tabs: Activos / Entregados
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _vistaActiva = 'activos'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _vistaActiva == 'activos'
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: _vistaActiva == 'activos'
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.08)),
                          ),
                          child: Center(
                            child: Text(
                                'Activos (${_pedidosListos.where((p) => p.estado != 'entregado').length})',
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: _vistaActiva == 'activos'
                                        ? const Color(0xFF014B44)
                                        : Colors.white70)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _vistaActiva = 'entregados'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _vistaActiva == 'entregados'
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: _vistaActiva == 'entregados'
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.08)),
                          ),
                          child: Center(
                            child: Text(
                                'Entregados (${_pedidosListos.where((p) => p.estado == 'entregado').length})',
                                style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: _vistaActiva == 'entregados'
                                        ? const Color(0xFF014B44)
                                        : Colors.white70)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                Builder(builder: (context) {
                  final filtrados = _pedidosListos
                      .where((p) => _vistaActiva == 'activos'
                          ? p.estado != 'entregado'
                          : p.estado == 'entregado')
                      .toList();
                  if (filtrados.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 40.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                                _vistaActiva == 'activos'
                                    ? Icons.inbox_rounded
                                    : Icons.check_circle_outline_rounded,
                                size: 54,
                                color: Colors.white.withValues(alpha: 0.15)),
                            const SizedBox(height: 12),
                            Text(
                              _vistaActiva == 'activos'
                                  ? 'No tenés pedidos activos en este momento.'
                                  : 'Aún no tenés pedidos entregados hoy.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filtrados.length,
                    itemBuilder: (context, idx) {
                      final p = filtrados[idx];
                      return TarjetaPedidoCadete(
                        pedido: p,
                        onAbrirWhatsApp: _abrirWhatsApp,
                        onCambiarEstado: _cambiarEstadoPedido,
                        estaCambiandoEstado: _cambiandoEstadoIds.contains(p.id),
                      );
                    },
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
}
