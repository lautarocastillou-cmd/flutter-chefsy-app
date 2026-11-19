import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ChangelogLog extends StatelessWidget {
  const ChangelogLog({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF011410),
      appBar: AppBar(
        backgroundColor: const Color(0xFF011410),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Historial de Actualizaciones',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
        ),
        centerTitle: true,
      ),
      body: FutureBuilder(
        future: _obtenerChangelog(),
        builder: (context, snapshot) {
          final versiones = snapshot.data ?? _versionesFallback();
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: versiones.length,
            itemBuilder: (context, idx) {
              final v = versiones[idx];
              return _tarjetaVersion(context, v);
            },
          );
        },
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _obtenerChangelog() async {
    try {
      final res = await ApiService().fetchChangelog();
      if (res != null) return res;
    } catch (_) {}
    return _versionesFallback();
  }

  List<Map<String, dynamic>> _versionesFallback() {
    return [
      {
        'version': '1.0.6',
        'build': 9,
        'fecha': '2026-11-18',
        'estado': 'publicada',
        'cambios': [
          {'tipo': 'correccion', 'texto': 'Criterio online de cadetes: ahora requiere GPS reciente (3 min) y coordenadas válidas.'},
          {'tipo': 'correccion', 'texto': 'Conteo de paradas: entregas finalizadas ya no cuentan como paradas pendientes.'},
          {'tipo': 'correccion', 'texto': 'Header: ya no muestra "Pedido X entregado" cuando va directo al domicilio (1 solo pedido).'},
          {'tipo': 'actualizacion', 'texto': 'Consumos de personal: se puede excluir a personas que ya no trabajan sin borrar su historial.'},
          {'tipo': 'actualizacion', 'texto': 'Timers de pedidos: ya no se reinician a 00:00 al pasar a "En Camino" ni al copiar link de seguimiento.'},
        ],
      },
      {
        'version': '1.0.5',
        'build': 8,
        'fecha': '2026-11-15',
        'estado': 'publicada',
        'cambios': [
          {'tipo': 'feature', 'texto': 'Panel de simulación de GPS para desarrolladores (doble tap en el logo).'},
          {'tipo': 'feature', 'texto': 'Informe de rendimiento de cadetes con velocidad y ranking.'},
          {'tipo': 'actualizacion', 'texto': 'Polling de pedidos reducido a 3 segundos.'},
        ],
      },
      {
        'version': '1.0.4',
        'build': 7,
        'fecha': '2026-11-10',
        'estado': 'publicada',
        'cambios': [
          {'tipo': 'feature', 'texto': 'Primera versión estable del portal de cadetes con rastreo GPS en segundo plano.'},
          {'tipo': 'feature', 'texto': 'Asignación de pedidos, cambio de estado y pagos extras.'},
        ],
      },
    ];
  }

  Widget _tarjetaVersion(BuildContext context, Map<String, dynamic> v) {
    final cambios = (v['cambios'] as List? ?? [])
        .map((c) => Map<String, dynamic>.from(c as Map))
        .toList();

    Color colorEstado;
    switch (v['estado']) {
      case 'publicada':
        colorEstado = const Color(0xFF10B981);
        break;
      case 'beta':
        colorEstado = const Color(0xFFFBBF24);
        break;
      default:
        colorEstado = Colors.white54;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF02241E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colorEstado.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: colorEstado.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    v['estado'] == 'publicada' ? 'PUBLICADA' : 'BETA',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      color: colorEstado,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'v${v['version']}',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Build ${v['build']} · ${v['fecha']}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ...cambios.map((c) {
            Color tipoColor;
            IconData tipoIcono;
            switch (c['tipo']) {
              case 'feature':
                tipoColor = const Color(0xFF3B82F6);
                tipoIcono = Icons.star_rounded;
                break;
              case 'actualizacion':
                tipoColor = const Color(0xFF10B981);
                tipoIcono = Icons.update_rounded;
                break;
              case 'correccion':
                tipoColor = const Color(0xFFF59E0B);
                tipoIcono = Icons.bug_report_rounded;
                break;
              default:
                tipoColor = Colors.white54;
                tipoIcono = Icons.info_rounded;
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(tipoIcono, size: 16, color: tipoColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      c['texto'],
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white70,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }
}
