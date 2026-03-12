class Program {
  final int id;
  final String name;

  Program({
    required this.id,
    required this.name,
  });

  factory Program.fromJson(Map<String, dynamic> json) {
    return Program(
      id: json['id'],
      name: json['nombre'],
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
      id: json['id'],
      name: json['estacion'],
      latitude: (json['latitud'] as num).toDouble(),
      longitude: (json['longitud'] as num).toDouble(),
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
      idUsuario: json['id_usuario'],
      nombre: json['nombre'],
      apellido: json['apellido'],
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
      idMetodo: json['id_metodo'],
      metodo: json['metodo'],
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
      idMatriz: json['id_matriz'],
      nombreMatriz: json['nombre_matriz'],
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
      idForm: json['id_form'],
      tipo: json['tipo'],
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
      id: json['id'],
      codigo: json['codigo'],
      idFormFk: idFormFk,
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
