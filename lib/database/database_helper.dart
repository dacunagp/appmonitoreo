import 'dart:io';
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

  // Función útil para leer el archivo de log si lo necesitas en el futuro
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
    
    // ⚠️ TEMPORARY: Reset database
    await _log('💣 [INIT] Destruyendo base de datos vieja para aplicar nuevo esquema...');
    await deleteDatabase(path);

    await _log('✨ [INIT] Creando base de datos SQLite en: $path');
    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await _log('🏗️ [SCHEMA] Construyendo tablas de la base de datos...');
    
    // 1. Long Format & Drafts
    // 🚨 AQUÍ ESTÁ EL FIX: La tabla ahora soporta absolutamente todos los datos del formulario
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
        is_draft INTEGER DEFAULT 0
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

    // 4. Flattened Catalogs (Updated with id_form_fk)
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
        minimo REAL, maximo REAL, activo INTEGER
      )
    ''');
    await _log('✅ [SCHEMA] Tablas construidas con éxito.');
  }

  // --- API Sync & Historical Data Methods (Long Format) ---

  Future<void> syncHistoricalData(List<Map<String, dynamic>> parsedData) async {
    await _log('🔄 [SYNC-HISTORIAL] Iniciando sincronización de historial de mediciones...');
    final db = await database;
    try {
      await db.delete('historial_mediciones', where: 'monitoreo_id IS NULL'); 
      Batch batch = db.batch();
      for (var row in parsedData) {
        batch.insert('historial_mediciones', row);
      }
      await batch.commit(noResult: true);
      await _log('✅ [SYNC-HISTORIAL] Éxito. ${parsedData.length} mediciones insertadas.');
    } catch (e) {
      await _log('❌ [SYNC-HISTORIAL] ERROR CRÍTICO al guardar historial: $e');
    }
  }

  Future<List<double>> getHistoricalValues(String estacion, String parametro) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'historial_mediciones',
      columns: ['valor'],
      where: 'estacion = ? AND parametro = ?',
      whereArgs: [estacion, parametro],
      orderBy: 'fecha ASC',
    );
    return maps.map((map) => (map['valor'] as num).toDouble()).toList();
  }

  Future<List<Map<String, dynamic>>> getHistorialMuestrasByStationName(String stationName) async {
    final db = await database;
    return await db.query(
      'historial_mediciones',
      where: 'estacion = ?',
      whereArgs: [stationName],
      orderBy: 'fecha DESC',
    );
  }

  Future<List<Map<String, dynamic>>> getHistorialMuestras() async {
    final db = await database;
    return await db.query('historial_mediciones', orderBy: 'fecha DESC');
  }

  Future<int> deleteSampleGroupByStation(String stationName) async {
    final db = await database;
    return await db.delete(
      'historial_mediciones',
      where: 'estacion = ?',
      whereArgs: [stationName],
    );
  }

  // --- Local Monitoreo CRUD (Forms) ---

  Future<int> addRegistroMonitoreo(Map<String, dynamic> registro) async {
    final db = await database;
    return await db.insert('monitoreos', registro);
  }

  Future<List<Map<String, dynamic>>> getMonitoreosList() async {
    final db = await database;
    // 🚨 FIX: Cambiamos 'fecha' por 'fecha_hora'
    return await db.query('monitoreos', orderBy: 'fecha_hora DESC');
  }

  Future<Map<String, dynamic>?> getRegistroMonitoreoById(int id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('monitoreos', where: 'id = ?', whereArgs: [id]);
    return maps.isNotEmpty ? maps.first : null;
  }

  Future<int> updateRegistroMonitoreo(int id, Map<String, dynamic> data) async {
    final db = await database;
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
  
  Future<int> saveMonitoreoTransaction(Map<String, dynamic> header, List<Map<String, dynamic>> detalles) async {
    final db = await database;
    int monitoreoId = header['id'] ?? 0;
    String estacion = header['estacion_id']?.toString() ?? 'S/N';
    String fecha = header['fecha_hora']?.toString() ?? DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      // 1. Insert or Update Header
      if (monitoreoId == 0) {
        header.remove('id'); // Double safeguard to ensure auto-increment
        monitoreoId = await txn.insert('monitoreos', header);
      } else {
        await txn.update('monitoreos', header, where: 'id = ?', whereArgs: [monitoreoId]);
        // Remove old details for this monitoreo during update to sync
        await txn.delete('historial_mediciones', where: 'monitoreo_id = ?', whereArgs: [monitoreoId]);
      }
      
      // 2. Insert Details (Parameters)
      for (var detalle in detalles) {
        detalle['monitoreo_id'] = monitoreoId;
        // Ensure station and date are available in detail if not provided
        detalle['estacion'] ??= estacion;
        detalle['fecha'] ??= fecha;
        await txn.insert('historial_mediciones', detalle);
      }
    });
    
    return monitoreoId;
  }

  // --- STRONGLY TYPED CATALOG METHODS ---

  Future<List<Usuario>> getUsuarios() async {
    final db = await database;
    final maps = await db.query('usuarios');
    return maps.map((map) => Usuario.fromJson(map)).toList();
  }

  Future<List<Program>> getPrograms() async {
    final db = await database;
    // Disfrazamos 'name' como 'nombre' para que Program.fromJson no reciba nulos
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
    // Disfrazamos todas las columnas al español para Station.fromJson
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

  Future<List<Map<String, dynamic>>> getStationsWithPrograms() async {
    final db = await database;
    // 🛡️ BLINDAJE SQL: 
    // 1. COALESCE asegura que NUNCA devuelva un 'null' a la pantalla.
    // 2. Devolvemos las llaves en inglés (name) Y en español (estacion) 
    //    para que la UI no falle sin importar cuál esté usando.
    // 3. LEFT JOIN asegura que las estaciones sin programa no rompan la app.
    return await db.rawQuery('''
      SELECT 
        s.id, 
        COALESCE(s.name, 'Sin nombre') AS name, 
        COALESCE(s.name, 'Sin nombre') AS estacion, 
        COALESCE(s.latitude, 0.0) AS latitude, 
        COALESCE(s.latitude, 0.0) AS latitud, 
        COALESCE(s.longitude, 0.0) AS longitude, 
        COALESCE(s.longitude, 0.0) AS longitud, 
        COALESCE(p.name, 'Sin Programa') AS program_name 
      FROM stations s
      LEFT JOIN program_stations ps ON s.id = ps.station_id
      LEFT JOIN programs p ON ps.program_id = p.id
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

  // --- CUD METHODS ---
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
    final map = item.toMap();
    map['id'] = map.remove('id_parametro');
    map['nombre'] = map.remove('nombre_parametro');
    map['minimo'] = map.remove('min');
    map['maximo'] = map.remove('max');
    return await db.insert('parametros', map);
  }
  Future<int> updateParametro(Parametro item) async {
    final db = await database;
    final map = item.toMap();
    map['id'] = map.remove('id_parametro');
    map['nombre'] = map.remove('nombre_parametro');
    map['minimo'] = map.remove('min');
    map['maximo'] = map.remove('max');
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

  // --- REFACTORED syncData (Bulletproof Null Safety + Narrative Logs) ---

  Future<void> syncData(Map<String, dynamic> data) async {
    await _log('📥 [SYNC-CATALOGOS] Iniciando proceso de sincronización general...');
    final db = await database;
    Batch batch = db.batch();

    try {
      // 1. Simple mappings
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

      // 2. Parametros
      if (data.containsKey('parametros')) {
        await _log('🔍 [SYNC] Procesando catálogo especial: parametros (conversión de booleanos)');
        batch.delete('parametros');
        List parametros = data['parametros'];
        for (var p in parametros) {
          final mapToInsert = Map<String, dynamic>.from(p);
          mapToInsert['activo'] = (p['activo'] == true) ? 1 : 0;
          mapToInsert['nombre'] = p['nombre']?.toString() ?? 'Sin nombre';
          batch.insert('parametros', mapToInsert);
        }
        await _log('   -> ${parametros.length} parámetros preparados.');
      } else {
        await _log('⚠️ [SYNC] JSON no contiene llave "parametros". Saltando.');
      }

      // 3. NESTED FLATTENING FOR CAMPANAS
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
            final int estId = est['id'] is String ? int.parse(est['id']) : (est['id'] ?? 0);

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

      // 4. Flattening Nested "Equipos"
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

      // Ejecutar la transacción completa
      await _log('⚙️ [SYNC] Ejecutando inserción en lote (Batch Commit) en SQLite...');
      await batch.commit(noResult: true);
      await _log('✅ [SYNC-CATALOGOS] Sincronización finalizada exitosamente.');

    } catch (e, stacktrace) {
      await _log('❌ [SYNC-ERROR] Excepción capturada durante la sincronización:');
      await _log('   Mensaje: $e');
      await _log('   Traza: $stacktrace');
    }
  }
}