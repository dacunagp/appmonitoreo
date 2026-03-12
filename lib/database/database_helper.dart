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

  Future<List<Program>> getPrograms() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('programs');
    return List.generate(maps.length, (i) {
      return Program(
        id: maps[i]['id'],
        name: maps[i]['name'],
      );
    });
  }

  Future<List<Station>> getStationsByProgram(int programId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.rawQuery('''
      SELECT s.* FROM stations s
      INNER JOIN program_stations ps ON s.id = ps.station_id
      WHERE ps.program_id = ?
    ''', [programId]);

    return List.generate(maps.length, (i) {
      return Station(
        id: maps[i]['id'],
        name: maps[i]['name'],
        latitude: maps[i]['latitude'],
        longitude: maps[i]['longitude'],
      );
    });
  }

  // New Getters for Data Viewer

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

  Future<List<EquipoDetalle>> getEquiposDetalle(int idForm) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'equipos_detalle',
      where: 'id_form_fk = ?',
      whereArgs: [idForm],
    );
    return maps.map<EquipoDetalle>((m) => EquipoDetalle(
      id: m['id'],
      codigo: m['codigo'],
      idFormFk: m['id_form_fk'],
    )).toList();
  }

  // --- CRUD Operations ---

  // Usuarios
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

  // Métodos
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

  // Matrices
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

  // Programas
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

  // Estaciones
  Future<int> addStation(Station station, int programId) async {
    final db = await database;
    final id = await db.insert('stations', station.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    await db.insert('program_stations', {
      'program_id': programId,
      'station_id': station.id,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
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

  Future<List<Map<String, dynamic>>> getStationsWithPrograms() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT s.*, p.name as program_name, p.id as program_id
      FROM stations s
      LEFT JOIN program_stations ps ON s.id = ps.station_id
      LEFT JOIN programs p ON ps.program_id = p.id
    ''');
  }
}
