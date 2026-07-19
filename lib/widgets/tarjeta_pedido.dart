import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/pedido_model.dart';

class TarjetaPedidoCadete extends StatelessWidget {
  final PedidoModel pedido;
  final Function(String telefono, String cliente) onAbrirWhatsApp;
  final Function(String id, String nuevoEstado) onCambiarEstado;

  const TarjetaPedidoCadete({
    super.key,
    required this.pedido,
    required this.onAbrirWhatsApp,
    required this.onCambiarEstado,
  });

  void _llamarCliente(BuildContext context, String tel) async {
    if (tel == 'Sin especificar' || tel.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sin número de teléfono registrado.')),
      );
      return;
    }
    final cleanTel = tel.replaceAll(RegExp(r'\D'), '');
    final url = Uri.parse('tel:$cleanTel');
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        await launchUrl(url, mode: LaunchMode.platformDefault);
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir la app de llamadas.')),
      );
    }
  }

  void _abrirGoogleMaps(BuildContext context) async {
    final coords = pedido.coordenadas;
    List<Uri> uris = [];
    if (coords != null && coords.latitud != 0.0) {
      uris = [
        Uri.parse('google.navigation:q=${coords.latitud},${coords.longitud}'),
        Uri.parse('geo:${coords.latitud},${coords.longitud}?q=${coords.latitud},${coords.longitud}'),
        Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${coords.latitud},${coords.longitud}'),
      ];
    } else {
      final dir = pedido.direccion;
      if (dir.isEmpty || dir == 'Retiro en local') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Es un pedido para retiro en local.')),
        );
        return;
      }
      uris = [
        Uri.parse('geo:0,0?q=${Uri.encodeComponent(dir)}'),
        Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(dir)}'),
      ];
    }

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
        // Continuar intentando con el siguiente URI/modo
      }
    }

    if (!abierto && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir Google Maps en este dispositivo.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    Color colorEstadoBg = const Color(0xFF3B82F6).withValues(alpha: 0.18);
    Color colorEstadoText = const Color(0xFF60A5FA);
    if (pedido.estado == 'en_cocina') {
      colorEstadoBg = const Color(0xFFF59E0B).withValues(alpha: 0.18);
      colorEstadoText = const Color(0xFFFBBF24);
    } else if (pedido.estado == 'listo') {
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
            key: ValueKey('header_${pedido.id}'),
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pedido.cliente,
                      style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w900,
                          color: Colors.white),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          pedido.telefono == 'Sin especificar'
                              ? 'Tel: No especificado'
                              : 'Tel: ${pedido.telefono}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.white54),
                        ),
                        if (pedido.hora.isNotEmpty) ...[
                          const Text(' • ',
                              style: TextStyle(color: Colors.white38)),
                          Text(
                            pedido.hora,
                            style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white70,
                                fontWeight: FontWeight.bold),
                          ),
                        ]
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: colorEstadoBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  pedido.estado.toUpperCase().replaceAll('_', ' '),
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
              if (pedido.telefono != 'Sin especificar') ...[
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF334155),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.phone_rounded, size: 15),
                    label: const Text('Llamar',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: () => _llamarCliente(context, pedido.telefono),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.chat_bubble_rounded, size: 15),
                    label: const Text('WhatsApp',
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: () =>
                        onAbrirWhatsApp(pedido.telefono, pedido.cliente),
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
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.map_rounded, size: 15),
                  label: const Text('Maps',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold)),
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
                border: Border.all(
                    color: const Color(0xFFE11D48).withValues(alpha: 0.3)),
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
                      if (pedido.distanciaKm != null)
                        Text(
                          '(${pedido.distanciaKm!.toStringAsFixed(1)} km)',
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
                      const Icon(Icons.location_on_rounded,
                          size: 18, color: Color(0xFFF43F5E)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          pedido.direccion,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white),
                        ),
                      ),
                      const Icon(Icons.navigation_rounded,
                          size: 16, color: Colors.white38),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Lista de productos
          if (pedido.productos.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: pedido.productos.map((prod) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Text(
                      '${prod.cantidad}× ${prod.nombre}',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: prod.esBebida
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: prod.esBebida
                            ? const Color(0xFFF43F5E)
                            : Colors.white70,
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
              border: Border(
                  top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.1))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Cobrar',
                        style: TextStyle(fontSize: 11, color: Colors.white54)),
                    Text(
                      pedido.totalFormateado,
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Colors.white),
                    ),
                    if (pedido.costoEnvio != null && pedido.costoEnvio! > 0)
                      Text(
                        '(Incluye ${pedido.costoEnvioFormateado} envío)',
                        style: const TextStyle(
                            fontSize: 10, color: Colors.white38),
                      ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      pedido.metodoPago.toUpperCase(),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.white70),
                    ),
                    if (pedido.metodoPago.toLowerCase() ==
                        'transferencia') ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: pedido.pagoConfirmado
                              ? const Color(0xFF10B981).withValues(alpha: 0.2)
                              : const Color(0xFFF59E0B).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          pedido.pagoConfirmado
                              ? '✅ PAGADO'
                              : '❌ Pendiente Impactar',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: pedido.pagoConfirmado
                                  ? const Color(0xFF34D399)
                                  : const Color(0xFFFBBF24)),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Observaciones
          if (pedido.observaciones.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
              ),
              child: Text(
                '⚠️ ${pedido.observaciones}',
                style: const TextStyle(
                    color: Color(0xFFFDE68A),
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
              ),
            ),
          ],

          // Botón de Acción de Estado (Marcar como listo / Entregar)
          if (pedido.estado == 'en_cocina' ||
              pedido.estado == 'listo' ||
              pedido.estado == 'en_camino') ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: pedido.estado == 'en_cocina'
                      ? const Color(0xFF10B981)
                      : pedido.estado == 'listo'
                          ? const Color(0xFF3B82F6)
                          : const Color(0xFFE11D48),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 2,
                ),
                icon: Icon(
                  pedido.estado == 'en_cocina'
                      ? Icons.check_circle_outline_rounded
                      : Icons.delivery_dining_rounded,
                  size: 20,
                ),
                label: Text(
                  pedido.estado == 'en_cocina'
                      ? 'MARCAR COMO LISTO'
                      : pedido.estado == 'listo'
                          ? 'COMENZAR VIAJE'
                          : 'MARCAR COMO ENTREGADO',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8),
                ),
                onPressed: () {
                  final nuevoEstado =
                      pedido.estado == 'en_cocina' ? 'listo' : 
                      pedido.estado == 'listo' ? 'en_camino' : 'entregado';
                  onCambiarEstado(pedido.id, nuevoEstado);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
