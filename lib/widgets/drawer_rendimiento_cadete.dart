import 'package:flutter/material.dart';
import '../models/rendimiento_model.dart';

class DrawerRendimientoCadete extends StatefulWidget {
  final RendimientoCompletoData? rendimiento;
  final VoidCallback? onRefrescar;

  const DrawerRendimientoCadete({
    super.key,
    this.rendimiento,
    this.onRefrescar,
  });

  @override
  State<DrawerRendimientoCadete> createState() =>
      _DrawerRendimientoCadeteState();
}

class _DrawerRendimientoCadeteState extends State<DrawerRendimientoCadete> {
  int _tabSeleccionada = 0; // 0 = Hoy, 1 = Esta Semana, 2 = Historial

  @override
  Widget build(BuildContext context) {
    final rend = widget.rendimiento;

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.88,
      backgroundColor: const Color(0xFF012421),
      child: SafeArea(
        child: Column(
          children: [
            // Cabecera de la Barra Lateral
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                            'Rendimiento & Podio',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            rend?.esDesdeCache == true
                                ? 'Copia local sin conexión'
                                : 'Telemetría de velocidad',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: rend?.esDesdeCache == true
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

            // Selector de Pestañas
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  children: [
                    _construirBotonTab(0, 'Hoy', Icons.today_rounded),
                    _construirBotonTab(1, 'Semana', Icons.calendar_view_week_rounded),
                    _construirBotonTab(2, 'Historial', Icons.history_rounded),
                  ],
                ),
              ),
            ),

            // Contenido con Scroll
            Expanded(
              child: rend == null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Color(0xFF34D399),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Calculando métricas y ranking...',
                            style: TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                          const SizedBox(height: 12),
                          TextButton.icon(
                            onPressed: widget.onRefrescar,
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text('Reintentar'),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF34D399),
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      children: [
                        if (_tabSeleccionada == 0) ...[
                          _construirHeroMasRapido(
                            esPropio: rend.miHoy.esMasRapido,
                            masRapido: rend.masRapidoHoy,
                            miVelocidad: rend.miHoy.velocidadMediaMovimiento,
                            subtitulo: 'Récord de velocidad de hoy en rodaje',
                          ),
                          const SizedBox(height: 12),
                          _construirGridMetricas(
                            velocidadMedia: rend.miHoy.velocidadMediaMovimiento,
                            velocidadMaxima: rend.miHoy.velocidadMaxima,
                            kmTotales: rend.miHoy.kmTotales,
                            pedidos: rend.miHoy.pedidosEntregados,
                            tiempoPromedioMin:
                                rend.miHoy.tiempoPromedioEntregaMin,
                            rankingPos: rend.miHoy.ranking,
                          ),
                          const SizedBox(height: 18),
                          _construirSeccionRanking(
                            titulo: '🏆 PODIO DE LA JORNADA',
                            ranking: rend.rankingHoy,
                            cadeteActualId: rend.cadeteId,
                          ),
                        ] else if (_tabSeleccionada == 1) ...[
                          _construirHeroMasRapido(
                            esPropio: rend.miSemana.esMasRapido,
                            masRapido: rend.masRapidoSemana,
                            miVelocidad: rend.miSemana.velocidadMediaMovimiento,
                            subtitulo:
                                'Semana #${rend.miSemana.semanaNumero} (${rend.miSemana.semanaInicio} al ${rend.miSemana.semanaFin})',
                          ),
                          const SizedBox(height: 12),
                          _construirGridMetricas(
                            velocidadMedia:
                                rend.miSemana.velocidadMediaMovimiento,
                            velocidadMaxima: rend.miSemana.velocidadMaxima,
                            kmTotales: rend.miSemana.kmTotales,
                            pedidos: rend.miSemana.pedidosEntregados,
                            tiempoPromedioMin:
                                rend.miSemana.tiempoPromedioEntregaMin,
                            rankingPos: rend.miSemana.ranking,
                          ),
                          const SizedBox(height: 18),
                          _construirSeccionRanking(
                            titulo: '🏆 PODIO SEMANAL',
                            ranking: rend.rankingSemana,
                            cadeteActualId: rend.cadeteId,
                          ),
                        ] else ...[
                          _construirHistorialSemanas(rend.historialSemanas),
                        ],
                      ],
                    ),
            ),

            // Barra inferior con botón de refresco
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.25),
                border: Border(
                  top: BorderSide(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: rend?.esDesdeCache == true
                              ? Colors.amberAccent
                              : const Color(0xFF10B981),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        rend?.esDesdeCache == true
                            ? 'Caché local activa'
                            : 'Sincronizado con Supabase',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white54,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: widget.onRefrescar,
                    child: const Row(
                      children: [
                        Icon(Icons.refresh_rounded,
                            size: 14, color: Color(0xFF34D399)),
                        SizedBox(width: 4),
                        Text(
                          'Actualizar',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF34D399),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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
                size: 13,
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: esPropio
              ? [const Color(0xFF065F46), const Color(0xFF047857)]
              : [const Color(0xFF1E293B), const Color(0xFF0F172A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: esPropio
              ? const Color(0xFF34D399)
              : Colors.amber.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.emoji_events_rounded,
                  color: Color(0xFFFBBF24),
                  size: 20,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      esPropio
                          ? '👑 ¡SOS EL MÁS RÁPIDO!'
                          : (hayGanador
                              ? '🏆 MÁS RÁPIDO: ${masRapido.nombre.toUpperCase()}'
                              : '🏁 EN DISPUTA'),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitulo,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              if (hayGanador)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFFBBF24).withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    '${masRapido.velocidad.toStringAsFixed(1)} km/h',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFFBBF24),
                    ),
                  ),
                ),
            ],
          ),
          if (!esPropio && hayGanador && miVelocidad > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.speed_rounded,
                      size: 13, color: Color(0xFF34D399)),
                  const SizedBox(width: 5),
                  Text(
                    'Tu velocidad: ${miVelocidad.toStringAsFixed(1)} km/h',
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
            Expanded(
              child: _construirTarjetaMetrica(
                titulo: 'VEL. MEDIA',
                valor: velocidadMedia > 0
                    ? '${velocidadMedia.toStringAsFixed(1)} km/h'
                    : '-- km/h',
                subtexto: 'En marcha',
                icono: Icons.speed_rounded,
                colorIcono: const Color(0xFF34D399),
                bordeColor: const Color(0xFF10B981).withValues(alpha: 0.3),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _construirTarjetaMetrica(
                titulo: 'VEL. PICO',
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
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _construirTarjetaMetrica(
                titulo: 'DISTANCIA',
                valor: '${kmTotales.toStringAsFixed(1)} km',
                subtexto: '$pedidos pedidos',
                icono: Icons.navigation_rounded,
                colorIcono: Colors.blue.shade300,
                bordeColor: Colors.blue.withValues(alpha: 0.25),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _construirTarjetaMetrica(
                titulo: rankingPos > 0 ? 'RANKING' : 'PROMEDIO',
                valor: rankingPos > 0
                    ? '#$rankingPos de flota'
                    : (tiempoPromedioMin > 0 ? '$tiempoPromedioMin min' : '--'),
                subtexto: tiempoPromedioMin > 0
                    ? '$tiempoPromedioMin min/viaje'
                    : 'Posición',
                icono: rankingPos > 0
                    ? Icons.leaderboard_rounded
                    : Icons.timer_rounded,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF023631),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bordeColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icono, size: 13, color: colorIcono),
              const SizedBox(width: 4),
              Text(
                titulo,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: colorIcono,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            valor,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            subtexto,
            style: const TextStyle(
              fontSize: 9,
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
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Icon(Icons.sports_motorsports_rounded,
                  size: 36, color: Colors.white.withValues(alpha: 0.2)),
              const SizedBox(height: 6),
              const Text(
                'Sin datos de telemetría todavía.',
                style: TextStyle(fontSize: 11, color: Colors.white54),
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
        const SizedBox(height: 6),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: ranking.length,
          separatorBuilder: (_, __) => const SizedBox(height: 5),
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: esPropio
                    ? const Color(0xFF10B981).withValues(alpha: 0.15)
                    : const Color(0xFF023631),
                borderRadius: BorderRadius.circular(10),
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
                    width: 24,
                    child: Text(
                      medalla,
                      style: TextStyle(
                        fontSize: cad.posicion <= 3 ? 15 : 11,
                        fontWeight: FontWeight.w900,
                        color: medallaColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              cad.nombre,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: esPropio
                                    ? const Color(0xFF34D399)
                                    : Colors.white,
                              ),
                            ),
                            if (esPropio) ...[
                              const SizedBox(width: 5),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'VOS',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF012B27),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          '${cad.pedidosEntregados} pedidos • ${cad.kmTotales.toStringAsFixed(1)} km',
                          style: const TextStyle(
                            fontSize: 9,
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
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF34D399),
                        ),
                      ),
                      Text(
                        'Pico: ${cad.velocidadMaxima.toStringAsFixed(0)} km/h',
                        style: const TextStyle(
                          fontSize: 8,
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
          padding: const EdgeInsets.symmetric(vertical: 30.0),
          child: Column(
            children: [
              Icon(Icons.calendar_month_rounded,
                  size: 40, color: Colors.white.withValues(alpha: 0.2)),
              const SizedBox(height: 10),
              const Text(
                'Aún no hay semanas completas archivadas.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 4),
              const Text(
                'Los registros se sincronizan automáticamente en Supabase.',
                style: TextStyle(color: Colors.white38, fontSize: 10),
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
          '📅 HISTORIAL DE SEMANAS (SUPABASE)',
          style: TextStyle(
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
          itemCount: historial.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, idx) {
            final sem = historial[idx];
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF023631),
                borderRadius: BorderRadius.circular(14),
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
                            size: 15,
                            color: sem.esMasRapidoSemana
                                ? const Color(0xFFFBBF24)
                                : const Color(0xFF34D399),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Semana #${sem.semanaNumero} - ${sem.anio}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      if (sem.esMasRapidoSemana)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFBBF24).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: const Color(0xFFFBBF24).withValues(alpha: 0.4)),
                          ),
                          child: const Row(
                            children: [
                              Text('👑 ', style: TextStyle(fontSize: 9)),
                              Text(
                                'MÁS RÁPIDO',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFFFBBF24),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Del ${sem.semanaInicio} al ${sem.semanaFin}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.white54,
                    ),
                  ),
                  const Divider(height: 14, color: Colors.white12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _construirItemHistorial(
                        'VEL. MEDIA',
                        '${sem.velocidadMediaMovimiento.toStringAsFixed(1)} km/h',
                        const Color(0xFF34D399),
                      ),
                      _construirItemHistorial(
                        'PICO',
                        '${sem.velocidadMaxima.toStringAsFixed(0)} km/h',
                        const Color(0xFFFBBF24),
                      ),
                      _construirItemHistorial(
                        'KM',
                        sem.kmTotales.toStringAsFixed(1),
                        Colors.blue.shade300,
                      ),
                      _construirItemHistorial(
                        'ENVÍOS',
                        sem.pedidosEntregados.toString(),
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
        const SizedBox(height: 1),
        Text(
          valor,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: valorColor,
          ),
        ),
      ],
    );
  }
}
