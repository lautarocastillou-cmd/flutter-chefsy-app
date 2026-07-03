import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// URL de la API pública en Chefsy para recibir posiciones de cadetes
const String API_URL = 'https://chefsy.xyz/api/public/ubicacion';
const String EXPO_SECRET_TOKEN = 'chefsy_expo_secure_track_99XQ';

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'chefsy_tracking',
      initialNotificationTitle: '🛵 Chefsy Cadetería',
      initialNotificationContent: 'Transmitiendo ubicación GPS en segundo plano...',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
    ),
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  service.on('stopService').listen((event) {
    service.stopSelf();
  });

  // Temporizador cada 6 segundos para no drenar batería agresivamente pero mantener un rastro suave
  Timer.periodic(const Duration(seconds: 6), (timer) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cadeteId = prefs.getString('cadete_id');
      
      if (cadeteId == null || cadeteId.isEmpty) return;

      // Obtener posición actual con alta precisión (GPS real)
      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      );

      // Si la precisión es muy mala (> 45 metros), ignorar el salto
      if (position.accuracy > 45) {
        return;
      }

      final response = await http.post(
        Uri.parse(API_URL),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $EXPO_SECRET_TOKEN',
        },
        body: jsonEncode({
          'cadeteId': cadeteId,
          'lat': position.latitude,
          'lng': position.longitude,
          'accuracy': position.accuracy,
          'speed': position.speed,
          'heading': position.heading,
        }),
      );

      if (response.statusCode == 200) {
        // Enviar actualización a la interfaz visual si la app está en primer plano
        service.invoke(
          'updatePosition',
          {
            'lat': position.latitude,
            'lng': position.longitude,
            'time': DateTime.now().toIso8601String(),
          },
        );
      }
    } catch (e) {
      // Manejo de errores silencioso para que el servicio no muera ante fallos de red o zonas sin señal
    }
  });
}
