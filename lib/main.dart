import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'background_service.dart';

// Token compartido con el servidor Chefsy — mismo que usa el endpoint GPS
const _token = 'chefsy_expo_secure_track_99XQ';
const _baseUrl = 'https://chefsy.xyz';

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
      title: 'Chefsy Cadetería',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE11D48),
          surface: Color(0xFF1E293B),
        ),
        fontFamily: 'Roboto',
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
  String? _cadeteNombre;
  bool _estaRastreando = false;
  List<dynamic> _pedidosListos = [];
  bool _cargandoPedidos = false;
  bool _logueando = false;
  String _ultimaUbicacionTexto = 'Esperando señal GPS...';
  Timer? _pollingTimer;

  final TextEditingController _usuarioCtrl = TextEditingController();
  final TextEditingController _claveCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cargarDatos();
    _pollingTimer = Timer.periodic(const Duration(seconds: 6), (_) => _fetchPedidosSilencioso());
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _usuarioCtrl.dispose();
    _claveCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    final prefs = await SharedPreferences.getInstance();
    final guardadoId = prefs.getString('cadete_id');
    final guardadoNombre = prefs.getString('cadete_nombre');
    final isRunning = await FlutterForegroundTask.isRunningService;

    setState(() {
      _cadeteId = guardadoId;
      _cadeteNombre = guardadoNombre;
      _estaRastreando = isRunning;
    });

    if (guardadoId != null) _fetchPedidos();
  }

  Future<void> _login() async {
    final usr = _usuarioCtrl.text.trim().toLowerCase();
    final clv = _claveCtrl.text;

    if (usr.isEmpty || clv.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor ingresá tu usuario y contraseña.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _logueando = true);

    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'usuario': usr, 'clave': clv}),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(res.body);

      if (res.statusCode == 200 && data['ok'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cadete_id', data['usuario']);
        await prefs.setString('cadete_nombre', data['nombre'] ?? data['usuario']);

        setState(() {
          _cadeteId = data['usuario'];
          _cadeteNombre = data['nombre'] ?? data['usuario'];
          _logueando = false;
        });

        _usuarioCtrl.clear();
        _claveCtrl.clear();
        _fetchPedidos();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(data['error'] ?? 'Credenciales incorrectas.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error de conexión al iniciar sesión en Chefsy.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _logueando = false);
    }
  }

  Future<void> _cerrarSesion() async {
    if (_estaRastreando) {
      await _detenerRastreo();
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('cadete_id');
    await prefs.remove('cadete_nombre');

    setState(() {
      _cadeteId = null;
      _cadeteNombre = null;
      _pedidosListos = [];
    });
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
    final notifPerm = await FlutterForegroundTask.checkNotificationPermission();
    if (notifPerm != NotificationPermission.granted) {
      await FlutterForegroundTask.requestNotificationPermission();
    }

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
        _ultimaUbicacionTexto = 'Rastreo pausado.';
      });
    }
  }

  void _toggleRastreo() {
    if (_estaRastreando) {
      _detenerRastreo();
    } else {
      _iniciarRastreo();
    }
  }

  Future<void> _fetchPedidos() async {
    if (_cadeteId == null) return;
    setState(() => _cargandoPedidos = true);
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/api/public/pedidos?cadeteId=$_cadeteId'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() => _pedidosListos = data['pedidos'] ?? []);
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _cargandoPedidos = false);
    }
  }

  Future<void> _fetchPedidosSilencioso() async {
    if (_cadeteId == null) return;
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/api/public/pedidos?cadeteId=$_cadeteId'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body);
        setState(() => _pedidosListos = data['pedidos'] ?? []);
      }
    } catch (_) {
    }
  }

  Future<void> _cambiarEstadoPedido(String id, String nuevoEstado) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/api/public/pedidos'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: jsonEncode({
          'accion': 'actualizar_estado',
          'id': id,
          'estado': nuevoEstado,
        }),
      );
      if (res.statusCode == 200) {
        _fetchPedidos();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No se pudo actualizar el estado.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al actualizar estado.')),
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
    final url = Uri.parse(
        'https://wa.me/$tel?text=${Uri.encodeComponent("Hola $cliente! Soy tu repartidor de Chefsy 🛵. Estoy en camino con tu pedido!")}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir WhatsApp')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cadeteId == null) {
      return _buildLoginScreen();
    }
    return _buildPortalScreen();
  }

  Widget _buildLoginScreen() {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFE11D48), Color(0xFF9F1239)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFE11D48).withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.delivery_dining_rounded,
                      size: 46, color: Colors.white),
                ),
                const SizedBox(height: 24),
                const Text(
                  'CHEFSY CADETERÍA',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Acceso Oficial con tu Usuario Chefsy',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 36),
                TextField(
                  controller: _usuarioCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Usuario',
                    prefixIcon: const Icon(Icons.person_outline_rounded),
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _claveCtrl,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    filled: true,
                    fillColor: const Color(0xFF1E293B),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFE11D48),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 4,
                    ),
                    onPressed: _logueando ? null : _login,
                    child: _logueando
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            'INICIAR SESIÓN',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPortalScreen() {
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
              // Sesión activa info
              Container(
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
                              (_cadeteNombre ?? _cadeteId ?? '').toUpperCase(),
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
                  const Text('📦 PEDIDOS ASIGNADOS',
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

class TarjetaPedidoCadete extends StatelessWidget {
  final dynamic pedido;
  final Function(String telefono, String cliente) onAbrirWhatsApp;
  final Function(String id, String nuevoEstado) onCambiarEstado;

  const TarjetaPedidoCadete({
    super.key,
    required this.pedido,
    required this.onAbrirWhatsApp,
    required this.onCambiarEstado,
  });

  String formatearPrecio(dynamic total) {
    if (total == null) return '\$0';
    final numVal = num.tryParse(total.toString()) ?? 0;
    final absVal = numVal.abs().toStringAsFixed(0);
    final strFormatted = absVal.replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.');
    return numVal < 0 ? '-\$$strFormatted' : '\$$strFormatted';
  }

  void _llamarCliente(BuildContext context, String? tel) async {
    if (tel == null || tel.toString().trim().isEmpty || tel == 'Sin especificar') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sin número de teléfono registrado.')),
      );
      return;
    }
    final cleanTel = tel.toString().replaceAll(RegExp(r'\D'), '');
    final url = Uri.parse('tel:$cleanTel');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir la app de llamadas.')),
      );
    }
  }

  void _abrirGoogleMaps(BuildContext context) async {
    final coords = pedido['coordenadas'];
    Uri url;
    if (coords != null && coords is Map && coords['latitud'] != null) {
      url = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${coords['latitud']},${coords['longitud']}');
    } else {
      final dir = pedido['direccion']?.toString() ?? '';
      if (dir.isEmpty || dir == 'Retiro en local') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Es un pedido para retiro en local.')),
        );
        return;
      }
      url = Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(dir)}');
    }
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir Google Maps.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = pedido['id']?.toString() ?? '';
    final cliente = pedido['cliente']?.toString() ?? 'Cliente';
    final telefono = pedido['telefono']?.toString() ?? 'Sin especificar';
    final hora = pedido['hora']?.toString() ?? '';
    final estado = pedido['estado']?.toString() ?? '';
    final direccion = pedido['direccion']?.toString() ?? 'Retiro en local';
    final distanciaKm = pedido['distanciaKm'];
    final productos = pedido['productos'];
    final total = pedido['total'];
    final costoEnvio = pedido['costoEnvio'];
    final metodoPago = pedido['metodoPago']?.toString() ?? '';
    final pagoConfirmado = pedido['pago_confirmado'] == true;
    final observaciones = pedido['observaciones']?.toString() ?? '';

    Color colorEstadoBg = const Color(0xFF3B82F6).withValues(alpha: 0.18);
    Color colorEstadoText = const Color(0xFF60A5FA);
    if (estado == 'en_cocina') {
      colorEstadoBg = const Color(0xFFF59E0B).withValues(alpha: 0.18);
      colorEstadoText = const Color(0xFFFBBF24);
    } else if (estado == 'listo') {
      colorEstadoBg = const Color(0xFF10B981).withValues(alpha: 0.18);
      colorEstadoText = const Color(0xFF34D399);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabecera: Cliente y Estado
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cliente,
                      style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          telefono == 'Sin especificar' ? 'Tel: No especificado' : 'Tel: $telefono',
                          style: const TextStyle(fontSize: 12, color: Colors.white54),
                        ),
                        if (hora.isNotEmpty) ...[
                          const Text(' • ', style: TextStyle(color: Colors.white38)),
                          Text(
                            hora,
                            style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.bold),
                          ),
                        ]
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: colorEstadoBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  estado.toUpperCase().replaceAll('_', ' '),
                  style: TextStyle(
                      color: colorEstadoText,
                      fontSize: 11,
                      fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Botones rápidos: Llamar, WhatsApp, Google Maps
          Row(
            children: [
              if (telefono != 'Sin especificar') ...[
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF334155),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.phone_rounded, size: 15),
                    label: const Text('Llamar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: () => _llamarCliente(context, telefono),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.chat_bubble_rounded, size: 15),
                    label: const Text('WhatsApp', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: () => onAbrirWhatsApp(telefono, cliente),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.map_rounded, size: 15),
                  label: const Text('Maps', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () => _abrirGoogleMaps(context),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Caja de Dirección / Delivery
          GestureDetector(
            onTap: () => _abrirGoogleMaps(context),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE11D48).withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'DIRECCIÓN DE ENTREGA',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.white54,
                            letterSpacing: 0.8),
                      ),
                      if (distanciaKm != null)
                        Text(
                          '(${num.tryParse(distanciaKm.toString())?.toStringAsFixed(1) ?? distanciaKm} km)',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFF43F5E)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.location_on_rounded, size: 18, color: Color(0xFFF43F5E)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          direccion,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white),
                        ),
                      ),
                      const Icon(Icons.navigation_rounded, size: 16, color: Colors.white38),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Lista de productos
          if (productos != null && productos is List && productos.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: productos.map<Widget>((prod) {
                  final nom = prod['nombre']?.toString() ?? 'Producto';
                  final cant = prod['cantidad']?.toString() ?? '1';
                  final esBebida = RegExp(r'coca|fanta|sprite|agua|cerveza|bebida|aquarius|gaseosa', caseSensitive: false).hasMatch(nom);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Text(
                      '$cant× $nom',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: esBebida ? FontWeight.w800 : FontWeight.w500,
                        color: esBebida ? const Color(0xFFF43F5E) : Colors.white70,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          // Cobrar y Método de Pago
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Cobrar', style: TextStyle(fontSize: 11, color: Colors.white54)),
                    Text(
                      formatearPrecio(total),
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                    if (costoEnvio != null && (num.tryParse(costoEnvio.toString()) ?? 0) > 0)
                      Text(
                        '(Incluye ${formatearPrecio(costoEnvio)} envío)',
                        style: const TextStyle(fontSize: 10, color: Colors.white38),
                      ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      metodoPago.toUpperCase(),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white70),
                    ),
                    if (metodoPago.toLowerCase() == 'transferencia') ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: pagoConfirmado
                              ? const Color(0xFF10B981).withValues(alpha: 0.2)
                              : const Color(0xFFF59E0B).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          pagoConfirmado ? '✅ PAGADO' : '❌ Pendiente Impactar',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: pagoConfirmado ? const Color(0xFF34D399) : const Color(0xFFFBBF24)),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Observaciones
          if (observaciones.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
              ),
              child: Text(
                '⚠️ $observaciones',
                style: const TextStyle(color: Color(0xFFFDE68A), fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],

          // Botón de Acción de Estado (Marcar como listo / Entregar)
          if (estado == 'en_cocina' || estado == 'listo' || estado == 'en_camino') ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: estado == 'en_cocina' ? const Color(0xFF10B981) : const Color(0xFFE11D48),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 2,
                ),
                icon: Icon(
                  estado == 'en_cocina' ? Icons.check_circle_outline_rounded : Icons.delivery_dining_rounded,
                  size: 20,
                ),
                label: Text(
                  estado == 'en_cocina' ? 'MARCAR COMO LISTO' : 'MARCAR COMO ENTREGADO',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.8),
                ),
                onPressed: () {
                  final nuevoEstado = estado == 'en_cocina' ? 'listo' : 'entregado';
                  onCambiarEstado(id, nuevoEstado);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// Entry point del handler — debe estar fuera de cualquier clase
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(GpsTaskHandler());
}
