class Program {
  final int id;
  final String name;

  Program({
    required this.id,
    required this.name,
  });

  factory Program.fromJson(Map<String, dynamic> json) {
    return Program(
      id: json['id_campana'] ?? json['id'] ?? 0,
      name: json['nombre_campana'] ?? json['nombre'] ?? 'Sin nombre',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
    };
  }

  @override
  bool operator ==(Object other) => identical(this, other) || (other is Program && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

class Station {
  final int id;
  final String name;
  final double latitude;
  final double longitude;

  Station({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  factory Station.fromJson(Map<String, dynamic> json) {
    return Station(
      id: json['id_estacion'] ?? json['id'] ?? 0,
      name: json['nombre_estacion'] ?? json['estacion'] ?? json['nombre'] ?? 'Sin nombre',
      latitude: (json['latitud'] ?? 0.0 as num).toDouble(),
      longitude: (json['longitud'] ?? 0.0 as num).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'latitude': latitude,
      'longitude': longitude,
    };
  }

  @override
  bool operator ==(Object other) => identical(this, other) || (other is Station && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

class Usuario {
  final int idUsuario;
  final String nombre;
  final String apellido;

  Usuario({
    required this.idUsuario,
    required this.nombre,
    required this.apellido,
  });

  factory Usuario.fromJson(Map<String, dynamic> json) {
    return Usuario(
      idUsuario: json['id_usuario'] ?? json['id'] ?? 0,
      nombre: json['nombre'] ?? 'Sin nombre',
      apellido: json['apellido'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id_usuario': idUsuario,
      'nombre': nombre,
      'apellido': apellido,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Usuario && other.idUsuario == idUsuario);

  @override
  int get hashCode => idUsuario.hashCode;
}

class Metodo {
  final int idMetodo;
  final String metodo;

  Metodo({
    required this.idMetodo,
    required this.metodo,
  });

  factory Metodo.fromJson(Map<String, dynamic> json) {
    return Metodo(
      idMetodo: json['id_metodo'] ?? json['id'] ?? 0,
      metodo: json['metodo'] ?? 'Sin nombre',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id_metodo': idMetodo,
      'metodo': metodo,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Metodo && other.idMetodo == idMetodo);

  @override
  int get hashCode => idMetodo.hashCode;
}

class Matriz {
  final int idMatriz;
  final String nombreMatriz;

  Matriz({
    required this.idMatriz,
    required this.nombreMatriz,
  });

  factory Matriz.fromJson(Map<String, dynamic> json) {
    return Matriz(
      idMatriz: json['id_matriz'] ?? json['id'] ?? 0,
      nombreMatriz: json['nombre_matriz'] ?? json['nombre'] ?? 'Sin nombre',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id_matriz': idMatriz,
      'nombre_matriz': nombreMatriz,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Matriz && other.idMatriz == idMatriz);

  @override
  int get hashCode => idMatriz.hashCode;
}

class TipoEquipo {
  final int idForm;
  final String tipo;

  TipoEquipo({
    required this.idForm,
    required this.tipo,
  });

  factory TipoEquipo.fromJson(Map<String, dynamic> json) {
    return TipoEquipo(
      idForm: json['id_form'] ?? 0,
      tipo: json['tipo'] ?? 'Sin tipo',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id_form': idForm,
      'tipo': tipo,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is TipoEquipo && other.idForm == idForm);

  @override
  int get hashCode => idForm.hashCode;
}

class EquipoDetalle {
  final int id;
  final String codigo;
  final int idFormFk;

  EquipoDetalle({
    required this.id,
    required this.codigo,
    required this.idFormFk,
  });

  factory EquipoDetalle.fromJson(Map<String, dynamic> json, int idFormFk) {
    return EquipoDetalle(
      id: json['id_equipo'] ?? json['id'] ?? 0,
      codigo: json['codigo_equipo'] ?? json['codigo'] ?? 'Sin código',
      idFormFk: json['id_form'] ?? idFormFk,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'codigo': codigo,
      'id_form_fk': idFormFk,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is EquipoDetalle && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

class Parametro {
  final int? idParametro;
  final String nombreParametro;
  final String claveInterna;
  final String unidad;
  final double? min;
  final double? max;
  final String? categoria; // [NEW] Phase 93
  int activo; 

  Parametro({
    this.idParametro,
    required this.nombreParametro,
    required this.claveInterna,
    required this.unidad,
    this.min,
    this.max,
    this.categoria, // [NEW] Phase 93
    this.activo = 1,
  });

  factory Parametro.fromJson(Map<String, dynamic> json) {
    final String rawName = json['nombre_parametro'] ?? json['nombre'] ?? json['parametro'] ?? '';
    final String rawClave = json['clave_interna'] ?? '';

    final String safeClave = rawClave.trim().isNotEmpty
        ? rawClave
        : rawName.toLowerCase().replaceAll(' ', '_').replaceAll('-', '_');

    return Parametro(
      idParametro: json['id_parametro'] ?? json['id'],
      nombreParametro: rawName,
      claveInterna: safeClave,
      unidad: json['unidad'] ?? '',
      min: json['min'] != null ? double.tryParse(json['min'].toString()) : null,
      max: json['max'] != null ? double.tryParse(json['max'].toString()) : null,
      categoria: json['categoria'], // [NEW] Phase 93
      activo: json['activo'] ?? 1,
    );
  }

  Map<String, dynamic> toMap() => {
        'id_parametro': idParametro,
        'nombre_parametro': nombreParametro,
        'clave_interna': claveInterna,
        'unidad': unidad,
        'min': min,
        'max': max,
        'categoria': categoria, // [NEW] Phase 93
        'activo': activo,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Parametro && other.idParametro == idParametro);

  @override
  int get hashCode => idParametro.hashCode;
}
class ChartData {
  final DateTime x;
  final double y;
  ChartData(this.x, this.y);
}
