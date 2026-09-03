class PedidoModel {
  final String id;
  final String cliente;
  final String telefono;
  final String hora;
  final String estado;
  final String direccion;
  final double? distanciaKm;
  final List<ProductoItem> productos;
  final double total;
  final double? costoEnvio;
  final String metodoPago;
  final bool pagoConfirmado;
  final String observaciones;
  final CoordenadasModel? coordenadas;

  PedidoModel({
    required this.id,
    required this.cliente,
    required this.telefono,
    required this.hora,
    required this.estado,
    required this.direccion,
    this.distanciaKm,
    required this.productos,
    required this.total,
    this.costoEnvio,
    required this.metodoPago,
    required this.pagoConfirmado,
    required this.observaciones,
    this.coordenadas,
  });

  PedidoModel copyWith({
    String? estado,
    bool? pagoConfirmado,
    CoordenadasModel? coordenadas,
    String? metodoPago,
  }) {
    return PedidoModel(
      id: id,
      cliente: cliente,
      telefono: telefono,
      hora: hora,
      estado: estado ?? this.estado,
      direccion: direccion,
      distanciaKm: distanciaKm,
      productos: productos,
      total: total,
      costoEnvio: costoEnvio,
      metodoPago: metodoPago ?? this.metodoPago,
      pagoConfirmado: pagoConfirmado ?? this.pagoConfirmado,
      observaciones: observaciones,
      coordenadas: coordenadas ?? this.coordenadas,
    );
  }

  factory PedidoModel.fromJson(Map<String, dynamic> json) {
    var prodsList = json['productos'] as List? ?? [];
    List<ProductoItem> items = prodsList
        .map((item) => ProductoItem.fromJson(Map<String, dynamic>.from(item)))
        .toList();

    CoordenadasModel? coords;
    if (json['coordenadas'] != null && json['coordenadas'] is Map) {
      coords = CoordenadasModel.fromJson(Map<String, dynamic>.from(json['coordenadas']));
    }

    return PedidoModel(
      id: json['id']?.toString() ?? '',
      cliente: json['cliente']?.toString() ?? 'Cliente',
      telefono: json['telefono']?.toString() ?? 'Sin especificar',
      hora: json['hora']?.toString() ?? '',
      estado: json['estado']?.toString() ?? '',
      direccion: json['direccion']?.toString() ?? 'Retiro en local',
      distanciaKm: json['distanciaKm'] != null
          ? double.tryParse(json['distanciaKm'].toString())
          : null,
      productos: items,
      total: double.tryParse(json['total']?.toString() ?? '0') ?? 0.0,
      costoEnvio: json['costoEnvio'] != null
          ? double.tryParse(json['costoEnvio'].toString())
          : (json['costo_envio'] != null
              ? double.tryParse(json['costo_envio'].toString())
              : null),
      metodoPago: json['metodoPago']?.toString() ?? '',
      pagoConfirmado: json['pago_confirmado'] == true,
      observaciones: json['observaciones']?.toString() ?? '',
      coordenadas: coords,
    );
  }

  static String formatearPrecio(double precio) {
    final absVal = precio.abs().toStringAsFixed(0);
    final strFormatted = absVal.replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.');
    return precio < 0 ? '-\$$strFormatted' : '\$$strFormatted';
  }

  String get totalFormateado => formatearPrecio(total);
  String get costoEnvioFormateado => costoEnvio != null ? formatearPrecio(costoEnvio!) : '\$0';

  /// Extrae inteligentemente si el cliente especificó con cuánto abona en las observaciones
  double? get montoPagaCliente {
    if (observaciones.trim().isEmpty) return null;
    final obs = observaciones.toLowerCase();

    // 1. Patrón común: "pago con $20.000", "paga con 20mil", "cambio de 10000", "billete de 20.000", "cambio para 20k"
    final regExp = RegExp(
      r'(?:pago\s+con|paga\s+con|abona\s+con|abono\s+con|cambio\s+(?:de|para)|billete\s+de|vuelto\s+(?:de|para)|llevar\s+cambio\s+de)\s*[:$]?\s*([0-9]{1,3}(?:\.[0-9]{3})*|[0-9]+)\s*(mil|k)?',
      caseSensitive: false,
    );

    final match = regExp.firstMatch(obs);
    if (match != null) {
      String rawNum = match.group(1)?.replaceAll('.', '').replaceAll(',', '') ?? '';
      double? valor = double.tryParse(rawNum);
      if (valor != null) {
        final sufijo = match.group(2)?.toLowerCase();
        if (sufijo == 'mil' || sufijo == 'k') {
          valor *= 1000;
        } else if (valor < 100 && valor > 0) {
          // A veces escriben "pago con 20" refiriéndose a 20.000
          if (total > 500 && (valor * 1000) >= total) {
            valor *= 1000;
          }
        }
        return valor;
      }
    }

    // 2. Patrón secundario: "$20.000" o "con $20000" si el monto es superior al total
    final regExpSecundario = RegExp(r'(?:con\s+)?\$\s*([0-9]{1,3}(?:\.[0-9]{3})*|[0-9]{4,6})');
    final matchSec = regExpSecundario.firstMatch(obs);
    if (matchSec != null) {
      String rawNum = matchSec.group(1)?.replaceAll('.', '').replaceAll(',', '') ?? '';
      double? valor = double.tryParse(rawNum);
      if (valor != null && valor > total) {
        return valor;
      }
    }

    return null;
  }

  /// Calcula el vuelto exacto si el cliente paga con un monto mayor al total
  double? get vueltoCalculado {
    final paga = montoPagaCliente;
    if (paga != null && paga > total) {
      return paga - total;
    }
    return null;
  }
}

class ProductoItem {
  final String nombre;
  final int cantidad;

  ProductoItem({
    required this.nombre,
    required this.cantidad,
  });

  factory ProductoItem.fromJson(Map<String, dynamic> json) {
    return ProductoItem(
      nombre: json['nombre']?.toString() ?? 'Producto',
      cantidad: int.tryParse(json['cantidad']?.toString() ?? '1') ?? 1,
    );
  }

  bool get esBebida {
    return RegExp(
      r'coca|fanta|sprite|agua|cerveza|bebida|aquarius|gaseosa',
      caseSensitive: false,
    ).hasMatch(nombre);
  }
}

class CoordenadasModel {
  final double latitud;
  final double longitud;

  CoordenadasModel({
    required this.latitud,
    required this.longitud,
  });

  factory CoordenadasModel.fromJson(Map<String, dynamic> json) {
    return CoordenadasModel(
      latitud: double.tryParse(json['latitud']?.toString() ?? '0') ?? 0.0,
      longitud: double.tryParse(json['longitud']?.toString() ?? '0') ?? 0.0,
    );
  }
}
