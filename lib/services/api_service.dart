import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
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
      // Usaremos un bucle individual para tener más control sobre los errores y reintentos
      for (String endpoint in endpoints) {
        String currentEndpoint = endpoint;
        final String fullUrl = '$baseUrl$currentEndpoint';
        debugPrint('🌐 [SYNC] Petición a: $fullUrl');

        var response = await http.get(
          Uri.parse(fullUrl),
          headers: {'Authorization': basicAuth},
        ).timeout(const Duration(seconds: 30));

        // --- LÓGICA DE REINTENTO PARA OBSERVACIONES ---
        // Si falla con 404 y es el endpoint de observaciones, intentamos con el path alternativo
        if (response.statusCode == 404 && currentEndpoint.toLowerCase().contains('observacion')) {
          final String fallbackEndpoint = currentEndpoint.contains('/') 
              ? 'observaciones_predefinidas' 
              : 'catalogos/observaciones';
          
          debugPrint('🔄 [SYNC-RETRY] 404 en $currentEndpoint. Intentando con: $baseUrl$fallbackEndpoint');
          
          response = await http.get(
            Uri.parse('$baseUrl$fallbackEndpoint'),
            headers: {'Authorization': basicAuth},
          ).timeout(const Duration(seconds: 30));
          
          if (response.statusCode == 200) {
            currentEndpoint = fallbackEndpoint;
            debugPrint('✅ [SYNC-RETRY] Éxito con el path alternativo: $fallbackEndpoint');
          }
        }

        if (response.statusCode != 200) {
          debugPrint('❌ [SYNC-ERROR] $currentEndpoint falló (${response.statusCode})');
          continue;
        }

        final decodedBody = json.decode(response.body);
        final endpointName = currentEndpoint.toLowerCase();

        // 1. Process Campañas / Programas
        if (endpointName.contains('campana')) {
          final listItems = _asList(decodedBody, 'campanas');
          final programs = listItems.map<Program>((j) => Program.fromJson(j)).toList();
          await _dbHelper.saveProgramsBatch(programs);
          
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

        // 7. Process Observaciones Predefinidas (Phase 142)
        if (endpointName.contains('observacion')) {
          debugPrint('📥 [DEBUG-SYNC] Respuesta de $endpointName: ${response.body}');
          
          var listItems = _asList(decodedBody, 'observaciones');
          if (listItems.isEmpty) {
            listItems = _asList(decodedBody, 'observaciones_predefinidas');
          }
          
          List<String> observaciones = [];
          for (var item in listItems) {
            if (item is String) {
              observaciones.add(item);
            } else if (item is Map) {
              final val = item['texto'] ?? item['observacion'] ?? item['nombre'];
              if (val != null) observaciones.add(val.toString());
            }
          }
          if (observaciones.isNotEmpty) {
            await _dbHelper.saveObservacionesPredefinidasBatch(observaciones);
            debugPrint('✅ [SYNC-OBS] Se guardaron ${observaciones.length} observaciones.');
          } else {
            debugPrint('⚠️ [SYNC-OBS] No se encontraron observaciones en la respuesta.');
          }
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
          'programa': programa.toString(),
          'id_campana': programa.toString(),
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
