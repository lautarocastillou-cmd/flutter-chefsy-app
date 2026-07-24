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
      metodoPago: metodoPago,
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
          : null,
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
