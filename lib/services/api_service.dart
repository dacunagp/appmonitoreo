import 'dart:convert';
import 'package:http/http.dart' as http;
import '../database/database_helper.dart';
import '../models/models.dart';

class ApiService {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  Future<Map<String, dynamic>> fetchNamespacedEndpoint(String endpoint) async {
    final config = await _dbHelper.getActiveUrlConfig();
    if (config == null) throw Exception('No hay una configuración de API activa.');

    final baseUrl = config['url'];
    final auth = '${config['usuario']}:${config['contrasenia']}';
    final String basicAuth = 'Basic ${base64Encode(utf8.encode(auth))}';

    try {
      final response = await http.get(
        Uri.parse('$baseUrl$endpoint'),
        headers: {'Authorization': basicAuth},
      );

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);
        if (decoded is List) {
          // Si es una lista (FastAPI), la envolvemos en un mapa para no romper pantallas antiguas
          // Se detecta el tipo según el endpoint para usar la llave correcta
          String key = endpoint.split('/').last;
          if (key == 'campanas') key = 'campanas';
          if (key == 'usuarios') key = 'usuarios';
          return { key: decoded };
        }
        return decoded as Map<String, dynamic>;
      } else {
        throw Exception('Failed to load $endpoint: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('API Error ($endpoint): $e');
    }
  }

  Future<void> fetchAllData() async {
    final config = await _dbHelper.getActiveUrlConfig();
    if (config == null) throw Exception('No hay una configuración de API activa.');

    final baseUrl = config['url'];
    final auth = '${config['usuario']}:${config['contrasenia']}';
    final String basicAuth = 'Basic ${base64Encode(utf8.encode(auth))}';

    final endpointData = await _dbHelper.getEndpoints();
    final endpoints = endpointData
        .map((e) => e['nombre'].toString())
        .where((name) {
          final lowerName = name.toLowerCase();
          return lowerName != 'sync/monitoreos' && 
                 !lowerName.contains('muestra') && 
                 !lowerName.contains('historial');
        })
        .toList();
    
    if (endpoints.isEmpty) throw Exception('No hay endpoints configurados para sincronizar.');

    try {
      final responses = await Future.wait(
        endpoints.map((e) => http.get(
          Uri.parse('$baseUrl$e'),
          headers: {'Authorization': basicAuth},
        )),
      );

      for (int i = 0; i < endpoints.length; i++) {
        if (responses[i].statusCode != 200) continue;

        final decodedBody = json.decode(responses[i].body);
        final endpointName = endpoints[i].toLowerCase();

        // 1. Process Campañas / Programas
        if (endpointName.contains('campana')) {
          final listItems = _asList(decodedBody, 'campanas');
          final programs = listItems.map<Program>((j) => Program.fromJson(j)).toList();
          await _dbHelper.saveProgramsBatch(programs);
          
          // Also save stations for each program if nested
          for (var item in listItems) {
            final progId = item['id_campana'] ?? item['id'] ?? 0;
            final stationsJson = item['estaciones'] as List? ?? [];
            final stations = stationsJson.map<Station>((s) => Station.fromJson(s)).toList();
            if (progId != 0 && stations.isNotEmpty) {
              await _dbHelper.saveStationsBatch(progId, stations);
            }
          }
        }

        // 2. Process Usuarios / Inspectores
        if (endpointName.contains('usuario')) {
          final listItems = _asList(decodedBody, 'usuarios');
          final users = listItems.map<Usuario>((j) => Usuario.fromJson(j)).toList();
          await _dbHelper.saveUsersBatch(users);
        }

        // 3. Process Metodos
        if (endpointName.contains('metodo')) {
          final listItems = _asList(decodedBody, 'metodos');
          final metodos = listItems.map<Metodo>((j) => Metodo.fromJson(j)).toList();
          await _dbHelper.saveMetodosBatch(metodos);
        }

        // 4. Process Matrices
        if (endpointName.contains('matriz')) {
          final listItems = _asList(decodedBody, 'matrices');
          final matrices = listItems.map<Matriz>((j) => Matriz.fromJson(j)).toList();
          await _dbHelper.saveMatricesBatch(matrices);
        }

        // 5. Process Equipos
        if (endpointName.contains('equipo')) {
          final listItems = _asList(decodedBody, 'equipos');
          List<Map<String, dynamic>> flatEquipos = [];
          
          for (var item in listItems) {
            // Si el item contiene una lista 'equipos', es el formato antiguo agrupado
            if (item is Map && item.containsKey('equipos') && item['equipos'] is List) {
              final tipo = item['tipo'] ?? 'General';
              final eqs = item['equipos'] as List;
              for (var eq in eqs) {
                flatEquipos.add({
                  'id': eq['id_equipo'] ?? eq['id'] ?? 0,
                  'codigo': eq['codigo_equipo'] ?? eq['codigo'] ?? 'S/N',
                  'tipo': tipo,
                  'id_form_fk': eq['id_form'] ?? eq['id_form_fk'] ?? 0,
                });
              }
            } else {
              // Formato plano (FastAPI)
              flatEquipos.add({
                'id': item['id_equipo'] ?? item['id'] ?? 0,
                'codigo': item['codigo_equipo'] ?? item['codigo'] ?? 'S/N',
                'tipo': item['nombre_parametro'] ?? 'General',
                'id_form_fk': item['id_form'] ?? item['id_form_fk'] ?? 0,
              });
            }
          }
          await _dbHelper.saveEquiposBatch(flatEquipos);
        }

        // 6. Process Parametros
        if (endpointName.contains('parametro')) {
          final listItems = _asList(decodedBody, 'parametros');
          final params = listItems.map<Parametro>((j) => Parametro.fromJson(j)).toList();
          await _dbHelper.saveParametrosBatch(params);
        }
      }
    } catch (e) {
      throw Exception('Sync error: $e');
    }
  }

  // Helper to ensure we get a List from legacy (wrapped) or FastAPI (raw) formats
  List<dynamic> _asList(dynamic data, String key) {
    if (data is List) return data;
    if (data is Map && data.containsKey(key) && data[key] is List) return data[key];
    if (data is Map && data.containsKey('data') && data['data'] is List) return data['data'];
    return [];
  }

  Future<dynamic> fetchHistorialMuestras(String programa, List<String> estaciones) async {
    final config = await _dbHelper.getActiveUrlConfig();
    if (config == null) throw Exception('No hay una configuración de API activa.');

    final baseUrl = config['url'];
    final auth = '${config['usuario']}:${config['contrasenia']}';
    final String basicAuth = 'Basic ${base64Encode(utf8.encode(auth))}';
    
    final endpointData = await _dbHelper.getEndpoints();
    String endpointName = 'muestras'; 
    try {
      final target = endpointData.firstWhere(
        (e) => e['nombre'].toString().toLowerCase().contains('muestra') || 
               e['nombre'].toString().toLowerCase().contains('historial'),
        orElse: () => {'nombre': 'muestras'}
      );
      endpointName = target['nombre'];
    } catch (_) {}

    final fullUrl = baseUrl.contains('endpoint=') 
        ? baseUrl.replaceAll('endpoint=', 'endpoint=$endpointName')
        : '$baseUrl$endpointName';

    try {
      // FORCE POST as per Phase 42 requirements to fix HTTP 405
      final response = await http.post(
        Uri.parse(fullUrl),
        headers: {
          'Authorization': basicAuth,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'programa': programa,
          'id_campana': programa, // FastAPI resilience
          'estaciones': estaciones,
        }),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to fetch muestras (HTTP ${response.statusCode}): ${response.body}');
      }
    } catch (e) {
      throw Exception('API Error: $e');
    }
  }

  List<Map<String, dynamic>> transformToLongFormat(List<dynamic> apiData) {
    List<Map<String, dynamic>> longFormatList = [];
    const parameterKeys = ['nivel', 'caudal', 'ph', 'temperatura', 'conductividad', 'oxigeno', 'SDT', 'turbiedad'];

    for (var record in apiData) {
      String fecha = record['fecha'] ?? '';
      String estacion = record['estacion'] ?? '';

      for (String key in parameterKeys) {
        if (record[key] != null) {
          longFormatList.add({
            'monitoreo_id': null, // Historical data from API has no local parent
            'estacion': estacion,
            'fecha': fecha,
            'parametro': key,
            'valor': (record[key] as num).toDouble(), // Safely cast ints (10) and doubles (6.78)
          });
        }
      }
    }
    return longFormatList;
  }
}
