class RendimientoCadeteHoy {
  final int pedidosEntregados;
  final double kmTotales;
  final double velocidadMediaMovimiento;
  final double velocidadMaxima;
  final int tiempoPromedioEntregaMin;
  final int ranking;
  final bool esMasRapido;

  const RendimientoCadeteHoy({
    this.pedidosEntregados = 0,
    this.kmTotales = 0.0,
    this.velocidadMediaMovimiento = 0.0,
    this.velocidadMaxima = 0.0,
    this.tiempoPromedioEntregaMin = 0,
    this.ranking = 0,
    this.esMasRapido = false,
  });

  factory RendimientoCadeteHoy.fromJson(Map<String, dynamic> json) {
    return RendimientoCadeteHoy(
      pedidosEntregados: (json['pedidos_entregados'] as num?)?.toInt() ?? 0,
      kmTotales: (json['km_totales'] as num?)?.toDouble() ?? 0.0,
      velocidadMediaMovimiento:
          (json['velocidad_media_movimiento'] as num?)?.toDouble() ?? 0.0,
      velocidadMaxima: (json['velocidad_maxima'] as num?)?.toDouble() ?? 0.0,
      tiempoPromedioEntregaMin:
          (json['tiempo_promedio_entrega_min'] as num?)?.toInt() ?? 0,
      ranking: (json['ranking'] as num?)?.toInt() ?? 0,
      esMasRapido: json['es_mas_rapido'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'pedidos_entregados': pedidosEntregados,
        'km_totales': kmTotales,
        'velocidad_media_movimiento': velocidadMediaMovimiento,
        'velocidad_maxima': velocidadMaxima,
        'tiempo_promedio_entrega_min': tiempoPromedioEntregaMin,
        'ranking': ranking,
        'es_mas_rapido': esMasRapido,
      };
}

class MasRapidoInfo {
  final String cadeteId;
  final String nombre;
  final double velocidad;
  final bool esPropio;

  const MasRapidoInfo({
    required this.cadeteId,
    required this.nombre,
    required this.velocidad,
    required this.esPropio,
  });

  factory MasRapidoInfo.fromJson(Map<String, dynamic> json) {
    return MasRapidoInfo(
      cadeteId: json['cadete_id']?.toString() ?? '',
      nombre: json['nombre']?.toString() ?? 'Cadete',
      velocidad: (json['velocidad'] as num?)?.toDouble() ?? 0.0,
      esPropio: json['es_propio'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'cadete_id': cadeteId,
        'nombre': nombre,
        'velocidad': velocidad,
        'es_propio': esPropio,
      };
}

class ItemRankingCadete {
  final int posicion;
  final String cadeteId;
  final String nombre;
  final double velocidadMedia;
  final double velocidadMaxima;
  final int pedidosEntregados;
  final double kmTotales;
  final bool esMasRapido;

  const ItemRankingCadete({
    required this.posicion,
    required this.cadeteId,
    required this.nombre,
    required this.velocidadMedia,
    required this.velocidadMaxima,
    required this.pedidosEntregados,
    required this.kmTotales,
    required this.esMasRapido,
  });

  factory ItemRankingCadete.fromJson(Map<String, dynamic> json) {
    return ItemRankingCadete(
      posicion: (json['posicion'] as num?)?.toInt() ?? 0,
      cadeteId: json['cadete_id']?.toString() ?? '',
      nombre: json['nombre']?.toString() ?? 'Cadete',
      velocidadMedia: (json['velocidad_media'] as num?)?.toDouble() ?? 0.0,
      velocidadMaxima: (json['velocidad_maxima'] as num?)?.toDouble() ?? 0.0,
      pedidosEntregados: (json['pedidos_entregados'] as num?)?.toInt() ?? 0,
      kmTotales: (json['km_totales'] as num?)?.toDouble() ?? 0.0,
      esMasRapido: json['es_mas_rapido'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'posicion': posicion,
        'cadete_id': cadeteId,
        'nombre': nombre,
        'velocidad_media': velocidadMedia,
        'velocidad_maxima': velocidadMaxima,
        'pedidos_entregados': pedidosEntregados,
        'km_totales': kmTotales,
        'es_mas_rapido': esMasRapido,
      };
}

class RendimientoSemanaActual {
  final int semanaNumero;
  final int anio;
  final String semanaInicio;
  final String semanaFin;
  final int pedidosEntregados;
  final double kmTotales;
  final double velocidadMediaMovimiento;
  final double velocidadMaxima;
  final int tiempoPromedioEntregaMin;
  final int ranking;
  final bool esMasRapido;

  const RendimientoSemanaActual({
    this.semanaNumero = 0,
    this.anio = 0,
    this.semanaInicio = '',
    this.semanaFin = '',
    this.pedidosEntregados = 0,
    this.kmTotales = 0.0,
    this.velocidadMediaMovimiento = 0.0,
    this.velocidadMaxima = 0.0,
    this.tiempoPromedioEntregaMin = 0,
    this.ranking = 0,
    this.esMasRapido = false,
  });

  factory RendimientoSemanaActual.fromJson(Map<String, dynamic> json) {
    return RendimientoSemanaActual(
      semanaNumero: (json['semana_numero'] as num?)?.toInt() ?? 0,
      anio: (json['anio'] as num?)?.toInt() ?? 0,
      semanaInicio: json['semana_inicio']?.toString() ?? '',
      semanaFin: json['semana_fin']?.toString() ?? '',
      pedidosEntregados: (json['pedidos_entregados'] as num?)?.toInt() ?? 0,
      kmTotales: (json['km_totales'] as num?)?.toDouble() ?? 0.0,
      velocidadMediaMovimiento:
          (json['velocidad_media_movimiento'] as num?)?.toDouble() ?? 0.0,
      velocidadMaxima: (json['velocidad_maxima'] as num?)?.toDouble() ?? 0.0,
      tiempoPromedioEntregaMin:
          (json['tiempo_promedio_entrega_min'] as num?)?.toInt() ?? 0,
      ranking: (json['ranking'] as num?)?.toInt() ?? 0,
      esMasRapido: json['es_mas_rapido'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'semana_numero': semanaNumero,
        'anio': anio,
        'semana_inicio': semanaInicio,
        'semana_fin': semanaFin,
        'pedidos_entregados': pedidosEntregados,
        'km_totales': kmTotales,
        'velocidad_media_movimiento': velocidadMediaMovimiento,
        'velocidad_maxima': velocidadMaxima,
        'tiempo_promedio_entrega_min': tiempoPromedioEntregaMin,
        'ranking': ranking,
        'es_mas_rapido': esMasRapido,
      };
}

class RendimientoSemanaHistorica {
  final String? id;
  final int anio;
  final int semanaNumero;
  final String semanaInicio;
  final String semanaFin;
  final int pedidosEntregados;
  final double kmTotales;
  final double velocidadMediaMovimiento;
  final double velocidadMaxima;
  final int tiempoPromedioEntregaMin;
  final bool esMasRapidoSemana;
  final int posicionRanking;

  const RendimientoSemanaHistorica({
    this.id,
    required this.anio,
    required this.semanaNumero,
    required this.semanaInicio,
    required this.semanaFin,
    required this.pedidosEntregados,
    required this.kmTotales,
    required this.velocidadMediaMovimiento,
    required this.velocidadMaxima,
    required this.tiempoPromedioEntregaMin,
    required this.esMasRapidoSemana,
    required this.posicionRanking,
  });

  factory RendimientoSemanaHistorica.fromJson(Map<String, dynamic> json) {
    return RendimientoSemanaHistorica(
      id: json['id']?.toString(),
      anio: (json['anio'] as num?)?.toInt() ?? 0,
      semanaNumero: (json['semana_numero'] as num?)?.toInt() ?? 0,
      semanaInicio: json['semana_inicio']?.toString() ?? '',
      semanaFin: json['semana_fin']?.toString() ?? '',
      pedidosEntregados: (json['pedidos_entregados'] as num?)?.toInt() ?? 0,
      kmTotales: (json['km_totales'] as num?)?.toDouble() ?? 0.0,
      velocidadMediaMovimiento:
          (json['velocidad_media_movimiento'] as num?)?.toDouble() ?? 0.0,
      velocidadMaxima: (json['velocidad_maxima'] as num?)?.toDouble() ?? 0.0,
      tiempoPromedioEntregaMin:
          (json['tiempo_promedio_entrega_min'] as num?)?.toInt() ?? 0,
      esMasRapidoSemana: json['es_mas_rapido_semana'] == true,
      posicionRanking: (json['posicion_ranking'] as num?)?.toInt() ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'anio': anio,
        'semana_numero': semanaNumero,
        'semana_inicio': semanaInicio,
        'semana_fin': semanaFin,
        'pedidos_entregados': pedidosEntregados,
        'km_totales': kmTotales,
        'velocidad_media_movimiento': velocidadMediaMovimiento,
        'velocidad_maxima': velocidadMaxima,
        'tiempo_promedio_entrega_min': tiempoPromedioEntregaMin,
        'es_mas_rapido_semana': esMasRapidoSemana,
        'posicion_ranking': posicionRanking,
      };
}

class RendimientoCompletoData {
  final String cadeteId;
  final String cadeteNombre;
  final String fechaNegocio;
  final RendimientoCadeteHoy miHoy;
  final MasRapidoInfo? masRapidoHoy;
  final List<ItemRankingCadete> rankingHoy;
  final RendimientoSemanaActual miSemana;
  final MasRapidoInfo? masRapidoSemana;
  final List<ItemRankingCadete> rankingSemana;
  final List<RendimientoSemanaHistorica> historialSemanas;
  final bool esDesdeCache;

  const RendimientoCompletoData({
    required this.cadeteId,
    required this.cadeteNombre,
    required this.fechaNegocio,
    required this.miHoy,
    this.masRapidoHoy,
    required this.rankingHoy,
    required this.miSemana,
    this.masRapidoSemana,
    required this.rankingSemana,
    required this.historialSemanas,
    this.esDesdeCache = false,
  });

  factory RendimientoCompletoData.fromJson(
    Map<String, dynamic> json, {
    bool esDesdeCache = false,
  }) {
    final hoyMap = json['hoy'] as Map<String, dynamic>? ?? {};
    final miHoyMap = hoyMap['mi_rendimiento'] as Map<String, dynamic>? ?? {};
    final masRapidoHoyMap = hoyMap['mas_rapido'] as Map<String, dynamic>?;
    final rankingHoyList = (hoyMap['ranking'] as List?) ?? [];

    final semanaMap = json['semana_actual'] as Map<String, dynamic>? ?? {};
    final miSemanaMap =
        semanaMap['mi_rendimiento'] as Map<String, dynamic>? ?? {};
    final masRapidoSemanaMap =
        semanaMap['mas_rapido'] as Map<String, dynamic>?;
    final rankingSemanaList = (semanaMap['ranking'] as List?) ?? [];

    final historialList = (json['historial_semanas'] as List?) ?? [];

    return RendimientoCompletoData(
      cadeteId: json['cadete_id']?.toString() ?? '',
      cadeteNombre: json['cadete_nombre']?.toString() ?? '',
      fechaNegocio: json['fecha_negocio']?.toString() ?? '',
      miHoy: RendimientoCadeteHoy.fromJson(miHoyMap),
      masRapidoHoy: masRapidoHoyMap != null
          ? MasRapidoInfo.fromJson(masRapidoHoyMap)
          : null,
      rankingHoy: rankingHoyList
          .map((i) => ItemRankingCadete.fromJson(Map<String, dynamic>.from(i)))
          .toList(),
      miSemana: RendimientoSemanaActual.fromJson(miSemanaMap),
      masRapidoSemana: masRapidoSemanaMap != null
          ? MasRapidoInfo.fromJson(masRapidoSemanaMap)
          : null,
      rankingSemana: rankingSemanaList
          .map((i) => ItemRankingCadete.fromJson(Map<String, dynamic>.from(i)))
          .toList(),
      historialSemanas: historialList
          .map((h) =>
              RendimientoSemanaHistorica.fromJson(Map<String, dynamic>.from(h)))
          .toList(),
      esDesdeCache: esDesdeCache,
    );
  }

  Map<String, dynamic> toJson() => {
        'cadete_id': cadeteId,
        'cadete_nombre': cadeteNombre,
        'fecha_negocio': fechaNegocio,
        'hoy': {
          'mi_rendimiento': miHoy.toJson(),
          if (masRapidoHoy != null) 'mas_rapido': masRapidoHoy!.toJson(),
          'ranking': rankingHoy.map((r) => r.toJson()).toList(),
        },
        'semana_actual': {
          'mi_rendimiento': miSemana.toJson(),
          if (masRapidoSemana != null)
            'mas_rapido': masRapidoSemana!.toJson(),
          'ranking': rankingSemana.map((r) => r.toJson()).toList(),
        },
        'historial_semanas':
            historialSemanas.map((h) => h.toJson()).toList(),
      };
}
