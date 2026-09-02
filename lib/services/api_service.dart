import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/pedido_model.dart';
import '../models/pago_extra_model.dart';

class ApiService {
  static const String _baseUrl = 'https://chefsy.xyz';
  static const String _token = 'chefsy_expo_secure_track_99XQ';

  // --- Iniciar Sesión ---
  Future<Map<String, dynamic>?> login(String usuario, String clave) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'usuario': usuario, 'clave': clave}),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data['ok'] == true) {
        return {
          'usuario': data['usuario']?.toString() ?? usuario,
          'nombre': data['nombre']?.toString() ?? data['usuario']?.toString() ?? usuario,
        };
      } else {
        return {'error': data['error'] ?? 'Credenciales incorrectas.'};
      }
    } catch (e) {
      return {'error': 'Error de conexión al iniciar sesión en Chefsy.'};
    }
  }

  // --- Consultar Pedidos y Pagos Extras del Turno ---
  Future<Map<String, dynamic>> fetchDatosTurno(String cadeteId) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/api/public/pedidos?cadeteId=$cadeteId'),
        headers: {'Authorization': 'Bearer $_token'},
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final listPedidos = data['pedidos'] as List? ?? [];
        final listExtras = data['pagos_extras'] as List? ?? [];
        final montoBase = double.tryParse(data['monto_base']?.toString() ?? '0') ?? 0.0;
        final turnoActivo = data['turno_activo'] == true;
        return {
          'pedidos': listPedidos
              .map((p) => PedidoModel.fromJson(Map<String, dynamic>.from(p)))
              .toList(),
          'pagos_extras': listExtras
              .map((e) => PagoExtraModel.fromJson(Map<String, dynamic>.from(e)))
              .toList(),
          'monto_base': montoBase,
          'turno_activo': turnoActivo,
        };
      }
    } catch (_) {}
    return {
      'pedidos': <PedidoModel>[],
      'pagos_extras': <PagoExtraModel>[],
      'monto_base': 0.0,
      'turno_activo': false,
    };
  }

  // --- Consultar Pedidos ---
  Future<List<PedidoModel>> fetchPedidos(String cadeteId) async {
    final datos = await fetchDatosTurno(cadeteId);
    return datos['pedidos'] as List<PedidoModel>;
  }

  // --- Cambiar Estado del Pedido ---
  Future<bool> cambiarEstadoPedido(String id, String nuevoEstado) async {
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
      ).timeout(const Duration(seconds: 8));

      return res.statusCode == 200;
    } catch (_) {}
    return false;
  }

  // --- Reportar Ubicación y Telemetría ---
  Future<bool> reportarUbicacion({
    required String cadeteId,
    required double lat,
    required double lng,
    double accuracy = 5.0,
    double speed = 0.0,
    double heading = 0.0,
    int? batteryLevel,
    bool gpsActivo = true,
    bool iniciarGpsManual = false,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/api/public/ubicacion'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: jsonEncode({
          'cadeteId': cadeteId,
          'lat': lat,
          'lng': lng,
          'accuracy': accuracy,
          'speed': speed,
          'heading': heading,
          'gps_activo': gpsActivo,
          if (iniciarGpsManual) 'iniciar_gps_manual': true,
          if (batteryLevel != null) 'batteryLevel': batteryLevel,
        }),
      ).timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
