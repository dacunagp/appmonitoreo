import 'dart:convert';

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

class Monitoreo {
  final int? id;
  final int? programaId;
  final int? estacionId;
  final String? fechaHora;
  final int monitoreoFallido;
  final String? observacion;
  final int? matrizId;
  final int? equipoMultiId;
  final int? turbidimetroId;
  final int? metodoId;
  final int hidroquimico;
  final int isotopico;
  final String? codLaboratorio;
  final int? usuarioId;
  final String? fotoPath;
  final String? fotoMultiparametro;
  final String? fotoTurbiedad;
  final int? equipoNivelId;
  final String? tipoPozo;
  final String? fechaHoraNivel;
  final double? latitud;
  final double? longitud;
  final double? temperatura;
  final double? ph;
  final double? conductividad;
  final double? oxigeno;
  final double? turbiedad;
  final double? profundidad;
  final double? nivel;
  final int? equipoCaudal;
  final double? nivelCaudal;
  final String? fechaHoraCaudal;
  final String? fotoCaudal;
  final String? fotoNivelFreatico;
  final String? fotoMuestreo;
  final String? firmaPath;
  final int isDraft;
  final String? syncStatus;
  final String? detallesJson;
  final String? multiparametrosJson;

  Monitoreo({
    this.id,
    this.programaId,
    this.estacionId,
    this.fechaHora,
    this.monitoreoFallido = 0,
    this.observacion,
    this.matrizId,
    this.equipoMultiId,
    this.turbidimetroId,
    this.metodoId,
    this.hidroquimico = 0,
    this.isotopico = 0,
    this.codLaboratorio,
    this.usuarioId,
    this.fotoPath,
    this.fotoMultiparametro,
    this.fotoTurbiedad,
    this.equipoNivelId,
    this.tipoPozo,
    this.fechaHoraNivel,
    this.latitud,
    this.longitud,
    this.temperatura,
    this.ph,
    this.conductividad,
    this.oxigeno,
    this.turbiedad,
    this.profundidad,
    this.nivel,
    this.equipoCaudal,
    this.nivelCaudal,
    this.fechaHoraCaudal,
    this.fotoCaudal,
    this.fotoNivelFreatico,
    this.fotoMuestreo,
    this.isDraft = 0,
    this.syncStatus = 'pending',
    this.detallesJson,
    this.multiparametrosJson,
    this.firmaPath,
  });

  factory Monitoreo.fromMap(Map<String, dynamic> map) {
    return Monitoreo(
      id: map['id'],
      programaId: map['programa_id'],
      estacionId: map['estacion_id'],
      fechaHora: map['fecha_hora'],
      monitoreoFallido: map['monitoreo_fallido'] ?? 0,
      observacion: map['observacion'],
      matrizId: map['matriz_id'],
      equipoMultiId: map['equipo_multi_id'],
      turbidimetroId: map['turbidimetro_id'],
      metodoId: map['metodo_id'],
      hidroquimico: map['hidroquimico'] ?? 0,
      isotopico: map['isotopico'] ?? 0,
      codLaboratorio: map['cod_laboratorio'],
      usuarioId: map['usuario_id'],
      fotoPath: map['foto_path'],
      fotoMultiparametro: map['foto_multiparametro'],
      fotoTurbiedad: map['foto_turbiedad'],
      equipoNivelId: map['equipo_nivel_id'],
      tipoPozo: map['tipo_pozo'],
      fechaHoraNivel: map['fecha_hora_nivel'],
      latitud: map['latitud']?.toDouble(),
      longitud: map['longitud']?.toDouble(),
      temperatura: map['temperatura']?.toDouble(),
      ph: map['ph']?.toDouble(),
      conductividad: map['conductividad']?.toDouble(),
      oxigeno: map['oxigeno']?.toDouble(),
      turbiedad: map['turbiedad']?.toDouble(),
      profundidad: map['profundidad']?.toDouble(),
      nivel: map['nivel']?.toDouble(),
      equipoCaudal: map['equipo_caudal'],
      nivelCaudal: map['nivel_caudal']?.toDouble(),
      fechaHoraCaudal: map['fecha_hora_caudal'],
      fotoCaudal: map['foto_caudal'],
      fotoNivelFreatico: map['foto_nivel_freatico'],
      fotoMuestreo: map['foto_muestreo'],
      isDraft: map['is_draft'] ?? 0,
      syncStatus: map['sync_status'],
      detallesJson: map['detalles_json'],
      multiparametrosJson: map['multiparametros_json'],
      firmaPath: map['firma_path'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'programa_id': programaId,
      'estacion_id': estacionId,
      'fecha_hora': fechaHora,
      'monitoreo_fallido': monitoreoFallido,
      'observacion': observacion,
      'matriz_id': matrizId,
      'equipo_multi_id': equipoMultiId,
      'turbidimetro_id': turbidimetroId,
      'metodo_id': metodoId,
      'hidroquimico': hidroquimico,
      'isotopico': isotopico,
      'cod_laboratorio': codLaboratorio,
      'usuario_id': usuarioId,
      'foto_path': fotoPath,
      'foto_multiparametro': fotoMultiparametro,
      'foto_turbiedad': fotoTurbiedad,
      'equipo_nivel_id': equipoNivelId,
      'tipo_pozo': tipoPozo,
      'fecha_hora_nivel': fechaHoraNivel,
      'latitud': latitud,
      'longitud': longitud,
      'temperatura': temperatura,
      'ph': ph,
      'conductividad': conductividad,
      'oxigeno': oxigeno,
      'turbiedad': turbiedad,
      'profundidad': profundidad,
      'nivel': nivel,
      'equipo_caudal': equipoCaudal,
      'nivel_caudal': nivelCaudal,
      'fecha_hora_caudal': fechaHoraCaudal,
      'foto_caudal': fotoCaudal,
      'foto_nivel_freatico': fotoNivelFreatico,
      'foto_muestreo': fotoMuestreo,
      'is_draft': isDraft,
      'sync_status': syncStatus,
      'detalles_json': detallesJson,
      'multiparametros_json': multiparametrosJson,
      'firma_path': firmaPath,
    };
  }

  /// Specialized serialization for API Sync (Phase 115)
  Future<Map<String, dynamic>> toJsonForSync({
    required Future<String?> Function(String?) compressPhoto,
    List<Map<String, String>>? legacyDetalles,
    Map<String, String>? unitsMap,
  }) async {
    final Map<String, String> units = unitsMap ?? {};
    return {
      // "id": id, // 🚨 REMOVED (PHASE 130) to prevent overwriting existing records on backend
      "id_local": id, // 🚨 ADDED (PHASE 133) so FastAPI can track the local SQLite ID
      "device_id": "MOBILE-DATA",
      "programa_id": programaId,
      "estacion_id": estacionId,
      "fecha_hora": fechaHora?.replaceAll('T', ' ').split('.').first,
      "monitoreo_fallido": monitoreoFallido,
      "observacion": observacion,
      "matriz_id": matrizId,
      "equipo_multi_id": equipoMultiId,
      "turbidimetro_id": turbidimetroId,
      "metodo_id": metodoId,
      "hidroquimico": hidroquimico,
      "isotopico": isotopico,
      "cod_laboratorio": codLaboratorio,
      "usuario_id": usuarioId,
      "is_draft": 0,
      "equipo_nivel_id": equipoNivelId,
      "tipo_pozo": tipoPozo,
      "fecha_hora_nivel": fechaHoraNivel?.replaceAll('T', ' ').split('.').first,
      "temperatura": temperatura,
      "ph": ph,
      "conductividad": conductividad,
      "oxigeno": oxigeno,
      "turbiedad": turbiedad,
      "profundidad": profundidad,
      "nivel": nivel,
      "equipo_caudal": equipoCaudal,
      "nivel_caudal": nivelCaudal,
      "fecha_hora_caudal": fechaHoraCaudal?.replaceAll('T', ' ').split('.').first,
      "latitud": latitud,
      "longitud": longitud,
      "multiparametros_json": _transformToExplicitFormat(multiparametrosJson, units),
      "detalles_json": _transformToExplicitFormat(detallesJson, units),
      "detalles": legacyDetalles ?? [], // Legacy support
      // 🖼️ Note: Images are now sent via MultipartFile in the sync screen
    };
  }

  /// Transforms [ {"key": val} ] to [ {"parametro": "key", "valor": val, "unidad": "..."} ]
  List<Map<String, dynamic>> _transformToExplicitFormat(String? jsonStr, Map<String, String> unitsMap) {
    if (jsonStr == null || jsonStr.isEmpty) return [];
    try {
      final List<dynamic> data = jsonDecode(jsonStr);
      return data.map((item) {
        if (item is Map<String, dynamic>) {
          // If it's already in the correct format, return as is
          if (item.containsKey('parametro') && item.containsKey('valor')) {
            return item;
          }
          // Otherwise, transform {"key": val} to {"parametro": "key", "valor": val, "unidad": "..."}
          if (item.isNotEmpty) {
            final key = item.keys.first;
            return {
              "parametro": key,
              "valor": item[key],
              "unidad": unitsMap[key] ?? ''
            };
          }
        }
        return <String, dynamic>{};
      }).where((m) => m.isNotEmpty).toList();
    } catch (e) {
      print('Error transforming JSON for Sync: $e');
      return [];
    }
  }
}
