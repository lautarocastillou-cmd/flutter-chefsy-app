import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String _keyCadeteId = 'cadete_id';
  static const String _keyCadeteNombre = 'cadete_nombre';
  
  static const String _keySimulacionActiva = 'simulacion_activa';
  static const String _keySimLat = 'sim_lat';
  static const String _keySimLng = 'sim_lng';

  // --- Sesión del Cadete ---
  Future<void> guardarSesion(String id, String nombre) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCadeteId, id);
    await prefs.setString(_keyCadeteNombre, nombre);
  }

  Future<void> borrarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyCadeteId);
    await prefs.remove(_keyCadeteNombre);
  }

  Future<Map<String, String?>> obtenerSesion() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'id': prefs.getString(_keyCadeteId),
      'nombre': prefs.getString(_keyCadeteNombre),
    };
  }

  // --- Modo Simulación ---
  Future<bool> isSimulacionActiva() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keySimulacionActiva) ?? false;
  }

  Future<void> setSimulacionActiva(bool activa) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySimulacionActiva, activa);
  }

  Future<Map<String, double>> obtenerSimCoordenadas() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'lat': prefs.getDouble(_keySimLat) ?? -32.8894, // Ubicación por defecto de Mendoza si no hay nada
      'lng': prefs.getDouble(_keySimLng) ?? -68.8458,
    };
  }

  Future<void> guardarSimCoordenadas(double lat, double lng) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_keySimLat, lat);
    await prefs.setDouble(_keySimLng, lng);
  }
}
