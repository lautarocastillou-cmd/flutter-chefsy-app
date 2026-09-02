class PagoExtraModel {
  final String id;
  final String cadeteId;
  final String cadeteNombre;
  final double monto;
  final String motivo;
  final String fecha;
  final String? turnoTipo;
  final String? creadoPor;
  final DateTime? createdAt;

  PagoExtraModel({
    required this.id,
    required this.cadeteId,
    required this.cadeteNombre,
    required this.monto,
    required this.motivo,
    required this.fecha,
    this.turnoTipo,
    this.creadoPor,
    this.createdAt,
  });

  factory PagoExtraModel.fromJson(Map<String, dynamic> json) {
    DateTime? parsedDate;
    if (json['created_at'] != null) {
      try {
        parsedDate = DateTime.parse(json['created_at'].toString());
      } catch (_) {}
    }

    return PagoExtraModel(
      id: json['id']?.toString() ?? '',
      cadeteId: json['cadete_id']?.toString() ?? '',
      cadeteNombre: json['cadete_nombre']?.toString() ?? '',
      monto: double.tryParse(json['monto']?.toString() ?? '0') ?? 0.0,
      motivo: json['motivo']?.toString() ?? 'Viaje extra',
      fecha: json['fecha']?.toString() ?? '',
      turnoTipo: json['turno_tipo']?.toString(),
      creadoPor: json['creado_por']?.toString(),
      createdAt: parsedDate,
    );
  }

  static String formatearPrecio(double precio) {
    final int valor = precio.round();
    final String s = valor.toString();
    final StringBuffer sb = StringBuffer();
    int count = 0;
    for (int i = s.length - 1; i >= 0; i--) {
      sb.write(s[i]);
      count++;
      if (count == 3 && i > 0) {
        sb.write('.');
        count = 0;
      }
    }
    return '\$${sb.toString().split('').reversed.join('')}';
  }

  String get horaFormateada {
    if (createdAt != null) {
      final local = createdAt!.toUtc().subtract(const Duration(hours: 3));
      final h = local.hour.toString().padLeft(2, '0');
      final m = local.minute.toString().padLeft(2, '0');
      return '$h:$m hs';
    }
    return '';
  }
}
