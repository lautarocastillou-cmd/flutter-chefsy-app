import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/pedido_model.dart';

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

  // --- Consultar Pedidos ---
  Future<List<PedidoModel>> fetchPedidos(String cadeteId) async {
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/api/public/pedidos?cadeteId=$cadeteId'),
        headers: {'Authorization': 'Bearer $_token'},
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = data['pedidos'] as List? ?? [];
        return list.map((p) => PedidoModel.fromJson(Map<String, dynamic>.from(p))).toList();
      }
    } catch (_) {}
    return [];
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
}
