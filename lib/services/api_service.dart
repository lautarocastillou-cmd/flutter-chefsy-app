import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/pedido_model.dart';
import '../models/pago_extra_model.dart';
import '../models/rendimiento_model.dart';

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
  Future<bool> cambiarEstadoPedido(
    String id,
    String nuevoEstado, {
    String? metodoPago,
    bool? pagoConfirmado,
  }) async {
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
          if (metodoPago != null) 'metodo_pago': metodoPago,
          if (pagoConfirmado != null) 'pago_confirmado': pagoConfirmado,
        }),
      ).timeout(const Duration(seconds: 8));

      return res.statusCode == 200;
    } catch (_) {}
    return false;
  }

  // --- Cambiar Método de Pago / Cobro Directo ---
  Future<bool> cambiarMetodoPago(
    String id,
    String nuevoMetodo, {
    bool? pagoConfirmado,
  }) async {
    try {
      final res = await http.post(
        Uri.parse('$_baseUrl/api/public/pedidos'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: jsonEncode({
          'accion': 'cambiar_metodo_pago',
          'id': id,
          'metodo_pago': nuevoMetodo,
          if (pagoConfirmado != null) 'pago_confirmado': pagoConfirmado,
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

  // --- Consultar Rendimiento, Velocidad y Ranking Semanal ---
  Future<RendimientoCompletoData?> fetchRendimientoCadete(String cadeteId) async {
    final cacheKey = 'cache_rendimiento_$cadeteId';
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {}

    // 1. Intentar consultar endpoint principal del servidor
    try {
      final res = await http.get(
        Uri.parse('$_baseUrl/api/public/cadetes/rendimiento?cadeteId=$cadeteId'),
        headers: {'Authorization': 'Bearer $_token'},
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['ok'] == true) {
          // Guardar en caché local para soporte offline
          prefs?.setString(cacheKey, res.body);
          return RendimientoCompletoData.fromJson(data, esDesdeCache: false);
        }
      }
    } catch (_) {
      // Continuar con fallbacks
    }

    // 2. Fallback de respaldo: Consultar directamente Supabase
    try {
      final cadeteIdNorm = cadeteId.trim().toLowerCase();

      // Consultar historial semanal en Supabase
      final semanasRes = await Supabase.instance.client
          .from('cadetes_rendimiento_semanal')
          .select()
          .or('cadete_id.ilike.$cadeteIdNorm,cadete_nombre.ilike.$cadeteIdNorm')
          .order('anio', ascending: false)
          .order('semana_numero', ascending: false)
          .limit(10);

      // Consultar registro de hoy si existe en Supabase
      final ahora = DateTime.now();
      final fechaHoyStr =
          "${ahora.year}-${ahora.month.toString().padLeft(2, '0')}-${ahora.day.toString().padLeft(2, '0')}";
      final hoyRes = await Supabase.instance.client
          .from('cadetes_rendimiento_diario')
          .select()
          .eq('fecha', fechaHoyStr);

      final List hoyList = (hoyRes as List?) ?? [];
      final List semanasList = (semanasRes as List?) ?? [];

      if (semanasList.isNotEmpty || hoyList.isNotEmpty) {
        Map<String, dynamic>? masRapidoRow;
        Map<String, dynamic>? miHoyRow;
        for (final item in hoyList) {
          final m = Map<String, dynamic>.from(item);
          final id = (m['cadete_id'] ?? '').toString().toLowerCase();
          final nom = (m['cadete_nombre'] ?? '').toString().toLowerCase();
          if (id == cadeteIdNorm || nom == cadeteIdNorm) {
            miHoyRow = m;
          }
          if (m['es_mas_rapido_dia'] == true) {
            masRapidoRow = m;
          }
        }

        final miRendimientoHoy = RendimientoCadeteHoy(
          pedidosEntregados:
              (miHoyRow?['pedidos_entregados'] as num?)?.toInt() ?? 0,
          kmTotales: (miHoyRow?['km_totales'] as num?)?.toDouble() ?? 0.0,
          velocidadMediaMovimiento:
              (miHoyRow?['velocidad_media_movimiento'] as num?)?.toDouble() ??
                  0.0,
          velocidadMaxima:
              (miHoyRow?['velocidad_maxima'] as num?)?.toDouble() ?? 0.0,
          tiempoPromedioEntregaMin:
              (miHoyRow?['tiempo_promedio_entrega_min'] as num?)?.toInt() ?? 0,
          ranking: (miHoyRow?['ranking_dia'] as num?)?.toInt() ?? 1,
          esMasRapido: miHoyRow?['es_mas_rapido_dia'] == true,
        );

        final masRapidoInfo = masRapidoRow != null
            ? MasRapidoInfo(
                cadeteId: masRapidoRow['cadete_id']?.toString() ?? '',
                nombre: masRapidoRow['cadete_nombre']?.toString() ?? 'Cadete',
                velocidad: (masRapidoRow['velocidad_media_movimiento'] as num?)
                        ?.toDouble() ??
                    0.0,
                esPropio: miRendimientoHoy.esMasRapido,
              )
            : null;

        final historial = semanasList.map((s) {
          return RendimientoSemanaHistorica.fromJson(
              Map<String, dynamic>.from(s));
        }).toList();

        final RendimientoSemanaActual semanaActual = historial.isNotEmpty
            ? RendimientoSemanaActual(
                semanaNumero: historial.first.semanaNumero,
                anio: historial.first.anio,
                semanaInicio: historial.first.semanaInicio,
                semanaFin: historial.first.semanaFin,
                pedidosEntregados: historial.first.pedidosEntregados,
                kmTotales: historial.first.kmTotales,
                velocidadMediaMovimiento:
                    historial.first.velocidadMediaMovimiento,
                velocidadMaxima: historial.first.velocidadMaxima,
                tiempoPromedioEntregaMin:
                    historial.first.tiempoPromedioEntregaMin,
                ranking: historial.first.posicionRanking,
                esMasRapido: historial.first.esMasRapidoSemana,
              )
            : const RendimientoSemanaActual();

        return RendimientoCompletoData(
          cadeteId: cadeteId,
          cadeteNombre: miHoyRow?['cadete_nombre']?.toString() ?? cadeteId,
          fechaNegocio: fechaHoyStr,
          miHoy: miRendimientoHoy,
          masRapidoHoy: masRapidoInfo,
          rankingHoy: [],
          miSemana: semanaActual,
          masRapidoSemana: null,
          rankingSemana: [],
          historialSemanas: historial,
          esDesdeCache: false,
        );
      }
    } catch (_) {
      // Continuar con caché local
    }

    // 3. Fallback Offline Local: Leer desde SharedPreferences
    final cachedStr = prefs?.getString(cacheKey);
    if (cachedStr != null && cachedStr.isNotEmpty) {
      try {
        final cachedData = jsonDecode(cachedStr) as Map<String, dynamic>;
        return RendimientoCompletoData.fromJson(cachedData,
            esDesdeCache: true);
      } catch (_) {}
    }

    return null;
  }
}
