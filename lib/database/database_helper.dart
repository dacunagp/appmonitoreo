import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
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

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'collector.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE programs (
        id INTEGER PRIMARY KEY,
        name TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE stations (
        id INTEGER PRIMARY KEY,
        name TEXT,
        latitude REAL,
        longitude REAL
      )
    ''');

    await db.execute('''
      CREATE TABLE program_stations (
        program_id INTEGER,
        station_id INTEGER,
        PRIMARY KEY (program_id, station_id),
        FOREIGN KEY (program_id) REFERENCES programs (id),
        FOREIGN KEY (station_id) REFERENCES stations (id)
      )
    ''');
    
    await db.execute('''
      CREATE TABLE usuarios (
        id_usuario INTEGER PRIMARY KEY,
        nombre TEXT,
        apellido TEXT
      )
    ''');
    
    await db.execute('''
      CREATE TABLE metodos (
        id_metodo INTEGER PRIMARY KEY,
        metodo TEXT
      )
    ''');
    
    await db.execute('''
      CREATE TABLE matrices (
        id_matriz INTEGER PRIMARY KEY,
        nombre_matriz TEXT
      )
    ''');
    
    await db.execute('''
      CREATE TABLE tipos_equipo (
        id_form INTEGER PRIMARY KEY,
        tipo TEXT
      )
    ''');
    
    await db.execute('''
      CREATE TABLE equipos_detalle (
        id INTEGER PRIMARY KEY,
        codigo TEXT,
        id_form_fk INTEGER,
        FOREIGN KEY (id_form_fk) REFERENCES tipos_equipo (id_form)
      )
    ''');

    await db.execute('''
      CREATE TABLE registros_monitoreo (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        programa_id INTEGER,
        estacion_id INTEGER,
        fecha_hora TEXT,
        monitoreo_fallido INTEGER,
        observacion TEXT,
        matriz_id INTEGER,
        equipo_multi_id INTEGER,
        temp REAL,
        ph REAL,
        conductividad REAL,
        oxigeno REAL,
        turbidimetro_id INTEGER,
        turbiedad REAL,
        metodo_id INTEGER,
        hidroquimico INTEGER,
        isotopico INTEGER,
        cod_laboratorio TEXT,
        usuario_id INTEGER,
        FOREIGN KEY (usuario_id) REFERENCES usuarios (id_usuario)
      )
    ''');

    await db.execute('''
      CREATE TABLE historial_muestras (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        certificado TEXT,
        fecha TEXT,
        nivel REAL,
        caudal REAL,
        ph REAL,
        temperatura REAL,
        conductividad REAL,
        oxigeno REAL,
        SDT REAL,
        estacion TEXT
      )
    ''');
  }

  Future<void> syncData(Map<String, dynamic> allData) async {
    final db = await database;

    await db.transaction((txn) async {
      // 1. Campañas & Estaciones
      if (allData.containsKey('campanas')) {
        final List<dynamic> campanas = allData['campanas'] ?? [];
        for (var campanaJson in campanas) {
          final program = Program.fromJson(campanaJson);
          await txn.insert(
            'programs',
            program.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );

          final List<dynamic> estaciones = campanaJson['estaciones'] ?? [];
          for (var estacionJson in estaciones) {
            final station = Station.fromJson(estacionJson);
            await txn.insert(
              'stations',
              station.toMap(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );

            await txn.insert(
              'program_stations',
              {
                'program_id': program.id,
                'station_id': station.id,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
      }

      // 2. Usuarios
      if (allData.containsKey('usuarios')) {
        final List<dynamic> usuarios = allData['usuarios'] ?? [];
        for (var json in usuarios) {
          final usuario = Usuario.fromJson(json);
          await txn.insert(
            'usuarios',
            usuario.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }

      // 3. Métodos
      if (allData.containsKey('metodos')) {
        final List<dynamic> metodos = allData['metodos'] ?? [];
        for (var json in metodos) {
          final metodo = Metodo.fromJson(json);
          await txn.insert(
            'metodos',
            metodo.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }

      // 4. Matrices
      if (allData.containsKey('matriz_aguas')) {
        final List<dynamic> matrices = allData['matriz_aguas'] ?? [];
        for (var json in matrices) {
          final matriz = Matriz.fromJson(json);
          await txn.insert(
            'matrices',
            matriz.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }

      // 5. Equipos
      if (allData.containsKey('equipos')) {
        final List<dynamic> equiposRoot = allData['equipos'] ?? [];
        for (var rootJson in equiposRoot) {
          final tipoEquipo = TipoEquipo.fromJson(rootJson);
          await txn.insert(
            'tipos_equipo',
            tipoEquipo.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );

          final List<dynamic> detalles = rootJson['equipos'] ?? [];
          for (var detalleJson in detalles) {
            final equipoDetalle = EquipoDetalle.fromJson(detalleJson, tipoEquipo.idForm);
            await txn.insert(
              'equipos_detalle',
              equipoDetalle.toMap(),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
      }
    });
  }

  // Getters
  Future<List<Program>> getPrograms() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('programs');
    return maps.map((m) => Program(id: m['id'], name: m['name'])).toList();
  }

  Future<List<Station>> getStationsByProgram(int programId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT s.* FROM stations s
      INNER JOIN program_stations ps ON s.id = ps.station_id
      WHERE ps.program_id = ?
    ''', [programId]);

    return maps.map((m) => Station(
      id: m['id'],
      name: m['name'],
      latitude: m['latitude'],
      longitude: m['longitude']
    )).toList();
  }

  Future<List<Usuario>> getUsuarios() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('usuarios');
    return maps.map<Usuario>((m) => Usuario(
      idUsuario: m['id_usuario'],
      nombre: m['nombre'],
      apellido: m['apellido'],
    )).toList();
  }

  Future<List<Metodo>> getMetodos() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('metodos');
    return maps.map<Metodo>((m) => Metodo(
      idMetodo: m['id_metodo'],
      metodo: m['metodo'],
    )).toList();
  }

  Future<List<Matriz>> getMatrices() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('matrices');
    return maps.map<Matriz>((m) => Matriz(
      idMatriz: m['id_matriz'],
      nombreMatriz: m['nombre_matriz'],
    )).toList();
  }

  Future<List<TipoEquipo>> getTiposEquipo() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('tipos_equipo');
    return maps.map<TipoEquipo>((m) => TipoEquipo(
      idForm: m['id_form'],
      tipo: m['tipo'],
    )).toList();
  }

  Future<List<Map<String, dynamic>>> getStationsWithPrograms() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT s.*, p.name as program_name, p.id as program_id
      FROM stations s
      LEFT JOIN program_stations ps ON s.id = ps.station_id
      LEFT JOIN programs p ON ps.program_id = p.id
    ''');
  }

  Future<List<Map<String, dynamic>>> getEquiposByType(String type) async {
    final db = await database;
    return await db.rawQuery('''
      SELECT ed.* 
      FROM equipos_detalle ed
      INNER JOIN tipos_equipo te ON ed.id_form_fk = te.id_form
      WHERE te.tipo = ?
    ''', [type]);
  }

  // CRUD Operations - Usuarios
  Future<int> addUsuario(Usuario usuario) async {
    final db = await database;
    return await db.insert('usuarios', usuario.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<int> updateUsuario(Usuario usuario) async {
    final db = await database;
    return await db.update('usuarios', usuario.toMap(), where: 'id_usuario = ?', whereArgs: [usuario.idUsuario]);
  }
  Future<int> deleteUsuario(int id) async {
    final db = await database;
    return await db.delete('usuarios', where: 'id_usuario = ?', whereArgs: [id]);
  }

  // CRUD Operations - Metodos
  Future<int> addMetodo(Metodo metodo) async {
    final db = await database;
    return await db.insert('metodos', metodo.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<int> updateMetodo(Metodo metodo) async {
    final db = await database;
    return await db.update('metodos', metodo.toMap(), where: 'id_metodo = ?', whereArgs: [metodo.idMetodo]);
  }
  Future<int> deleteMetodo(int id) async {
    final db = await database;
    return await db.delete('metodos', where: 'id_metodo = ?', whereArgs: [id]);
  }

  // CRUD Operations - Matrices
  Future<int> addMatriz(Matriz matriz) async {
    final db = await database;
    return await db.insert('matrices', matriz.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<int> updateMatriz(Matriz matriz) async {
    final db = await database;
    return await db.update('matrices', matriz.toMap(), where: 'id_matriz = ?', whereArgs: [matriz.idMatriz]);
  }
  Future<int> deleteMatriz(int id) async {
    final db = await database;
    return await db.delete('matrices', where: 'id_matriz = ?', whereArgs: [id]);
  }

  // CRUD Operations - Programas
  Future<int> addProgram(Program program) async {
    final db = await database;
    return await db.insert('programs', program.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<int> updateProgram(Program program) async {
    final db = await database;
    return await db.update('programs', program.toMap(), where: 'id = ?', whereArgs: [program.id]);
  }
  Future<int> deleteProgram(int id) async {
    final db = await database;
    await db.delete('program_stations', where: 'program_id = ?', whereArgs: [id]);
    return await db.delete('programs', where: 'id = ?', whereArgs: [id]);
  }

  // CRUD Operations - Estaciones
  Future<int> addStation(Station station, int programId) async {
    final db = await database;
    final id = await db.insert('stations', station.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    await db.insert('program_stations', {'program_id': programId, 'station_id': station.id}, conflictAlgorithm: ConflictAlgorithm.replace);
    return id;
  }
  Future<int> updateStation(Station station) async {
    final db = await database;
    return await db.update('stations', station.toMap(), where: 'id = ?', whereArgs: [station.id]);
  }
  Future<int> deleteStation(int id) async {
    final db = await database;
    await db.delete('program_stations', where: 'station_id = ?', whereArgs: [id]);
    return await db.delete('stations', where: 'id = ?', whereArgs: [id]);
  }

  // CRUD Operations - Equipos
  Future<List<Map<String, dynamic>>> getAllEquiposWithTipo() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT ed.id, ed.codigo, ed.id_form_fk, te.tipo 
      FROM equipos_detalle ed
      LEFT JOIN tipos_equipo te ON ed.id_form_fk = te.id_form
    ''');
  }

  Future<int> addEquipo(Map<String, dynamic> equipo) async {
    final db = await database;
    return await db.insert('equipos_detalle', equipo, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> updateEquipo(Map<String, dynamic> equipo) async {
    final db = await database;
    return await db.update('equipos_detalle', equipo, where: 'id = ?', whereArgs: [equipo['id']]);
  }

  Future<int> deleteEquipo(int id) async {
    final db = await database;
    return await db.delete('equipos_detalle', where: 'id = ?', whereArgs: [id]);
  }

  // Registros de Monitoreo
  Future<int> addRegistroMonitoreo(Map<String, dynamic> registro) async {
    final db = await database;
    return await db.insert('registros_monitoreo', registro);
  }

  Future<List<Map<String, dynamic>>> getMonitoreosList() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT rm.id, rm.fecha_hora, rm.monitoreo_fallido, s.name as estacion_name 
      FROM registros_monitoreo rm
      LEFT JOIN stations s ON rm.estacion_id = s.id
      ORDER BY rm.fecha_hora DESC
    ''');
  }

  Future<List<Map<String, dynamic>>> getRegistrosMonitoreo() async {
    final db = await database;
    return await db.query('registros_monitoreo', orderBy: 'id DESC');
  }

  Future<int> deleteRegistroMonitoreo(int id) async {
    final db = await database;
    return await db.delete('registros_monitoreo', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteAllRegistrosMonitoreo() async {
    final db = await database;
    return await db.delete('registros_monitoreo');
  }

  Future<Map<String, dynamic>?> getRegistroMonitoreoById(int id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'registros_monitoreo',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) return maps.first;
    return null;
  }

  Future<int> updateRegistroMonitoreo(int id, Map<String, dynamic> data) async {
    final db = await database;
    return await db.update(
      'registros_monitoreo',
      data,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Historial de Muestras
  Future<void> insertHistorialMuestras(List<dynamic> muestras) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('historial_muestras');
      for (var m in muestras) {
        await txn.insert('historial_muestras', {
          'certificado': m['certificado'],
          'fecha': m['fecha'],
          'nivel': m['nivel'],
          'caudal': m['caudal'],
          'ph': m['ph'],
          'temperatura': m['temperatura'],
          'conductividad': m['conductividad'],
          'oxigeno': m['oxigeno'],
          'SDT': m['SDT'],
          'estacion': m['estacion'],
        });
      }
    });
  }

  Future<List<Map<String, dynamic>>> getHistorialMuestras() async {
    final db = await database;
    return await db.query('historial_muestras', orderBy: 'fecha DESC');
  }

  Future<List<String>> getEstacionesNombresByPrograma(int programaId) async {
    final db = await database;
    final List<Map<String, dynamic>> res = await db.rawQuery('''
      SELECT s.name 
      FROM stations s
      JOIN program_stations ps ON s.id = ps.station_id
      WHERE ps.program_id = ?
    ''', [programaId]);
    return res.map((row) => row['name'] as String).toList();
  }
}
