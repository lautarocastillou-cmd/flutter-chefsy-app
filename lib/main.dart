import 'package:flutter/material.dart';
import 'background_service.dart';
import 'screens/login_screen.dart';
import 'screens/portal_screen.dart';
import 'services/auth_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Inicializar configuración del foreground task (sin arrancarlo todavía)
  initForegroundTask();
  runApp(const ChefsyCadeteApp());
}

class ChefsyCadeteApp extends StatefulWidget {
  const ChefsyCadeteApp({super.key});

  @override
  State<ChefsyCadeteApp> createState() => _ChefsyCadeteAppState();
}

class _ChefsyCadeteAppState extends State<ChefsyCadeteApp> {
  String? _cadeteId;
  String? _cadeteNombre;
  bool _cargando = true;
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _cargarSesion();
  }

  Future<void> _cargarSesion() async {
    final sesion = await _authService.obtenerSesion();
    setState(() {
      _cadeteId = sesion['id'];
      _cadeteNombre = sesion['nombre'];
      _cargando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    return MaterialApp(
      title: 'Chefsy Cadetería',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: _cadeteId == null
          ? LoginScreen(
              onLoginSuccess: (id, nombre) {
                setState(() {
                  _cadeteId = id;
                  _cadeteNombre = nombre;
                });
              },
            )
          : PortalScreen(
              cadeteId: _cadeteId!,
              cadeteNombre: _cadeteNombre!,
              onLogout: () {
                setState(() {
                  _cadeteId = null;
                  _cadeteNombre = null;
                });
              },
            ),
    );
  }
}
