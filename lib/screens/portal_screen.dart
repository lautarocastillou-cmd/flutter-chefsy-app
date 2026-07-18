import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/pedido_model.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/tarjeta_pedido.dart';
import '../background_service.dart';
import '../services/updater_service.dart';

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
  bool _mostrarControlesSimulacion = false;
  bool _simulacionActiva = false;
  double _simLat = -32.8894;
  double _simLng = -68.8458;

  final ApiService _apiService = ApiService();
  final AuthService _authService = AuthService();
  final UpdaterService _updaterService = UpdaterService();

  String? _mensajeActualizacion;
  bool _listoParaReiniciar = false;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
    _pollingTimer = Timer.periodic(const Duration(seconds: 6), (_) => _fetchPedidosSilencioso());
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    final isRunning = await FlutterForegroundTask.isRunningService;
    final simActiva = await _authService.isSimulacionActiva();
    final simCoords = await _authService.obtenerSimCoordenadas();

    setState(() {
      _estaRastreando = isRunning;
      _simulacionActiva = simActiva;
      _simLat = simCoords['lat']!;
      _simLng = simCoords['lng']!;
      if (isRunning) {
        _ultimaUbicacionTexto = simActiva ? 'Simulador activo: [$_simLat, $_simLng]' : 'Transmitiendo GPS...';
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
              content: Text('❌ Necesitamos permiso de ubicación para rastrear.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }
    }

    try {
      await FlutterForegroundTask.startService(
        serviceId: 888,
        notificationTitle: _simulacionActiva ? '🛠️ Chefsy GPS (SIMULADO)' : '🛵 Chefsy Cadetería',
        notificationText: _simulacionActiva 
            ? 'Simulación activa: [$_simLat, $_simLng]'
            : 'GPS activo. Podés guardar el celular en el bolsillo.',
        callback: startCallback,
      );
      if (mounted) {
        setState(() {
          _estaRastreando = true;
          _ultimaUbicacionTexto = _simulacionActiva 
              ? 'Simulador activo: [$_simLat, $_simLng]'
              : 'Transmitiendo GPS...';
        });
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
          content: const Text('¿Estás seguro de que querés dejar de compartir tu ubicación?'),
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
      setState(() {
        _pedidosListos = list;
      });
    }
  }

  Future<void> _cambiarEstadoPedido(String id, String nuevoEstado) async {
    final ok = await _apiService.cambiarEstadoPedido(id, nuevoEstado);
    if (ok) {
      _fetchPedidos();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo actualizar el estado.')),
        );
      }
    }
  }

  Future<void> _abrirWhatsApp(String telefono, String cliente) async {
    var tel = telefono.replaceAll(RegExp(r'\D'), '');
    if (tel.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El cliente no tiene teléfono registrado')),
      );
      return;
    }
    if (!tel.startsWith('549') && !tel.startsWith('54')) {
      if (tel.startsWith('0')) tel = tel.substring(1);
      tel = '549$tel';
    }
    final mensaje = "Hola $cliente! Soy tu repartidor de Chefsy 🛵. Estoy en camino con tu pedido!";
    
    final uris = [
      Uri.parse('whatsapp://send?phone=$tel&text=${Uri.encodeComponent(mensaje)}'),
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
        const SnackBar(content: Text('No se pudo abrir WhatsApp en este dispositivo.')),
      );
    }
  }

  // --- Funciones del Simulador de GPS ---
  Future<void> _toggleSimulacion(bool activa) async {
    await _authService.setSimulacionActiva(activa);
    setState(() {
      _simulacionActiva = activa;
    });
    // Si ya está rastreando, reiniciamos el servicio para aplicar los cambios de modo
    if (_estaRastreando) {
      await _detenerRastreo();
      await _iniciarRastreo();
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

    // Actualizar notificación del foreground task con la ubicación mock
    if (_estaRastreando && _simulacionActiva) {
      await FlutterForegroundTask.updateService(
        notificationTitle: '🛠️ Chefsy GPS (SIMULADO)',
        notificationText: 'Simulación activa: [${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}]',
      );
    }
  }

  void _moverSimulador(double deltaLat, double deltaLng) {
    _actualizarSimCoords(_simLat + deltaLat, _simLng + deltaLng);
  }

  void _teletransportarLocal() {
    // Coordenadas local de Chefsy en Mendoza
    _actualizarSimCoords(-32.8894, -68.8458);
  }

  void _teletransportarCliente() {
    if (_pedidosListos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay pedidos activos para teletransportar.')),
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
      const SnackBar(content: Text('Ninguno de los pedidos activos tiene coordenadas válidas.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('🛵 Chefsy Cadetería',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: _estaRastreando
                    ? const Color(0xFF10B981).withValues(alpha: 0.2)
                    : Colors.white10,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                _estaRastreando ? 'VIVO' : 'PAUSADO',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: _estaRastreando
                        ? const Color(0xFF10B981)
                        : Colors.white54),
              ),
            )
          ],
        ),
        backgroundColor: const Color(0xFF0F172A),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetchPedidos,
          ),
        ],
      ),
      body: WithForegroundTask(
        child: Padding(
          padding: const EdgeInsets.all(18.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Banner de Actualización Shorebird / OTA
              if (_mensajeActualizacion != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: _listoParaReiniciar ? const Color(0xFF10B981) : const Color(0xFF3B82F6),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: (_listoParaReiniciar ? const Color(0xFF10B981) : const Color(0xFF3B82F6)).withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _listoParaReiniciar ? Icons.system_update_rounded : Icons.cloud_download_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _mensajeActualizacion!.split('|').first,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                      if (_listoParaReiniciar)
                        ElevatedButton(
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Reiniciá la app para activar el nuevo código.')),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF10B981),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          child: const Text('Aplicar', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
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
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: _estaRastreando
                          ? [const Color(0xFF10B981), const Color(0xFF047857)]
                          : [const Color(0xFFE11D48), const Color(0xFF9F1239)],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: (_estaRastreando ? const Color(0xFF10B981) : const Color(0xFFE11D48)).withValues(alpha: 0.35),
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
                          _estaRastreando ? Icons.gps_fixed_rounded : Icons.play_circle_fill_rounded,
                          key: ValueKey(_estaRastreando),
                          size: 32,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _estaRastreando
                                  ? (_simulacionActiva ? 'SIMULACIÓN GPS ACTIVA' : 'RASTREO EN BOLSILLO ACTIVO')
                                  : 'INICIAR TURNO Y RASTREO',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 0.5),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _ultimaUbicacionTexto,
                              style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.85), fontFamily: 'monospace'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _estaRastreando ? 'ON' : 'OFF',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Sesión activa info (Doble tap activa controles de simulación)


              GestureDetector(
                onDoubleTap: () {
                  setState(() {
                    _mostrarControlesSimulacion = !_mostrarControlesSimulacion;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(_mostrarControlesSimulacion 
                          ? '🛠️ Panel de Desarrollador Activado' 
                          : '🛠️ Panel de Desarrollador Oculto'),
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.account_circle_rounded,
                              color: Color(0xFFE11D48), size: 28),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.cadeteNombre.toUpperCase(),
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white),
                              ),
                              const Text(
                                'Sesión Repartidor Conectada',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.white54),
                              ),
                            ],
                          ),
                        ],
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(foregroundColor: Colors.white60),
                        icon: const Icon(Icons.logout_rounded, size: 18),
                        label: const Text('Salir', style: TextStyle(fontSize: 12)),
                        onPressed: _cerrarSesion,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Panel de Simulación (si está activo)
              if (_mostrarControlesSimulacion) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF3B82F6), width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.bug_report_rounded, color: Colors.blueAccent, size: 20),
                              SizedBox(width: 6),
                              Text(
                                'MODO SIMULACIÓN GPS',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.blueAccent),
                              ),
                            ],
                          ),
                          Switch(
                            value: _simulacionActiva,
                            onChanged: _toggleSimulacion,
                            activeThumbColor: Colors.blueAccent,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (_simulacionActiva) ...[
                        Text(
                          'Coords: [${_simLat.toStringAsFixed(5)}, ${_simLng.toStringAsFixed(5)}]',
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.white70),
                        ),
                        const SizedBox(height: 10),
                        // Botones de teletransporte
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue.withValues(alpha: 0.2),
                                  foregroundColor: Colors.blue,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                ),
                                onPressed: _teletransportarLocal,
                                child: const Text('Local Chefsy', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.pink.withValues(alpha: 0.2),
                                  foregroundColor: Colors.pinkAccent,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                ),
                                onPressed: _teletransportarCliente,
                                child: const Text('Cliente Pedido', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // Controles de dirección (Joystick de flechas)
                        Center(
                          child: Column(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_upward_rounded, size: 28, color: Colors.white),
                                onPressed: () => _moverSimulador(0.00015, 0.0), // Norte
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.arrow_back_rounded, size: 28, color: Colors.white),
                                    onPressed: () => _moverSimulador(0.0, -0.00015), // Oeste
                                  ),
                                  const SizedBox(width: 40, child: Icon(Icons.navigation, color: Colors.blueAccent, size: 20)),
                                  IconButton(
                                    icon: const Icon(Icons.arrow_forward_rounded, size: 28, color: Colors.white),
                                    onPressed: () => _moverSimulador(0.0, 0.00015), // Este
                                  ),
                                ],
                              ),
                              IconButton(
                                icon: const Icon(Icons.arrow_downward_rounded, size: 28, color: Colors.white),
                                onPressed: () => _moverSimulador(-0.00015, 0.0), // Sur
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
                  const Text('📦 PEDIDOS ASIGNADOS',
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

              Expanded(
                child: _pedidosListos.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inbox_rounded,
                                size: 54,
                                color: Colors.white.withValues(alpha: 0.15)),
                            const SizedBox(height: 12),
                            const Text(
                              '🎉 Sin entregas pendientes ahora.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 14),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _pedidosListos.length,
                        itemBuilder: (context, idx) {
                          final p = _pedidosListos[idx];
                          return TarjetaPedidoCadete(
                            pedido: p,
                            onAbrirWhatsApp: _abrirWhatsApp,
                            onCambiarEstado: _cambiarEstadoPedido,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
