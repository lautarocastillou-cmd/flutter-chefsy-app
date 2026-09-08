import 'package:flutter/material.dart';
import '../models/rendimiento_model.dart';

class ModalRendimientoCadete extends StatefulWidget {
  final RendimientoCompletoData rendimiento;
  final VoidCallback? onRefrescar;

  const ModalRendimientoCadete({
    super.key,
    required this.rendimiento,
    this.onRefrescar,
  });

  static void mostrar(
    BuildContext context, {
    required RendimientoCompletoData rendimiento,
    VoidCallback? onRefrescar,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ModalRendimientoCadete(
        rendimiento: rendimiento,
        onRefrescar: onRefrescar,
      ),
    );
  }

  @override
  State<ModalRendimientoCadete> createState() => _ModalRendimientoCadeteState();
}

class _ModalRendimientoCadeteState extends State<ModalRendimientoCadete> {
  int _tabSeleccionada = 0; // 0 = Hoy, 1 = Esta Semana, 2 = Historial

  @override
  Widget build(BuildContext context) {
    final rend = widget.rendimiento;
    final miHoy = rend.miHoy;
    final miSemana = rend.miSemana;

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: Color(0xFF012421),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          // Barra de agarre superior
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 42,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),

          // Cabecera con título y botón de cierre
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.speed_rounded,
                        color: Color(0xFF34D399),
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Rendimiento & Récords',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          rend.esDesdeCache
                              ? 'Modo sin conexión (datos guardados)'
                              : 'Telemetría física en tiempo real',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: rend.esDesdeCache
                                ? Colors.amberAccent
                                : Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                ),
              ],
            ),
          ),

          // Selector de pestañas: Hoy / Esta Semana / Historial
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: Row(
                children: [
                  _construirBotonTab(0, 'Hoy', Icons.today_rounded),
                  _construirBotonTab(1, 'Semana Actual', Icons.calendar_view_week_rounded),
                  _construirBotonTab(2, 'Historial', Icons.history_rounded),
                ],
              ),
            ),
          ),

          // Contenido con scroll según pestaña
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_tabSeleccionada == 0) ...[
                  _construirHeroMasRapido(
                    esPropio: miHoy.esMasRapido,
                    masRapido: rend.masRapidoHoy,
                    miVelocidad: miHoy.velocidadMediaMovimiento,
                    subtitulo: 'Récord de velocidad de hoy en rodaje',
                  ),
                  const SizedBox(height: 14),
                  _construirGridMetricas(
                    velocidadMedia: miHoy.velocidadMediaMovimiento,
                    velocidadMaxima: miHoy.velocidadMaxima,
                    kmTotales: miHoy.kmTotales,
                    pedidos: miHoy.pedidosEntregados,
                    tiempoPromedioMin: miHoy.tiempoPromedioEntregaMin,
                    rankingPos: miHoy.ranking,
                  ),
                  const SizedBox(height: 20),
                  _construirSeccionRanking(
                    titulo: '🏆 PODIO DE LA JORNADA',
                    ranking: rend.rankingHoy,
                    cadeteActualId: rend.cadeteId,
                  ),
                ] else if (_tabSeleccionada == 1) ...[
                  _construirHeroMasRapido(
                    esPropio: miSemana.esMasRapido,
                    masRapido: rend.masRapidoSemana,
                    miVelocidad: miSemana.velocidadMediaMovimiento,
                    subtitulo:
                        'Semana #${miSemana.semanaNumero} (${miSemana.semanaInicio} al ${miSemana.semanaFin})',
                  ),
                  const SizedBox(height: 14),
                  _construirGridMetricas(
                    velocidadMedia: miSemana.velocidadMediaMovimiento,
                    velocidadMaxima: miSemana.velocidadMaxima,
                    kmTotales: miSemana.kmTotales,
                    pedidos: miSemana.pedidosEntregados,
                    tiempoPromedioMin: miSemana.tiempoPromedioEntregaMin,
                    rankingPos: miSemana.ranking,
                  ),
                  const SizedBox(height: 20),
                  _construirSeccionRanking(
                    titulo: '🏆 PODIO SEMANAL DE CADETES',
                    ranking: rend.rankingSemana,
                    cadeteActualId: rend.cadeteId,
                  ),
                ] else ...[
                  _construirHistorialSemanas(rend.historialSemanas),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirBotonTab(int index, String texto, IconData icono) {
    final activa = _tabSeleccionada == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tabSeleccionada = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: activa ? const Color(0xFF10B981) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icono,
                size: 14,
                color: activa ? const Color(0xFF012B27) : Colors.white70,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  texto,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: activa ? const Color(0xFF012B27) : Colors.white70,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _construirHeroMasRapido({
    required bool esPropio,
    required MasRapidoInfo? masRapido,
    required double miVelocidad,
    required String subtitulo,
  }) {
    final hayGanador = masRapido != null && masRapido.velocidad > 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: esPropio
              ? [const Color(0xFF065F46), const Color(0xFF047857)]
              : [const Color(0xFF1E293B), const Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: esPropio
              ? const Color(0xFF34D399)
              : Colors.amber.withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: esPropio
                ? const Color(0xFF10B981).withValues(alpha: 0.25)
                : Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.emoji_events_rounded,
                  color: Color(0xFFFBBF24),
                  size: 24,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      esPropio
                          ? '👑 ¡SOS EL MÁS RÁPIDO!'
                          : (hayGanador
                              ? '🏆 MÁS RÁPIDO: ${masRapido.nombre.toUpperCase()}'
                              : '🏁 EN DISPUTA DE VELOCIDAD'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitulo,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              if (hayGanador)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFFFBBF24).withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    '${masRapido.velocidad.toStringAsFixed(1)} km/h',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFFBBF24),
                    ),
                  ),
                ),
            ],
          ),
          if (!esPropio && hayGanador && miVelocidad > 0) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.speed_rounded,
                      size: 14, color: Color(0xFF34D399)),
                  const SizedBox(width: 6),
                  Text(
                    'Tu velocidad media: ${miVelocidad.toStringAsFixed(1)} km/h',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _construirGridMetricas({
    required double velocidadMedia,
    required double velocidadMaxima,
    required double kmTotales,
    required int pedidos,
    required int tiempoPromedioMin,
    required int rankingPos,
  }) {
    return Column(
      children: [
        Row(
          children: [
            // Card 1: Velocidad Media en Movimiento
            Expanded(
              child: _construirTarjetaMetrica(
                titulo: 'VELOCIDAD MEDIA',
                valor: velocidadMedia > 0
                    ? '${velocidadMedia.toStringAsFixed(1)} km/h'
                    : '-- km/h',
                subtexto: 'Calculada en marcha',
                icono: Icons.speed_rounded,
                colorIcono: const Color(0xFF34D399),
                bordeColor: const Color(0xFF10B981).withValues(alpha: 0.3),
              ),
            ),
            const SizedBox(width: 10),
            // Card 2: Velocidad Máxima Pico
            Expanded(
              child: _construirTarjetaMetrica(
                titulo: 'VELOCIDAD PICO',
                valor: velocidadMaxima > 0
                    ? '${velocidadMaxima.toStringAsFixed(0)} km/h'
                    : '-- km/h',
                subtexto: 'Máxima alcanzada',
                icono: Icons.bolt_rounded,
                colorIcono: const Color(0xFFFBBF24),
                bordeColor: const Color(0xFFFBBF24).withValues(alpha: 0.3),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            // Card 3: Kilómetros Totales
            Expanded(
              child: _construirTarjetaMetrica(
                titulo: 'DISTANCIA',
                valor: '${kmTotales.toStringAsFixed(1)} km',
                subtexto: '$pedidos envíos hechos',
                icono: Icons.navigation_rounded,
                colorIcono: Colors.blue.shade300,
                bordeColor: Colors.blue.withValues(alpha: 0.25),
              ),
            ),
            const SizedBox(width: 10),
            // Card 4: Tiempo Promedio o Posición
            Expanded(
              child: _construirTarjetaMetrica(
                titulo: rankingPos > 0 ? 'RANKING FLOTA' : 'TIEMPO PROMEDIO',
                valor: rankingPos > 0
                    ? '#$rankingPos en velocidad'
                    : (tiempoPromedioMin > 0 ? '$tiempoPromedioMin min' : '--'),
                subtexto: tiempoPromedioMin > 0
                    ? 'Promedio: $tiempoPromedioMin min/viaje'
                    : 'Posición de flota',
                icono: rankingPos > 0 ? Icons.leaderboard_rounded : Icons.timer_rounded,
                colorIcono: const Color(0xFFA78BFA),
                bordeColor: Colors.purple.withValues(alpha: 0.25),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _construirTarjetaMetrica({
    required String titulo,
    required String valor,
    required String subtexto,
    required IconData icono,
    required Color colorIcono,
    required Color bordeColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF023631),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: bordeColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, size: 14, color: colorIcono),
              const SizedBox(width: 5),
              Text(
                titulo,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: colorIcono,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            valor,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtexto,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: Colors.white54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _construirSeccionRanking({
    required String titulo,
    required List<ItemRankingCadete> ranking,
    required String cadeteActualId,
  }) {
    if (ranking.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            children: [
              Icon(Icons.sports_motorsports_rounded,
                  size: 40, color: Colors.white.withValues(alpha: 0.2)),
              const SizedBox(height: 8),
              const Text(
                'Aún no hay entregas con telemetría en este periodo.',
                style: TextStyle(fontSize: 12, color: Colors.white54),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final idNorm = cadeteActualId.toLowerCase().trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: Colors.white60,
          ),
        ),
        const SizedBox(height: 8),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: ranking.length,
          separatorBuilder: (_, __) => const SizedBox(height: 6),
          itemBuilder: (context, idx) {
            final cad = ranking[idx];
            final esPropio = cad.cadeteId.toLowerCase().trim() == idNorm ||
                cad.nombre.toLowerCase().trim() == idNorm;

            String medalla = '#${cad.posicion}';
            Color medallaColor = Colors.white70;
            if (cad.posicion == 1) {
              medalla = '🥇';
              medallaColor = const Color(0xFFFBBF24);
            } else if (cad.posicion == 2) {
              medalla = '🥈';
              medallaColor = Colors.grey.shade300;
            } else if (cad.posicion == 3) {
              medalla = '🥉';
              medallaColor = Colors.orange.shade300;
            }

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: esPropio
                    ? const Color(0xFF10B981).withValues(alpha: 0.15)
                    : const Color(0xFF023631),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: esPropio
                      ? const Color(0xFF34D399)
                      : Colors.white.withValues(alpha: 0.06),
                  width: esPropio ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      medalla,
                      style: TextStyle(
                        fontSize: cad.posicion <= 3 ? 16 : 12,
                        fontWeight: FontWeight.w900,
                        color: medallaColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              cad.nombre,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: esPropio
                                    ? const Color(0xFF34D399)
                                    : Colors.white,
                              ),
                            ),
                            if (esPropio) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'VOS',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF012B27),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${cad.pedidosEntregados} pedidos • ${cad.kmTotales.toStringAsFixed(1)} km',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${cad.velocidadMedia.toStringAsFixed(1)} km/h',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF34D399),
                        ),
                      ),
                      Text(
                        'Pico: ${cad.velocidadMaxima.toStringAsFixed(0)} km/h',
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.white38,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _construirHistorialSemanas(
      List<RendimientoSemanaHistorica> historial) {
    if (historial.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40.0),
          child: Column(
            children: [
              Icon(Icons.calendar_month_rounded,
                  size: 48, color: Colors.white.withValues(alpha: 0.2)),
              const SizedBox(height: 12),
              const Text(
                'Aún no hay semanas completas archivadas.',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 4),
              const Text(
                'Al finalizar cada turno y semana, los registros se sincronizan en Supabase.',
                style: TextStyle(color: Colors.white38, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '📅 HISTORIAL DE SEMANAS REGISTRADAS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: Colors.white60,
          ),
        ),
        const SizedBox(height: 10),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: historial.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, idx) {
            final sem = historial[idx];
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF023631),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: sem.esMasRapidoSemana
                      ? const Color(0xFFFBBF24).withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.08),
                  width: sem.esMasRapidoSemana ? 1.5 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            sem.esMasRapidoSemana
                                ? Icons.workspace_premium_rounded
                                : Icons.date_range_rounded,
                            size: 16,
                            color: sem.esMasRapidoSemana
                                ? const Color(0xFFFBBF24)
                                : const Color(0xFF34D399),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Semana #${sem.semanaNumero} - ${sem.anio}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      if (sem.esMasRapidoSemana)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFBBF24).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: const Color(0xFFFBBF24).withValues(alpha: 0.4)),
                          ),
                          child: const Row(
                            children: [
                              Text('👑 ', style: TextStyle(fontSize: 10)),
                              Text(
                                'MÁS RÁPIDO',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFFFBBF24),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Del ${sem.semanaInicio} al ${sem.semanaFin}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white54,
                    ),
                  ),
                  const Divider(height: 16, color: Colors.white12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _construirItemHistorial(
                        'VELOCIDAD MEDIA',
                        '${sem.velocidadMediaMovimiento.toStringAsFixed(1)} km/h',
                        const Color(0xFF34D399),
                      ),
                      _construirItemHistorial(
                        'VEL. MÁXIMA',
                        '${sem.velocidadMaxima.toStringAsFixed(0)} km/h',
                        const Color(0xFFFBBF24),
                      ),
                      _construirItemHistorial(
                        'DISTANCIA',
                        '${sem.kmTotales.toStringAsFixed(1)} km',
                        Colors.blue.shade300,
                      ),
                      _construirItemHistorial(
                        'ENVÍOS',
                        '${sem.pedidosEntregados}',
                        Colors.white70,
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _construirItemHistorial(String label, String valor, Color valorColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w800,
            color: Colors.white38,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          valor,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: valorColor,
          ),
        ),
      ],
    );
  }
}
