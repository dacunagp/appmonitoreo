import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/models.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;

  factory DatabaseHelper() => _instance;

  DatabaseHelper._internal();

  static const Map<String, String> _defaultCategories = {
    'Profundidad': 'Datos de Monitoreo',
    'Nivel': 'Nivel Freático',
    'pH': 'Multiparámetro',
    'Temperatura': 'Multiparámetro',
    'Conductividad': 'Multiparámetro',
    'Oxigeno': 'Multiparámetro',
    'Oxígeno': 'Multiparámetro',
    'Turbiedad': 'Turbiedad',
    'Caudal': 'Parámetros Adicionales',
    'SDT': 'Parámetros Adicionales',
    'Uranio': 'Parámetros Adicionales',
  };

  String _resolveCategory(String? current, String? name) {
    if (name == null) return 'Parámetros Adicionales';
    final lowerName = name.toLowerCase();

    // 1. Mandatory mapping based on keywords (Orientation Logic)
    if (lowerName.contains('ph') || lowerName.contains('temperatura') || 
        lowerName.contains('conductividad') || lowerName.contains('oxigeno') || 
        lowerName.contains('oxígeno')) {
      return 'Multiparámetro';
    }
    if (lowerName.contains('turbiedad')) {
      return 'Turbiedad';
    }
    if (lowerName.contains('nivel')) {
      return 'Nivel Freático';
    }
    if (lowerName.contains('profundidad')) {
      return 'Datos de Monitoreo';
    }

    // 2. Fallback to existing if it's not empty/null
    if (current != null && current.isNotEmpty && current != 'Sin Categoría' && 
        current != 'null' && current != 'adicional') {
      return current;
    }

    // 3. Final Default
    return 'Parámetros Adicionales';
  }

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // --- 📝 SISTEMA DE LOGGING NARRATIVO ---
  Future<void> _log(String message) async {
    final timestamp = DateTime.now().toIso8601String();
    final logMessage = '[$timestamp] $message';
    
    // 1. Imprime en la consola de VS Code
    debugPrint(logMessage);

    // 2. Escribe en el archivo físico del dispositivo
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/sync_log.txt');
      await file.writeAsString('$logMessage\n', mode: FileMode.append);
    } catch (e) {
      debugPrint('🚨 Error al escribir en el archivo de log: $e');
    }
  }

  Future<String> readLogFile() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/sync_log.txt');
      if (await file.exists()) {
        return await file.readAsString();
      }
      return 'El archivo de log está vacío o no existe.';
    } catch (e) {
      return 'Error leyendo log: $e';
    }
  }
  // ---------------------------------------

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'collector.db');
    
    await _log('✨ [INIT] Abriendo base de datos SQLite en: $path');
    Database db = await openDatabase(
      path,
      version: 17, // 🚀 BUMP A VERSIÓN 17 (ACTUALIZAR SERVIDORES API)
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
    await _ensureApiTablesExist(db);
    return db;
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    await _log('🚀 [UPGRADE] Migrando base de datos de versión $oldVersion a $newVersion...');
    // ... (previous versions)
    if (oldVersion < 6) {
      try {
        await _log('🚀 [UPGRADE] Agregando columna sync_status a monitoreos...');
        await db.execute("ALTER TABLE monitoreos ADD COLUMN sync_status TEXT DEFAULT 'pending';");
        // Retroactively mark existing synced records as success
        await db.execute("UPDATE monitoreos SET sync_status = 'success' WHERE is_draft = 2;");
      } catch (e) {
        await _log('⚠️ [UPGRADE] Error agregando sync_status: $e');
      }
    }

    if (oldVersion < 7) {
      try {
        await _log('🚀 [UPGRADE] Agregando endpoint por defecto sync/monitoreos...');
        var res = await db.rawQuery("SELECT id FROM endpoints WHERE nombre = ?", ['sync/monitoreos']);
        if (res.isEmpty) {
          await db.insert('endpoints', {'nombre': 'sync/monitoreos'});
          await _log('✅ [UPGRADE] Endpoint sync/monitoreos agregado por defecto.');
        }
      } catch (e) {
        await _log('⚠️ [UPGRADE] Error agregando endpoint por defecto: $e');
      }
    }

    if (oldVersion < 8) {
      try {
        await _log('🚀 [UPGRADE] Creando tabla notificaciones...');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS notificaciones (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            titulo TEXT,
            mensaje TEXT,
            payload TEXT,
            fecha TEXT
          )
        ''');
        await _log('✅ [UPGRADE] Tabla notificaciones creada exitosamente.');
      } catch (e) {
        await _log('⚠️ [UPGRADE] Error creando tabla notificaciones: $e');
      }
    }
    if (oldVersion < 9) {
      try {
        await _log('🚀 [UPGRADE] Agregando endpoint por defecto "muestras"...');
        var res = await db.rawQuery("SELECT id FROM endpoints WHERE nombre = ?", ['muestras']);
        if (res.isEmpty) {
          await db.insert('endpoints', {'nombre': 'muestras'});
          await _log('✅ [UPGRADE] Endpoint "muestras" agregado exitosamente.');
        }
      } catch (e) {
        await _log('⚠️ [UPGRADE] Error agregando endpoint "muestras": $e');
      }
    }

    if (oldVersion < 10) {
      try {
        await _log('🚀 [UPGRADE] Agregando columna categoria a parametros...');
        await db.execute("ALTER TABLE parametros ADD COLUMN categoria TEXT;");
        await _log('✅ [UPGRADE] Columna categoria agregada exitosamente.');
      } catch (e) {
        await _log('⚠️ [UPGRADE] Error agregando categoria: $e');
      }
    }

    if (oldVersion < 11) {
      try {
        await _log('🚀 [UPGRADE] Agregando columna detalles_json a monitoreos (Phase 108)...');
        await db.execute("ALTER TABLE monitoreos ADD COLUMN detalles_json TEXT;");
        await _log('✅ [UPGRADE] Columna detalles_json agregada exitosamente.');
      } catch (e) {
        await _log('⚠️ [UPGRADE] Error agregando detalles_json: $e');
      }
    }

    if (oldVersion < 12) {
      try {
        await _log('🚀 [UPGRADE] Agregando columna multiparametros_json a monitoreos (Phase 114)...');
        await db.execute("ALTER TABLE monitoreos ADD COLUMN multiparametros_json TEXT;");
        await _log('✅ [UPGRADE] Columna multiparametros_json agregada exitosamente.');
      } catch (e) {
        await _log('⚠️ [UPGRADE] Error agregando multiparametros_json: $e');
      }
    }

    if (oldVersion < 13) {
      await _log('🚀 [UPGRADE] Agregando columnas Phase 115 (Caudal + Respaldos Fotográficos)...');
      final List<String> newColumns = [
        "ALTER TABLE monitoreos ADD COLUMN equipo_caudal INTEGER;",
        "ALTER TABLE monitoreos ADD COLUMN nivel_caudal REAL;",
        "ALTER TABLE monitoreos ADD COLUMN fecha_hora_caudal TEXT;",
        "ALTER TABLE monitoreos ADD COLUMN foto_caudal TEXT;",
        "ALTER TABLE monitoreos ADD COLUMN foto_nivel_freatico TEXT;",
        "ALTER TABLE monitoreos ADD COLUMN foto_muestreo TEXT;",
      ];
      for (final sql in newColumns) {
        try {
          await db.execute(sql);
        } catch (e) {
          await _log('⚠️ [UPGRADE v13] Error ejecutando "$sql": $e');
        }
      }
      await _log('✅ [UPGRADE v13] Columnas Phase 115 agregadas exitosamente.');
    }

    if (oldVersion < 14) {
      try {
        await _log('🚀 [UPGRADE] Creando tabla observaciones_predefinidas (Phase 142)...');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS observaciones_predefinidas (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            texto TEXT NOT NULL
          )
        ''');
        await _log('✅ [UPGRADE v14] Tabla observaciones_predefinidas creada exitosamente.');
      } catch (e) {
        await _log('⚠️ [UPGRADE v14] Error creando tabla observaciones_predefinidas: $e');
      }
    }

    if (oldVersion < 15) {
      try {
        await _log('🚀 [UPGRADE] Agregando endpoint por defecto "catalogos/observaciones"...');
        var res = await db.rawQuery("SELECT id FROM endpoints WHERE nombre = ?", ['observaciones_predefinidas']);
        if (res.isEmpty) {
          await db.insert('endpoints', {'nombre': 'observaciones_predefinidas'});
          await _log('✅ [UPGRADE v15] Endpoint "observaciones_predefinidas" agregado exitosamente.');
        }
      } catch (e) {
        await _log('⚠️ [UPGRADE v15] Error agregando endpoint: $e');
      }
    }

    if (oldVersion < 16) {
      try {
        await _log('🚀 [UPGRADE] Agregando columna firma_path a monitoreos (Phase 146)...');
        await db.execute("ALTER TABLE monitoreos ADD COLUMN firma_path TEXT;");
        await _log('✅ [UPGRADE v16] Columna firma_path agregada exitosamente.');
      } catch (e) {
        await _log('⚠️ [UPGRADE v16] Error agregando firma_path: $e');
      }
    }

    if (oldVersion < 17) {
      try {
        await _log('🚀 [UPGRADE v17] Actualizando servidores API: eliminando obsoletos e insertando nuevo servidor AWS...');

        // 1. Eliminar servidores obsoletos
        await db.delete('url_acces', where: "url = ?", whereArgs: ['http://10.0.0.75/api_collector/public/api/']);
        await db.delete('url_acces', where: "url = ?", whereArgs: ['https://gpconsultores.cl/apicollector/sync.php?endpoint=']);
        await _log('✅ [UPGRADE v17] Servidores obsoletos eliminados.');

        // 2. Asegurarse de que el servidor apicollector.gpconsultores.cl esté presente e inactivo
        final existing = await db.query('url_acces', where: "url = ?", whereArgs: ['https://apicollector.gpconsultores.cl/api/']);
        if (existing.isEmpty) {
          await db.insert('url_acces', {
            'url': 'https://apicollector.gpconsultores.cl/api/',
            'usuario': 'collector',
            'contrasenia': 'gp2026',
            'is_active': 0,
          });
          await _log('✅ [UPGRADE v17] Servidor apicollector.gpconsultores.cl insertado.');
        } else {
          await db.update('url_acces', {'is_active': 0}, where: "url = ?", whereArgs: ['https://apicollector.gpconsultores.cl/api/']);
        }

        // 3. Insertar nuevo servidor AWS dev si no existe y marcarlo como activo
        final awsExisting = await db.query('url_acces', where: "url = ?", whereArgs: ['http://3.234.4.126:5348/api/']);
        if (awsExisting.isEmpty) {
          await db.insert('url_acces', {
            'url': 'http://3.234.4.126:5348/api/',
            'usuario': 'collector',
            'contrasenia': 'gp2026',
            'is_active': 0,
          });
          await _log('✅ [UPGRADE v17] Nuevo servidor AWS dev insertado.');
        }

        // 4. Desactivar todos y activar sólo el nuevo servidor AWS
        await db.update('url_acces', {'is_active': 0});
        await db.update('url_acces', {'is_active': 1}, where: "url = ?", whereArgs: ['http://3.234.4.126:5348/api/']);
        await _log('✅ [UPGRADE v17] Servidor AWS dev establecido como activo (seleccionado).');

      } catch (e) {
        await _log('⚠️ [UPGRADE v17] Error actualizando servidores API: $e');
      }
    }
  }

  Future<void> _ensureApiTablesExist(Database db) async {
    var res = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='url_acces'");
    if (res.isEmpty) {
      await _log('🏗️ [MIGRATION] Creando tabla url_acces para base de datos existente...');
      await db.execute('''
        CREATE TABLE url_acces (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          url TEXT NOT NULL,
          usuario TEXT NOT NULL,
          contrasenia TEXT NOT NULL,
          is_active INTEGER DEFAULT 0
        )
      ''');
      // Insertar servidor de producción (Inactivo)
      await db.insert('url_acces', {
        'url': 'https://apicollector.gpconsultores.cl/api/',
        'usuario': 'collector',
        'contrasenia': 'gp2026',
        'is_active': 0
      });
      // Insertar servidor AWS dev (Activo / Seleccionado por defecto)
      await db.insert('url_acces', {
        'url': 'http://3.234.4.126:5348/api/',
        'usuario': 'collector',
        'contrasenia': 'gp2026',
        'is_active': 1
      });
    }

    res = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='endpoints'");
    if (res.isEmpty) {
      await _log('🏗️ [MIGRATION] Creando tabla endpoints para base de datos existente...');
      await db.execute('''
        CREATE TABLE endpoints (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          nombre TEXT NOT NULL
        )
      ''');
      final List<String> defaultEndpoints = ['campanas', 'usuarios', 'metodos', 'matriz_aguas', 'equipos', 'parametros', 'sync/monitoreos', 'muestras', 'observaciones_predefinidas'];
      for (String ep in defaultEndpoints) {
        await db.insert('endpoints', {'nombre': ep});
      }
    }

    res = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='security'");
    if (res.isEmpty) {
      await _log('🏗️ [MIGRATION] Creando tabla security para base de datos existente...');
      await db.execute('CREATE TABLE security (id INTEGER PRIMARY KEY AUTOINCREMENT, pin TEXT NOT NULL)');
      await db.insert('security', {'pin': '1234'});
    }

    res = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='observaciones_predefinidas'");
    if (res.isEmpty) {
      await _log('🏗️ [MIGRATION] Creando tabla observaciones_predefinidas para base de datos existente...');
      await db.execute('''
        CREATE TABLE observaciones_predefinidas (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          texto TEXT NOT NULL
        )
      ''');
    }

    // --- CORRECCIÓN DINÁMICA DE ENDPOINTS (Forzar observaciones_predefinidas) ---
    try {
      var resObs = await db.rawQuery("SELECT id FROM endpoints WHERE nombre = ?", ['observaciones_predefinidas']);
      if (resObs.isEmpty) {
        await db.insert('endpoints', {'nombre': 'observaciones_predefinidas'});
        await _log('✅ [FIX] Endpoint "observaciones_predefinidas" asegurado.');
      }
      // Eliminar versiones incorrectas que causan 404
      int deletedCount = await db.delete('endpoints', 
        where: "nombre = ? OR nombre = ? OR nombre = ?", 
        whereArgs: ['catalogos/observaciones', 'catalogos_observaciones', 'catalogos_observación']
      );
      if (deletedCount > 0) {
        await _log('🧹 [FIX] Se eliminaron $deletedCount endpoints antiguos/incorrectos.');
      }
    } catch (e) {
      await _log('⚠️ [FIX] Error corrigiendo endpoints: $e');
    }
  }

  Future _createDB(Database db, int version) async {
    await _log('🏗️ [SCHEMA] Construyendo tablas de la base de datos...');
    
    // 1. Long Format & Drafts (MÁS LAS 7 COLUMNAS FLATTENED Y LAT/LONG)
    await db.execute('''
      CREATE TABLE monitoreos (
        id INTEGER PRIMARY KEY AUTOINCREMENT, 
        programa_id INTEGER,
        estacion_id INTEGER, 
        fecha_hora TEXT, 
        monitoreo_fallido INTEGER, 
        observacion TEXT,
        matriz_id INTEGER,
        equipo_multi_id INTEGER,
        turbidimetro_id INTEGER,
        metodo_id INTEGER,
        hidroquimico INTEGER,
        isotopico INTEGER,
        cod_laboratorio TEXT,
        usuario_id INTEGER,
        foto_path TEXT,
        foto_multiparametro TEXT,
        foto_turbiedad TEXT,
        equipo_nivel_id INTEGER,
        tipo_pozo TEXT,
        fecha_hora_nivel TEXT,
        latitud REAL,
        longitud REAL,
        temperatura REAL,
        ph REAL,
        conductividad REAL,
        oxigeno REAL,
        turbiedad REAL,
        profundidad REAL,
        nivel REAL,
        is_draft INTEGER DEFAULT 0,
        sync_status TEXT DEFAULT 'pending',
        detalles_json TEXT,
        multiparametros_json TEXT,
        equipo_caudal INTEGER,
        nivel_caudal REAL,
        fecha_hora_caudal TEXT,
        foto_caudal TEXT,
        foto_nivel_freatico TEXT,
        foto_muestreo TEXT,
        firma_path TEXT
      )
    ''');
    
    await db.execute('''
      CREATE TABLE historial_mediciones (
        id INTEGER PRIMARY KEY AUTOINCREMENT, monitoreo_id INTEGER, estacion TEXT NOT NULL, 
        fecha TEXT NOT NULL, parametro TEXT NOT NULL, valor REAL NOT NULL, 
        FOREIGN KEY (monitoreo_id) REFERENCES monitoreos (id) ON DELETE CASCADE
      )
    ''');

    // 2. Standard Catalogs
    await db.execute('CREATE TABLE usuarios (id_usuario INTEGER PRIMARY KEY, nombre TEXT, apellido TEXT)');
    await db.execute('CREATE TABLE matrices (id_matriz INTEGER PRIMARY KEY, nombre_matriz TEXT)');
    await db.execute('CREATE TABLE metodos (id_metodo INTEGER PRIMARY KEY, metodo TEXT)');
    await db.execute('CREATE TABLE tipos_equipo (id_form INTEGER PRIMARY KEY, tipo TEXT)');
    await db.execute('CREATE TABLE security (id INTEGER PRIMARY KEY AUTOINCREMENT, pin TEXT NOT NULL)');

    await db.insert('security', {'pin': '1234'});

    // 3. ENGLISH SCHEMA & MANY-TO-MANY RELATIONSHIPS
    await db.execute('CREATE TABLE programs (id INTEGER PRIMARY KEY, name TEXT)');
    await db.execute('CREATE TABLE stations (id INTEGER PRIMARY KEY, name TEXT, latitude REAL, longitude REAL)');
    await db.execute('''
      CREATE TABLE program_stations (
        program_id INTEGER, station_id INTEGER,
        PRIMARY KEY (program_id, station_id),
        FOREIGN KEY (program_id) REFERENCES programs (id) ON DELETE CASCADE,
        FOREIGN KEY (station_id) REFERENCES stations (id) ON DELETE CASCADE
      )
    ''');

    // 4. Flattened Catalogs
    await db.execute('''
      CREATE TABLE equipos (
        id INTEGER PRIMARY KEY, 
        codigo TEXT NOT NULL, 
        tipo TEXT NOT NULL,
        id_form_fk INTEGER
      )
    ''');

    // 5. Parametros 
    await db.execute('''
      CREATE TABLE parametros (
        id INTEGER PRIMARY KEY, nombre TEXT, clave_interna TEXT, unidad TEXT, 
        minimo REAL, maximo REAL, categoria TEXT, activo INTEGER
      )
    ''');

    // 6. Dynamic API Config
    await db.execute('''
      CREATE TABLE url_acces (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        url TEXT NOT NULL,
        usuario TEXT NOT NULL,
        contrasenia TEXT NOT NULL,
        is_active INTEGER DEFAULT 0
      )
    ''');

    // Insertar par de APIs de fábrica
    await db.insert('url_acces', {
      'url': 'https://apicollector.gpconsultores.cl/api/',
      'usuario': 'collector',
      'contrasenia': 'gp2026',
      'is_active': 0
    });
    await db.insert('url_acces', {
      'url': 'http://3.234.4.126:5348/api/',
      'usuario': 'collector',
      'contrasenia': 'gp2026',
      'is_active': 1  // ✅ Servidor de desarrollo AWS — seleccionado por defecto
    });

    await db.execute('''
      CREATE TABLE endpoints (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL
      )
    ''');

    final List<String> defaultEndpoints = ['campanas', 'usuarios', 'metodos', 'matriz_aguas', 'equipos', 'parametros', 'sync/monitoreos', 'muestras', 'observaciones_predefinidas'];
    for (String ep in defaultEndpoints) {
      await db.insert('endpoints', {'nombre': ep});
    }

    // 7. Notificaciones Push
    await db.execute('''
      CREATE TABLE notificaciones (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        titulo TEXT,
        mensaje TEXT,
        payload TEXT,
        fecha TEXT
      )
    ''');

    // 8. Observaciones Predefinidas
    await db.execute('''
      CREATE TABLE observaciones_predefinidas (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        texto TEXT NOT NULL
      )
    ''');

    await _log('✅ [SCHEMA] Tablas construidas con éxito.');
  }

  Future<void> syncHistoricalData(List<Map<String, dynamic>> parsedData, {int? exactSampleCount}) async {
    if (parsedData.isEmpty) return;
    await _log('🔄 [SYNC-HISTORIAL] Iniciando sincronización de ${parsedData.length} registros aplanados...');
    final db = await database;

    try {
      final Set<String> stationsInBatch = parsedData
          .map((row) => (row['estacion'] ?? '').toString())
          .where((s) => s.isNotEmpty)
          .toSet();

      await db.transaction((txn) async {
        for (final station in stationsInBatch) {
          await txn.delete(
            'historial_mediciones',
            where: 'estacion = ? AND monitoreo_id IS NULL',
            whereArgs: [station],
          );
        }

        final Batch batch = txn.batch();
        for (var row in parsedData) {
          batch.insert(
            'historial_mediciones',
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await batch.commit(noResult: true);
      });

      final int logCount = exactSampleCount ?? parsedData.length;
      await _log('✅ [SYNC-HISTORIAL] Éxito. $logCount registros/muestras insertados para la estación.');
    } catch (e) {
      await _log('❌ [SYNC-HISTORIAL] ERROR CRÍTICO: $e');
      rethrow;
    }
  }

  Future<List<double>> getHistoricalValues(String estacion, String parametro) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'historial_mediciones',
      columns: ['valor'],
      // Strictly use API-synced records only (monitoreo_id IS NULL = from API download)
      where: 'estacion = ? AND parametro = ? AND monitoreo_id IS NULL',
      whereArgs: [estacion, parametro],
      orderBy: 'fecha ASC',
    );
    return maps.map((map) {
      dynamic val = map['valor'];
      if (val is num) return val.toDouble();
      return double.tryParse(val?.toString() ?? '') ?? 0.0;
    }).toList();
  }

  Future<List<Map<String, dynamic>>> getHistorialMuestrasByStationName(String stationName) async {
    final db = await database;
    // Strictly query API-synced records only. monitoreo_id IS NULL means the row came
    // from a server download, NOT from a local pending monitoring form.
    return await db.query(
      'historial_mediciones',
      where: 'estacion = ? AND monitoreo_id IS NULL',
      whereArgs: [stationName],
      orderBy: 'fecha DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getHistorialMuestras({String? dateFilter}) async {
    final db = await database;
    String whereClause = 'monitoreo_id IS NULL';
    List<dynamic> whereArgs = [];
    
    if (dateFilter != null) {
      whereClause += ' AND fecha LIKE ?';
      whereArgs.add('$dateFilter%');
    }

    return await db.query(
      'historial_mediciones',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'fecha DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getHistorialSummary({String? dateFilter}) async {
    final db = await database;
    
    // We enforce the business rule: a valid record must have at least one valid physical/chemical metric.
    // In our EAV schema, this means selecting dates that have at least one of these parameters.
    final String validMetricsFilter = '''
      LOWER(parametro) IN ('caudal', 'ph', 'temperatura', 'conductividad', 'oxigeno', 'sdt', 'turbiedad', 'nivel', 'profundidad')
      AND valor IS NOT NULL 
      AND CAST(valor AS TEXT) != ''
    ''';

    if (dateFilter != null) {
      return await db.rawQuery('''
        SELECT 
          estacion, 
          COUNT(*) as count,
          MAX(fecha) as raw_last_date
        FROM historial_mediciones 
        WHERE monitoreo_id IS NULL 
          AND fecha LIKE ?
          AND $validMetricsFilter
        GROUP BY estacion
        ORDER BY estacion ASC
      ''', ['$dateFilter%']);
    } else {
      return await db.rawQuery('''
        SELECT 
          estacion, 
          COUNT(*) as count,
          MAX(fecha) as raw_last_date
        FROM historial_mediciones 
        WHERE monitoreo_id IS NULL
          AND $validMetricsFilter
        GROUP BY estacion
        ORDER BY estacion ASC
      ''');
    }
  }

  Future<void> debugExcludedHistoricalRecords() async {
    final db = await database;
    final List<Map<String, dynamic>> excluded = await db.rawQuery('''
      SELECT estacion, fecha, parametro, valor 
      FROM historial_mediciones
      WHERE monitoreo_id IS NULL
      AND fecha NOT IN (
        SELECT DISTINCT fecha
        FROM historial_mediciones
        WHERE monitoreo_id IS NULL
        AND LOWER(parametro) IN ('caudal', 'ph', 'temperatura', 'conductividad', 'oxigeno', 'sdt', 'turbiedad', 'nivel', 'profundidad')
        AND valor IS NOT NULL 
        AND CAST(valor AS TEXT) != ''
      )
      ORDER BY estacion DESC, fecha DESC
    ''');
    
    await _log('🔍 [DEBUG-HISTORIAL] Encontrados ${excluded.length} registros huérfanos/inválidos que no aportan parámetros físicos y fueron filtrados de la UI:');
    for (var r in excluded) {
      await _log('   -> EST: ${r['estacion']} | FECHA: ${r['fecha']} | PARAM: ${r['parametro']} | VALOR: ${r['valor']}');
    }
  }

  Future<int> deleteAllHistorialMuestras() async {
    final db = await database;
    return await db.delete(
      'historial_mediciones',
      where: 'monitoreo_id IS NULL',
    );
  }

  Future<int> deleteSampleGroupByStation(String stationName) async {
    final db = await database;
    return await db.delete(
      'historial_mediciones',
      where: 'estacion = ?',
      whereArgs: [stationName],
    );
  }

  Future<int> addRegistroMonitoreo(Map<String, dynamic> registro) async {
    final db = await database;
    return await db.insert('monitoreos', registro);
  }

  Future<int> updateMonitoreoStatus(int id, int status) async {
    final db = await database;
    return await db.update('monitoreos', {'is_draft': status}, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getMonitoreosList() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT m.*, COALESCE(s.name, 'Estación Desconocida') AS nombre_estacion
      FROM monitoreos m
      LEFT JOIN stations s ON m.estacion_id = s.id
      ORDER BY m.fecha_hora DESC
    ''');
  }

  Future<List<Map<String, dynamic>>> getMonitoreosForExport() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT 
        m.id AS ID,
        COALESCE(p.name, 'N/A') AS Programa,
        COALESCE(s.name, 'N/A') AS Estacion,
        m.latitud AS Latitud,
        m.longitud AS Longitud,
        m.fecha_hora AS Fecha_Hora,
        COALESCE(u.nombre || ' ' || u.apellido, 'N/A') AS Inspector,
        COALESCE(ma.nombre_matriz, 'N/A') AS Matriz,
        COALESCE(me.metodo, 'N/A') AS Metodo,
        COALESCE(em.codigo, 'N/A') AS Equipo_Multiparametro,
        COALESCE(et.codigo, 'N/A') AS Equipo_Turbidimetro,
        COALESCE(en.codigo, 'N/A') AS Equipo_Nivel,
        m.tipo_pozo AS Tipo_Pozo,
        m.fecha_hora_nivel AS Fecha_Hora_Nivel,
        m.nivel AS Nivel_Freatico,
        m.profundidad AS Profundidad,
        m.temperatura AS Temperatura,
        m.ph AS pH,
        m.conductividad AS Conductividad,
        m.oxigeno AS Oxigeno_Disuelto,
        m.turbiedad AS Turbiedad,
        CASE WHEN m.hidroquimico = 1 THEN 'Sí' ELSE 'No' END AS Muestra_Hidroquimica,
        CASE WHEN m.isotopico = 1 THEN 'Sí' ELSE 'No' END AS Muestra_Isotopica,
        m.cod_laboratorio AS Codigo_Laboratorio,
        CASE WHEN m.monitoreo_fallido = 1 THEN 'Sí' ELSE 'No' END AS Monitoreo_Fallido,
        m.observacion AS Observaciones,
        CASE 
          WHEN m.is_draft = 1 THEN 'Borrador' 
          WHEN m.is_draft = 0 THEN 'Finalizado (Pendiente)' 
          WHEN m.is_draft = 2 THEN 'Enviado' 
          ELSE 'Desconocido' 
        END AS Estado_App
      FROM monitoreos m
      LEFT JOIN programs p ON m.programa_id = p.id
      LEFT JOIN stations s ON m.estacion_id = s.id
      LEFT JOIN usuarios u ON m.usuario_id = u.id_usuario
      LEFT JOIN matrices ma ON m.matriz_id = ma.id_matriz
      LEFT JOIN metodos me ON m.metodo_id = me.id_metodo
      LEFT JOIN equipos em ON m.equipo_multi_id = em.id
      LEFT JOIN equipos et ON m.turbidimetro_id = et.id
      LEFT JOIN equipos en ON m.equipo_nivel_id = en.id
      ORDER BY m.fecha_hora DESC
    ''');
  }

  Future<List<Map<String, dynamic>>> getPendingToSendMonitoreos() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT m.*, COALESCE(s.name, 'Estación Desconocida') AS nombre_estacion
      FROM monitoreos m
      LEFT JOIN stations s ON m.estacion_id = s.id
      WHERE m.is_draft = 0 AND m.sync_status = 'pending'
      ORDER BY m.fecha_hora DESC
    ''');
  }

  Future<List<Map<String, dynamic>>> getSentMonitoreos() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT m.*, COALESCE(s.name, 'Estación Desconocida') AS nombre_estacion
      FROM monitoreos m
      LEFT JOIN stations s ON m.estacion_id = s.id
      WHERE m.sync_status = 'success'
      ORDER BY m.fecha_hora DESC
    ''');
  }

  Future<int> getStationSyncStatus(int stationId) async {
    final db = await database;
    final List<Map<String, dynamic>> results = await db.query(
      'monitoreos',
      where: 'estacion_id = ?',
      whereArgs: [stationId],
    );

    if (results.isEmpty) return -1;

    bool hasPending = results.any((m) => m['is_draft'] == 0);
    if (hasPending) return 0;

    bool hasSent = results.any((m) => m['is_draft'] == 2);
    if (hasSent) return 2;

    return -1;
  }

  /// Returns a sync status code: 0 = No Record, 1 = Draft/Not Sent, 2 = Sent (Phase 81)
  Future<int> getStationLatestSyncStatus(int stationId) async {
    final db = await database;
    final List<Map<String, dynamic>> result = await db.query(
      'monitoreos',
      columns: ['id', 'is_draft'], 
      where: 'estacion_id = ?',
      whereArgs: [stationId],
      orderBy: 'id DESC', 
      limit: 1,
    );

    if (result.isEmpty) return 0; // No record -> Grey
    if (result.first['is_draft'] == 1) return 1; // Draft -> Yellow
    return 2; // Sent -> Green
  }

  /// Returns a detailed monitoring status (Phase 118 Sync):
  /// 0 = Gray (No Record), 1 = Red (Failed), 2 = Yellow (Borrador), 3 = Green (Enviado), 4 = Orange (Pendiente)
  Future<int> getStationDetailedMonitoringStatus(int stationId) async {
    final db = await database;
    final List<Map<String, dynamic>> result = await db.query(
      'monitoreos',
      columns: ['monitoreo_fallido', 'is_draft', 'sync_status'],
      where: 'estacion_id = ?',
      whereArgs: [stationId],
      orderBy: 'id DESC',
      limit: 1,
    );

    if (result.isEmpty) return 0; // Gris (Sin información)

    final r = result.first;
    // Use the same criteria as monitoreos_screen.dart
    final bool isFallido = r['monitoreo_fallido'] == 'true' || r['monitoreo_fallido'] == 1 || r['monitoreo_fallido'] == 'SI';
    final int draftStatus = r['is_draft'] ?? 1;

    if (isFallido) return 1; // Rojo (Fallido)
    if (draftStatus == 1) return 2; // Amarillo (Borrador)
    if (draftStatus == 0) return 4; // Naranja (Pendiente)
    if (draftStatus == 2 || r['sync_status'] == 'success') return 3; // Verde (Enviado)
    
    return 0;
  }




  Future<List<Map<String, dynamic>>> getHistorialMedicionesByMonitoreoId(int monitoreoId) async {
    final db = await database;
    return await db.query(
      'historial_mediciones',
      where: 'monitoreo_id = ?',
      whereArgs: [monitoreoId]
    );
  }

  // Alias for readability/consistency in Phase 101 refactoring
  Future<List<Map<String, dynamic>>> getDetallesLocalesPorMonitoreo(int monitoreoId) async {
    return await getHistorialMedicionesByMonitoreoId(monitoreoId);
  }


  Future<int> updateMonitoreoSyncStatus(int id, String status) async {
    final db = await database;
    return await db.update('monitoreos', {'sync_status': status}, where: 'id = ?', whereArgs: [id]);
  }

  Future<Map<String, dynamic>?> getRegistroMonitoreoById(int id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('monitoreos', where: 'id = ?', whereArgs: [id]);
    return maps.isNotEmpty ? maps.first : null;
  }

  Future<int> updateRegistroMonitoreo(int id, Map<String, dynamic> data) async {
    final db = await database;
    
    // 🛡️ [DEFENSE] Check if record is already synced
    final existing = await getRegistroMonitoreoById(id);
    if (existing != null && (existing['is_draft'] == 2 || existing['sync_status'] == 'success')) {
      await _log('🛡️ [DEFENSE] Bloqueo de actualización: El registro $id ya fue sincronizado.');
      return 0; // Reject update
    }

    return await db.update('monitoreos', data, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteRegistroMonitoreo(int id) async {
    final db = await database;
    return await db.delete('monitoreos', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteAllRegistrosMonitoreo() async {
    final db = await database;
    return await db.delete('monitoreos');
  }

  // --- MÉTODOS PARA OBSERVACIONES PREDEFINIDAS (Phase 142) ---
  Future<void> saveObservacionesPredefinidasBatch(List<String> observaciones) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('observaciones_predefinidas');
      final Batch batch = txn.batch();
      for (var obs in observaciones) {
        batch.insert('observaciones_predefinidas', {'texto': obs});
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<Map<String, dynamic>>> getObservacionesPredefinidasCompleto() async {
    final db = await database;
    return await db.query('observaciones_predefinidas');
  }

  Future<List<String>> getObservacionesPredefinidas() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('observaciones_predefinidas');
    return maps.map((map) => map['texto'] as String).toList();
  }

  Future<int> addObservacionPredefinida(String texto) async {
    final db = await database;
    return await db.insert('observaciones_predefinidas', {'texto': texto});
  }

  Future<int> updateObservacionPredefinida(int id, String texto) async {
    final db = await database;
    return await db.update('observaciones_predefinidas', {'texto': texto}, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteObservacionPredefinida(int id) async {
    final db = await database;
    return await db.delete('observaciones_predefinidas', where: 'id = ?', whereArgs: [id]);
  }
  
  Future<int> saveMonitoreoTransaction(Map<String, dynamic> header, List<Map<String, dynamic>> detalles) async {
    final db = await database;
    int monitoreoId = header['id'] ?? 0;
    String estacion = header['estacion_id']?.toString() ?? 'S/N';
    String fecha = header['fecha_hora']?.toString() ?? DateTime.now().toIso8601String();

    // 🛡️ [DEFENSE] Check if record is already synced
    if (monitoreoId != 0) {
      final existing = await getRegistroMonitoreoById(monitoreoId);
      if (existing != null && (existing['is_draft'] == 2 || existing['sync_status'] == 'success')) {
        await _log('🛡️ [DEFENSE] Bloqueo de transacción: El registro $monitoreoId ya fue sincronizado.');
        return monitoreoId; // Return current id without changes
      }
    }

    await db.transaction((txn) async {
      if (monitoreoId == 0) {
        header.remove('id');
        monitoreoId = await txn.insert('monitoreos', header);
      } else {
        await txn.update('monitoreos', header, where: 'id = ?', whereArgs: [monitoreoId]);
        await txn.delete('historial_mediciones', where: 'monitoreo_id = ?', whereArgs: [monitoreoId]);
      }
      
      for (var detalle in detalles) {
        detalle['monitoreo_id'] = monitoreoId;
        detalle['estacion'] ??= estacion;
        detalle['fecha'] ??= fecha;
        await txn.insert('historial_mediciones', detalle);
      }
    });
    
    return monitoreoId;
  }



  Future<List<Usuario>> getUsuarios() async {
    final db = await database;
    final maps = await db.query('usuarios');
    return maps.map((map) => Usuario.fromJson(map)).toList();
  }

  Future<List<Program>> getPrograms() async {
    final db = await database;
    final maps = await db.rawQuery('SELECT id, name AS nombre FROM programs');
    return maps.map((map) => Program.fromJson(map)).toList();
  }

  Future<List<Matriz>> getMatrices() async {
    final db = await database;
    final maps = await db.query('matrices');
    return maps.map((map) => Matriz.fromJson(map)).toList();
  }

  Future<List<Metodo>> getMetodos() async {
    final db = await database;
    final maps = await db.query('metodos');
    return maps.map((map) => Metodo.fromJson(map)).toList();
  }

  Future<List<Parametro>> getParametros() async {
    final db = await database;
    final maps = await db.query('parametros');
    return maps.map((map) {
      final adjusted = Map<String, dynamic>.from(map);
      adjusted['id_parametro'] = map['id'];
      adjusted['nombre_parametro'] = map['nombre'];
      adjusted['min'] = map['minimo'];
      adjusted['max'] = map['maximo'];
      return Parametro.fromJson(adjusted);
    }).toList();
  }

  Future<List<TipoEquipo>> getTiposEquipo() async {
    final db = await database;
    final maps = await db.query('tipos_equipo');
    return maps.map((map) => TipoEquipo.fromJson(map)).toList();
  }

  Future<List<EquipoDetalle>> getEquiposByType(String tipoNombre) async {
    final db = await database;
    final maps = await db.query('equipos', where: 'tipo = ?', whereArgs: [tipoNombre]);
    return maps.map((map) => EquipoDetalle.fromJson(map, 0)).toList();
  }

  Future<List<Map<String, dynamic>>> getAllEquiposWithTipo() async {
    final db = await database;
    return await db.query('equipos');
  }

  Future<List<Station>> getStationsByProgram(int programId) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT 
        s.id, 
        s.name AS estacion, 
        s.latitude AS latitud, 
        s.longitude AS longitud 
      FROM stations s
      INNER JOIN program_stations ps ON s.id = ps.station_id
      WHERE ps.program_id = ?
    ''', [programId]);
    return maps.map((map) => Station.fromJson(map)).toList();
  }

  Future<List<Station>> getAllStations() async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT 
        id, 
        name AS estacion, 
        latitude AS latitud, 
        longitude AS longitud 
      FROM stations 
      ORDER BY name ASC
    ''');
    return maps.map((map) => Station.fromJson(map)).toList();
  }

  Future<List<Map<String, dynamic>>> getStationsWithPrograms() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT 
        s.id, 
        COALESCE(s.name, 'Sin nombre') AS name, 
        COALESCE(s.name, 'Sin nombre') AS estacion, 
        COALESCE(s.latitude, 0.0) AS latitude, 
        COALESCE(s.latitude, 0.0) AS latitud, 
        COALESCE(s.longitude, 0.0) AS longitude, 
        COALESCE(s.longitude, 0.0) AS longitud, 
        COALESCE(p.id, 0) AS program_id,
        COALESCE(p.name, 'Sin Programa') AS program_name 
      FROM stations s
      LEFT JOIN program_stations ps ON s.id = ps.station_id
      LEFT JOIN programs p ON ps.program_id = p.id
    ''');
  }

  Future<List<Map<String, dynamic>>> getDownloadedStationsWithPrograms() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT 
        s.id, 
        COALESCE(s.name, 'Sin nombre') AS name, 
        COALESCE(s.name, 'Sin nombre') AS estacion, 
        COALESCE(s.latitude, 0.0) AS latitude, 
        COALESCE(s.latitude, 0.0) AS latitud, 
        COALESCE(s.longitude, 0.0) AS longitude, 
        COALESCE(s.longitude, 0.0) AS longitud, 
        COALESCE(p.id, 0) AS program_id,
        COALESCE(p.name, 'Sin Programa') AS program_name 
      FROM stations s
      INNER JOIN historial_mediciones hm ON s.name = hm.estacion
      LEFT JOIN program_stations ps ON s.id = ps.station_id
      LEFT JOIN programs p ON ps.program_id = p.id
      GROUP BY s.id
      ORDER BY s.name ASC
    ''');
  }

 Future<List<String>> getEstacionesNombresByPrograma(int programId) async {
    final db = await database;
    final maps = await db.rawQuery('''
      SELECT s.name AS estacion 
      FROM stations s
      INNER JOIN program_stations ps ON s.id = ps.station_id
      WHERE ps.program_id = ?
    ''', [programId]);
    return maps.map((map) => map['estacion'] as String).toList();
  }

  Future<int> addProgram(Program item) async {
    final db = await database;
    return await db.insert('programs', item.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<int> updateProgram(Program item) async {
    final db = await database;
    return await db.update('programs', item.toMap(), where: 'id = ?', whereArgs: [item.id]);
  }
  Future<int> deleteProgram(int id) async {
    final db = await database;
    return await db.delete('programs', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> addStation(Station item, int programId) async {
    final db = await database;
    int stationId = await db.insert('stations', item.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    await db.insert('program_stations', {'program_id': programId, 'station_id': item.id}, conflictAlgorithm: ConflictAlgorithm.ignore);
    return stationId;
  }
  Future<int> updateStation(Station item) async {
    final db = await database;
    return await db.update('stations', item.toMap(), where: 'id = ?', whereArgs: [item.id]);
  }
  Future<int> deleteStation(int id) async {
    final db = await database;
    return await db.delete('stations', where: 'id = ?', whereArgs: [id]);
  }
  Future<void> addStationToProgram(int stationId, int programId) async {
    final db = await database;
    await db.insert('program_stations', {'program_id': programId, 'station_id': stationId}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<int> addUsuario(Usuario item) async {
    final db = await database;
    return await db.insert('usuarios', item.toMap());
  }
  Future<int> updateUsuario(Usuario item) async {
    final db = await database;
    return await db.update('usuarios', item.toMap(), where: 'id_usuario = ?', whereArgs: [item.idUsuario]);
  }
  Future<int> deleteUsuario(int id) async => database.then((db) => db.delete('usuarios', where: 'id_usuario = ?', whereArgs: [id]));

  Future<int> addMatriz(Matriz item) async => database.then((db) => db.insert('matrices', item.toMap()));
  Future<int> updateMatriz(Matriz item) async => database.then((db) => db.update('matrices', item.toMap(), where: 'id_matriz = ?', whereArgs: [item.idMatriz]));
  Future<int> deleteMatriz(int id) async => database.then((db) => db.delete('matrices', where: 'id_matriz = ?', whereArgs: [id]));

  Future<int> addMetodo(Metodo item) async => database.then((db) => db.insert('metodos', item.toMap()));
  Future<int> updateMetodo(Metodo item) async => database.then((db) => db.update('metodos', item.toMap(), where: 'id_metodo = ?', whereArgs: [item.idMetodo]));
  Future<int> deleteMetodo(int id) async => database.then((db) => db.delete('metodos', where: 'id_metodo = ?', whereArgs: [id]));

  Future<int> addParametro(Parametro item) async {
    final db = await database;
    final String resolvedCat = _resolveCategory(item.categoria, item.nombreParametro);
    
    final map = item.toMap();
    map['id'] = map.remove('id_parametro');
    map['nombre'] = map.remove('nombre_parametro');
    map['minimo'] = map.remove('min');
    map['maximo'] = map.remove('max');
    map['categoria'] = resolvedCat;
    
    return await db.insert('parametros', map);
  }
  Future<int> updateParametro(Parametro item) async {
    final db = await database;
    final String resolvedCat = _resolveCategory(item.categoria, item.nombreParametro);
    
    final map = item.toMap();
    map['id'] = map.remove('id_parametro');
    map['nombre'] = map.remove('nombre_parametro');
    map['minimo'] = map.remove('min');
    map['maximo'] = map.remove('max');
    map['categoria'] = resolvedCat;
    
    return await db.update('parametros', map, where: 'id = ?', whereArgs: [item.idParametro]);
  }
  Future<int> deleteParametro(int id) async => database.then((db) => db.delete('parametros', where: 'id = ?', whereArgs: [id]));

  Future<int> addEquipo(Map<String, dynamic> item) async {
    final db = await database;
    final Map<String, dynamic> cleanItem = Map<String, dynamic>.from(item);
    cleanItem['tipo'] ??= 'General'; 
    return await db.insert('equipos', cleanItem);
  }
  Future<int> updateEquipo(Map<String, dynamic> item) async => database.then((db) => db.update('equipos', item, where: 'id = ?', whereArgs: [item['id']]));
  Future<int> deleteEquipo(int id) async => database.then((db) => db.delete('equipos', where: 'id = ?', whereArgs: [id]));

  Future<List<Map<String, dynamic>>> getUrlAccess() async {
    final db = await database;
    return await db.query('url_acces', orderBy: 'id ASC');
  }

  Future<Map<String, dynamic>?> getActiveUrlConfig() async {
    final db = await database;
    final maps = await db.query('url_acces', where: 'is_active = 1', limit: 1);
    return maps.isNotEmpty ? maps.first : null;
  }

  Future<int> addUrlAccess(Map<String, dynamic> item) async {
    final db = await database;
    return await db.insert('url_acces', item);
  }

  Future<int> updateUrlAccess(Map<String, dynamic> item) async {
    final db = await database;
    return await db.update('url_acces', item, where: 'id = ?', whereArgs: [item['id']]);
  }

  Future<int> deleteUrlAccess(int id) async {
    final db = await database;
    return await db.delete('url_acces', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> setActiveUrl(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update('url_acces', {'is_active': 0});
      await txn.update('url_acces', {'is_active': 1}, where: 'id = ?', whereArgs: [id]);
    });
  }

  // --- BATCH SAVE METHODS FOR API RESILIENCE ---
  
  Future<void> saveProgramsBatch(List<Program> items) async {
    final db = await database;
    Batch batch = db.batch();
    batch.delete('programs');
    batch.delete('stations');
    batch.delete('program_stations');
    for (var p in items) {
      batch.insert('programs', {'id': p.id, 'name': p.name}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> saveStationsBatch(int programId, List<Station> items) async {
    final db = await database;
    Batch batch = db.batch();
    for (var s in items) {
      batch.insert('stations', {
        'id': s.id,
        'name': s.name,
        'latitude': s.latitude,
        'longitude': s.longitude
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      batch.insert('program_stations', {
        'program_id': programId,
        'station_id': s.id
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  Future<void> saveUsersBatch(List<Usuario> items) async {
    final db = await database;
    Batch batch = db.batch();
    batch.delete('usuarios');
    for (var u in items) {
      batch.insert('usuarios', u.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<void> saveMetodosBatch(List<Metodo> items) async {
    final db = await database;
    Batch batch = db.batch();
    batch.delete('metodos');
    for (var m in items) {
      batch.insert('metodos', m.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<void> saveMatricesBatch(List<Matriz> items) async {
    final db = await database;
    Batch batch = db.batch();
    batch.delete('matrices');
    for (var m in items) {
      batch.insert('matrices', m.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<void> saveEquiposBatch(List<Map<String, dynamic>> items) async {
    final db = await database;
    Batch batch = db.batch();
    batch.delete('equipos');
    for (var e in items) {
      batch.insert('equipos', e);
    }
    await batch.commit(noResult: true);
  }

  Future<void> saveParametrosBatch(List<Parametro> items) async {
    final db = await database;
    Batch batch = db.batch();
    batch.delete('parametros');
    for (var p in items) {
      final String resolvedCat = _resolveCategory(p.categoria, p.nombreParametro);
      final map = p.toMap();
      // Adjust keys for DB schema if necessary
      final dbMap = {
        'id': map['id_parametro'],
        'nombre': map['nombre_parametro'],
        'clave_interna': map['clave_interna'],
        'unidad': map['unidad'],
        'minimo': map['min'],
        'maximo': map['max'],
        'categoria': resolvedCat,
        'activo': 1 // Default to active when synced
      };
      batch.insert('parametros', dbMap);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Map<String, dynamic>>> getEndpoints() async {
    final db = await database;
    return await db.query('endpoints', orderBy: 'nombre ASC');
  }

  Future<int> addEndpoint(String nombre) async {
    final db = await database;
    return await db.insert('endpoints', {'nombre': nombre});
  }

  Future<int> updateEndpoint(int id, String nombre) async {
    final db = await database;
    return await db.update('endpoints', {'nombre': nombre}, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteEndpoint(int id) async {
    final db = await database;
    return await db.delete('endpoints', where: 'id = ?', whereArgs: [id]);
  }

  Future<String?> getEndpointByName(String name) async {
    final db = await database;
    final results = await db.query('endpoints', where: 'nombre = ?', whereArgs: [name], limit: 1);
    if (results.isNotEmpty) {
      return results.first['nombre'] as String;
    }
    return null;
  }

  Future<String?> getPin() async {
    final db = await database;
    final maps = await db.query('security', limit: 1);
    return maps.isNotEmpty ? maps.first['pin'] as String : null;
  }

  Future<int> updatePin(String newPin) async {
    final db = await database;
    return await db.update('security', {'pin': newPin});
  }

  Future<void> syncData(Map<String, dynamic> data) async {
    await _log('📥 [SYNC-CATALOGOS] Iniciando proceso de sincronización general...');
    final db = await database;
    Batch batch = db.batch();

    try {
      final simpleCatalogs = {
        'usuarios': 'usuarios',
        'matriz_aguas': 'matrices',
        'metodos': 'metodos',
        'tipos_equipo': 'tipos_equipo',
      };

      for (var entry in simpleCatalogs.entries) {
        if (data.containsKey(entry.key)) {
          await _log('🔍 [SYNC] Procesando catálogo simple: ${entry.key}');
          batch.delete(entry.value);
          List items = data[entry.key];
          for (var item in items) {
            batch.insert(entry.value, item);
          }
          await _log('   -> ${items.length} registros preparados para ${entry.value}.');
        }
      }

      if (data.containsKey('parametros')) {
        await _log('🔍 [SYNC] Procesando catálogo especial: parametros (categorización dinámica)');
        batch.delete('parametros');
        List parametros = data['parametros'];
        for (var p in parametros) {
          final mapToInsert = Map<String, dynamic>.from(p);
          final String pName = p['nombre']?.toString() ?? 'Sin nombre';
          final String? pCat = p['categoria']?.toString();
          
          mapToInsert['activo'] = (p['activo'] == true) ? 1 : 0;
          mapToInsert['nombre'] = pName;
          mapToInsert['categoria'] = _resolveCategory(pCat, pName);
          
          batch.insert('parametros', mapToInsert);
        }
        await _log('   -> ${parametros.length} parámetros preparados con auto-categorización.');
      } else {
        await _log('⚠️ [SYNC] JSON no contiene llave "parametros". Saltando.');
      }

      if (data.containsKey('campanas')) {
        await _log('🔍 [SYNC] Desempacando datos anidados: campanas -> programs / stations');
        batch.delete('programs');
        batch.delete('stations');
        batch.delete('program_stations');

        List campanas = data['campanas'];
        int estacionesTotales = 0;

        for (var campana in campanas) {
          final int progId = campana['id'] is String ? int.parse(campana['id']) : (campana['id'] ?? 0);
          final String progName = campana['nombre']?.toString() ?? 'Programa Sin Nombre';

          batch.insert('programs', {'id': progId, 'name': progName}, conflictAlgorithm: ConflictAlgorithm.replace);

          final List<dynamic> listaEstaciones = campana['estaciones'] ?? [];
          estacionesTotales += listaEstaciones.length;

          for (var est in listaEstaciones) {
            int estId = est['id'] is String ? int.parse(est['id']) : (est['id'] ?? 0);

            // 🛡️ [SYNC-FIX] Fallback for missing ID to prevent overwrites
            if (estId == 0) {
              final String stationName = est['estacion']?.toString() ?? 'Sin Nombre';
              estId = stationName.hashCode.abs();
              await _log('⚠️ [SYNC-WARNING] Estación "$stationName" llegó sin ID válido. Usando ID fallback: $estId');
            }

            batch.insert('stations', {
              'id': estId,
              'name': est['estacion']?.toString() ?? 'Estación Sin Nombre',
              'latitude': est['latitud'] ?? 0.0,
              'longitude': est['longitud'] ?? 0.0
            }, conflictAlgorithm: ConflictAlgorithm.replace);

            batch.insert('program_stations', {
              'program_id': progId,
              'station_id': estId
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
          }
        }
        await _log('   -> ${campanas.length} programas y $estacionesTotales estaciones preparadas.');
      } else {
        await _log('⚠️ [SYNC] JSON no contiene llave "campanas". Saltando.');
      }

      if (data.containsKey('equipos')) {
        await _log('🔍 [SYNC] Desempacando datos anidados: equipos por tipo');
        batch.delete('equipos'); 
        List categorias = data['equipos'];
        int equiposTotales = 0;

        for (var categoria in categorias) {
          final String tipoEquipo = categoria['tipo']?.toString() ?? 'Sin Tipo';
          final List<dynamic> lista = categoria['equipos'] ?? [];
          equiposTotales += lista.length;

          for (var eq in lista) {
            batch.insert('equipos', {
              'id': eq['id'] ?? 0, 
              'codigo': eq['codigo']?.toString() ?? 'S/N', 
              'tipo': tipoEquipo,
              'id_form_fk': eq['id_form_fk'] ?? 0
            });
          }
        }
        await _log('   -> $equiposTotales equipos preparados.');
      } else {
        await _log('⚠️ [SYNC] JSON no contiene llave "equipos". Saltando.');
      }

      await _log('⚙️ [SYNC] Ejecutando inserción en lote (Batch Commit) en SQLite...');
      await batch.commit(noResult: true);
      await _log('✅ [SYNC-CATALOGOS] Sincronización finalizada exitosamente.');

    } catch (e, stacktrace) {
      await _log('❌ [SYNC-ERROR] Excepción capturada durante la sincronización:');
      await _log('   Mensaje: $e');
      await _log('   Traza: $stacktrace');
    }
  }
  Future<void> syncUsuarios(List<dynamic> usuarios) async {
    await _log('📥 [SYNC-USUARIOS] Sincronizando catálogo de usuarios...');
    final db = await database;
    Batch batch = db.batch();

    try {
      batch.delete('usuarios');
      for (var u in usuarios) {
        batch.insert('usuarios', u);
      }
      await batch.commit(noResult: true);
      await _log('✅ [SYNC-USUARIOS] Éxito. ${usuarios.length} usuarios sincronizados.');
    } catch (e, stacktrace) {
      await _log('❌ [SYNC-USUARIOS] ERROR: $e');
      await _log('   Traza: $stacktrace');
      rethrow;
    }
  }

  Future<void> syncCampanas(List<dynamic> campanas) async {
    await _log('📥 [SYNC-CAMPANAS] Sincronizando programas y estaciones...');
    final db = await database;
    Batch batch = db.batch();

    try {
      batch.delete('programs');
      batch.delete('stations');
      batch.delete('program_stations');

      int estacionesTotales = 0;
      for (var campana in campanas) {
        final int progId = campana['id'] is String ? int.parse(campana['id']) : (campana['id'] ?? 0);
        final String progName = campana['nombre']?.toString() ?? 'Programa Sin Nombre';

        batch.insert('programs', {'id': progId, 'name': progName}, conflictAlgorithm: ConflictAlgorithm.replace);

        final List<dynamic> listaEstaciones = campana['estaciones'] ?? [];
        estacionesTotales += listaEstaciones.length;

        for (var est in listaEstaciones) {
          int estId = est['id'] is String ? int.parse(est['id']) : (est['id'] ?? 0);

          // 🛡️ [SYNC-FIX] Fallback for missing ID to prevent overwrites
          if (estId == 0) {
            final String stationName = est['estacion']?.toString() ?? 'Sin Nombre';
            estId = stationName.hashCode.abs();
            await _log('⚠️ [SYNC-WARNING] Estación "$stationName" llegó sin ID válido. Usando ID fallback: $estId');
          }

          batch.insert('stations', {
            'id': estId,
            'name': est['estacion']?.toString() ?? 'Estación Sin Nombre',
            'latitude': est['latitud'] ?? 0.0,
            'longitude': est['longitud'] ?? 0.0
          }, conflictAlgorithm: ConflictAlgorithm.replace);

          batch.insert('program_stations', {
            'program_id': progId,
            'station_id': estId
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        }
      }
      await batch.commit(noResult: true);
      await _log('✅ [SYNC-CAMPANAS] Éxito. ${campanas.length} programas y $estacionesTotales estaciones sincronizadas.');
    } catch (e, stacktrace) {
      await _log('❌ [SYNC-CAMPANAS] ERROR: $e');
      await _log('   Traza: $stacktrace');
      rethrow;
    }
  }

  Future<int> getDistinctHistoricalSampleCount(String stationName) async {
    final db = await database;
    
    // Count distinct dates for a given station to get the true "Sample/Visit" count
    final List<Map<String, dynamic>> result = await db.rawQuery('''
      SELECT COUNT(DISTINCT fecha) as count 
      FROM historial_muestras 
      WHERE estacion = ?
    ''', [stationName]);

    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ─── NOTIFICACIONES PUSH ──────────────────────────────────────────────────

  // Controlador de stream para reactividad en la UI (broadcast para múltiples listeners)
  final StreamController<List<Map<String, dynamic>>> _notificacionesController = 
      StreamController<List<Map<String, dynamic>>>.broadcast();

  /// Stream para escuchar los cambios en notificaciones.
  Stream<List<Map<String, dynamic>>> get notificacionesStream => _notificacionesController.stream;

  /// Método privado para emitir el último estado de la tabla de notificaciones conectada al Stream.
  Future<void> _notificarCambios() async {
    final data = await obtenerNotificaciones();
    if (!_notificacionesController.isClosed) {
      _notificacionesController.add(data);
    }
  }

  /// Cierra el stream (generalmente no se llama porque DatabaseHelper es Singleton durante la vida de la app).
  void dispose() {
    _notificacionesController.close();
  }

  /// Inserta una notificación recibida en la base de datos local y notifica a los listeners.
  Future<int> insertarNotificacion(Map<String, dynamic> data) async {
    final db = await database;
    final id = await db.insert('notificaciones', data);
    await _notificarCambios();
    return id;
  }

  /// Retorna todas las notificaciones ordenadas por fecha descendente.
  Future<List<Map<String, dynamic>>> obtenerNotificaciones() async {
    final db = await database;
    return await db.query('notificaciones', orderBy: 'fecha DESC');
  }

  /// Elimina una notificación por su ID y notifica a los listeners.
  Future<int> deleteNotificacion(int id) async {
    final db = await database;
    final count = await db.delete('notificaciones', where: 'id = ?', whereArgs: [id]);
    await _notificarCambios();
    return count;
  }

  /// Elimina todas las notificaciones y notifica a los listeners.
  Future<int> deleteAllNotificaciones() async {
    final db = await database;
    final count = await db.delete('notificaciones');
    await _notificarCambios();
    return count;
  }
  /// Alterna el estado activo/inactivo de un parámetro por su ID.
  Future<int> toggleParametroStatus(int id, bool isActive) async {
    final db = await database;
    return await db.update(
      'parametros', 
      {'activo': isActive ? 1 : 0}, 
      where: 'id = ?', 
      whereArgs: [id]
    );
  }

  /// Obtiene solamente los parámetros que tienen el campo 'activo' en 1.
  Future<List<Parametro>> getActiveParametros() async {
    final db = await database;
    final maps = await db.query('parametros', where: 'activo = 1');
    return maps.map((map) {
      final adjusted = Map<String, dynamic>.from(map);
      adjusted['id_parametro'] = map['id'];
      adjusted['nombre_parametro'] = map['nombre'];
      adjusted['min'] = map['minimo'];
      adjusted['max'] = map['maximo'];
      return Parametro.fromJson(adjusted);
    }).toList();
  }

  /// Migración: Aplica categorías y unidades por defecto a todos los parámetros basándose en su nombre/clave.
  Future<void> migrateCategories() async {
    await _log('🛠️ [MIGRACIÓN] Iniciando asignación de categorías y unidades por defecto...');
    final db = await database;
    final List<Map<String, dynamic>> rows = await db.query('parametros');
    
    int count = 0;
    Batch batch = db.batch();
    
    for (var row in rows) {
      final String? currentCat = row['categoria']?.toString();
      final String? currentUnit = row['unidad']?.toString();
      final String pName = row['nombre']?.toString() ?? '';
      final String lowerName = pName.toLowerCase();
      
      // 1. Resolve Category
      final String resolvedCat = _resolveCategory(currentCat, pName);
      
      // 2. Resolve Unit (Standardization)
      String? resolvedUnit = currentUnit;
      if (resolvedUnit == null || resolvedUnit.isEmpty || resolvedUnit == 'Adim.') {
        if (lowerName.contains('turbiedad')) {
          resolvedUnit = 'NTU';
        } else if (lowerName.contains('caudal')) {
          resolvedUnit = 'L/s';
        } else if (lowerName.contains('profundidad')) {
          resolvedUnit = 'm';
        } else if (lowerName.contains('nivel')) {
          resolvedUnit = 'm';
        } else if (lowerName == 'ph') {
          resolvedUnit = 'u.pH';
        }
      }
      
      // 3. Update if anything changed
      if (resolvedCat != currentCat || resolvedUnit != currentUnit) {
        batch.update('parametros', {
          'categoria': resolvedCat,
          'unidad': resolvedUnit
        }, where: 'id = ?', whereArgs: [row['id']]);
        count++;
      }
    }
    
    if (count > 0) {
      await batch.commit(noResult: true);
      await _log('✅ [MIGRACIÓN] Corregidos $count parámetros con metadatos sincronizados.');
    } else {
      await _log('ℹ️ [MIGRACIÓN] No se encontraron parámetros para corregir.');
    }
  }

}
