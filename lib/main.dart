import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'background_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Inicializar configuración del foreground task (sin arrancarlo todavía)
  initForegroundTask();
  runApp(const ChefsyCadeteApp());
}

class ChefsyCadeteApp extends StatelessWidget {
  const ChefsyCadeteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chefsy Cadete',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE11D48),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0B0F19),
        useMaterial3: true,
      ),
      home: const PortalCadeteScreen(),
    );
  }
}

class PortalCadeteScreen extends StatefulWidget {
  const PortalCadeteScreen({super.key});

  @override
  State<PortalCadeteScreen> createState() => _PortalCadeteScreenState();
}

class _PortalCadeteScreenState extends State<PortalCadeteScreen> {
  String? _cadeteId;
  bool _estaRastreando = false;
  List<dynamic> _pedidosListos = [];
  bool _cargandoPedidos = false;
  String _ultimaUbicacionTexto = 'Esperando señal GPS...';

  final List<Map<String, String>> _cadetesDisponibles = [
    {'id': 'paulo', 'nombre': 'Paulo'},
    {'id': 'juan', 'nombre': 'Juan'},
    {'id': 'lautaro', 'nombre': 'Lautaro'},
  ];

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    final prefs = await SharedPreferences.getInstance();
    final guardado = prefs.getString('cadete_id');
    final isRunning = await FlutterForegroundTask.isRunningService;

    setState(() {
      _cadeteId = guardado;
      _estaRastreando = isRunning;
    });

    if (guardado != null) _fetchPedidos();
  }

  // Solicitar permiso SOLO de primer plano (whileInUse) — no fuerza el de "siempre"
  // para evitar el crash de SecurityException en Android 12-14.
  Future<bool> _verificarPermisosGps() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    // Permiso permanentemente denegado → abrir config del sistema
    if (permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      return false;
    }

    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  Future<void> _iniciarRastreo() async {
    // Pedir permiso de notificaciones en Android 13+ (requerido para mostrar la notificación del servicio)
    final notifPerm = await FlutterForegroundTask.checkNotificationPermission();
    if (notifPerm != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

    // Pedir permiso de ubicación
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

    try {
      await FlutterForegroundTask.startService(
        serviceId: 888,
        notificationTitle: '🛵 Chefsy Cadetería',
        notificationText: 'GPS activo. Podés guardar el celular en el bolsillo.',
        callback: startCallback,
      );
      if (mounted) {
        setState(() {
          _estaRastreando = true;
          _ultimaUbicacionTexto = 'Transmitiendo GPS...';
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
        _ultimaUbicacionTexto = 'Rastreo detenido.';
      });
    }
  }

  Future<void> _toggleRastreo() async {
    if (_cadeteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ Primero seleccioná tu usuario de cadete.'),
          backgroundColor: Colors.amber,
        ),
      );
      return;
    }

    if (_estaRastreando) {
      await _detenerRastreo();
    } else {
      await _iniciarRastreo();
    }
  }

  Future<void> _fetchPedidos() async {
    if (_cadeteId == null) return;
    setState(() => _cargandoPedidos = true);
    try {
      final res = await http.get(Uri.parse('https://chefsy.xyz/api/admin/pedidos'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _pedidosListos = (data['pedidos'] ?? []).where((p) =>
              (p['estado'] == 'listo' || p['estado'] == 'en_camino') &&
              p['cadete_id'] == _cadeteId).toList();
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _cargandoPedidos = false);
    }
  }

  void _abrirWhatsApp(String telefono, String cliente) async {
    final num = telefono.replaceAll(RegExp(r'\D'), '');
    final msg = Uri.encodeComponent(
        '¡Hola $cliente! Soy tu repartidor de Chefsy 🛵. Estoy en camino con tu pedido.');
    final url = Uri.parse('https://wa.me/549$num?text=$msg');
    if (await canLaunchUrl(url)) await launchUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.delivery_dining, color: Color(0xFFF43F5E), size: 28),
            SizedBox(width: 10),
            Text('Chefsy Cadete',
                style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5)),
          ],
        ),
        backgroundColor: const Color(0xFF131B2E),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            onPressed: _fetchPedidos,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Selector de Usuario
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Sesión Repartidor:',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white70)),
                    DropdownButton<String>(
                      value: _cadeteId,
                      hint: const Text('Seleccionar'),
                      underline: const SizedBox(),
                      dropdownColor: const Color(0xFF1E293B),
                      items: _cadetesDisponibles
                          .map((c) => DropdownMenuItem(
                                value: c['id'],
                                child: Text(c['nombre']!.toUpperCase(),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white)),
                              ))
                          .toList(),
                      onChanged: (val) async {
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setString('cadete_id', val!);
                        setState(() => _cadeteId = val);
                        _fetchPedidos();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),

              // Botón principal de turno
              GestureDetector(
                onTap: _toggleRastreo,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeInOut,
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: _estaRastreando
                          ? [const Color(0xFF10B981), const Color(0xFF047857)]
                          : [const Color(0xFFE11D48), const Color(0xFF9F1239)],
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: (_estaRastreando
                                ? const Color(0xFF10B981)
                                : const Color(0xFFE11D48))
                            .withValues(alpha: 0.45),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      )
                    ],
                  ),
                  child: Column(
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Icon(
                          _estaRastreando
                              ? Icons.gps_fixed_rounded
                              : Icons.play_circle_fill_rounded,
                          key: ValueKey(_estaRastreando),
                          size: 56,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _estaRastreando
                            ? 'RASTREO EN BOLSILLO ACTIVO'
                            : 'INICIAR TURNO Y RASTREO',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _estaRastreando
                            ? 'Podés apagar la pantalla. El GPS sigue reportando.'
                            : 'Toca para activar el rastreo en segundo plano',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 13),
                      ),
                      if (_estaRastreando) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _ultimaUbicacionTexto,
                            style: const TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                color: Colors.white70),
                          ),
                        ),
                      ]
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // Pedidos asignados
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('📦 PEDIDOS EN CURSO',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          letterSpacing: 1,
                          color: Colors.white60)),
                  if (_cargandoPedidos)
                    const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
              const SizedBox(height: 14),

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
                            Text(
                              _cadeteId == null
                                  ? 'Seleccioná tu usuario para ver pedidos'
                                  : '🎉 Sin entregas pendientes ahora.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 14),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _pedidosListos.length,
                        itemBuilder: (context, idx) {
                          final p = _pedidosListos[idx];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E293B),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.08)),
                            ),
                            padding: const EdgeInsets.all(18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        p['cliente'] ?? 'Cliente',
                                        style: const TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w900),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF59E0B)
                                            .withValues(alpha: 0.18),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        (p['estado'] ?? '')
                                            .toString()
                                            .toUpperCase(),
                                        style: const TextStyle(
                                            color: Color(0xFFFBBF24),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w800),
                                      ),
                                    )
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(Icons.location_on_rounded,
                                        size: 16, color: Color(0xFFF43F5E)),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        p['direccion'] ?? 'Retiro en local',
                                        style: const TextStyle(
                                            color: Colors.white70, fontSize: 14),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF25D366),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(14)),
                                      elevation: 0,
                                    ),
                                    icon: const Icon(
                                        Icons.chat_bubble_rounded,
                                        size: 18),
                                    label: const Text('AVISAR POR WHATSAPP',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13,
                                            letterSpacing: 0.5)),
                                    onPressed: () => _abrirWhatsApp(
                                        p['telefono'] ?? '',
                                        p['cliente'] ?? ''),
                                  ),
                                ),
                              ],
                            ),
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

// Entry point del handler — debe estar fuera de cualquier clase
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(GpsTaskHandler());
}
