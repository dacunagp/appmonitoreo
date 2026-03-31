import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';

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
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        throw Exception('Failed to load $endpoint: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('API Error ($endpoint): $e');
    }
  }

  Future<Map<String, dynamic>> fetchAllData() async {
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

    final Map<String, dynamic> allResults = {};

    try {
      final responses = await Future.wait(
        endpoints.map((e) => http.get(
          Uri.parse('$baseUrl$e'),
          headers: {'Authorization': basicAuth},
        )),
      );

      for (int i = 0; i < endpoints.length; i++) {
        if (responses[i].statusCode == 200) {
          final data = json.decode(responses[i].body);
          final endpointName = endpoints[i];

          if (data is Map<String, dynamic>) {
            // The API wrapped the response in an object (e.g., {"usuarios": [...]})
            allResults.addAll(data);
          } else if (data is List) {
            // The API sent a raw array (e.g., [...]). We wrap it manually using the endpoint name.
            // Clean the endpoint name if it contains slashes (e.g., 'api/usuarios' -> 'usuarios')
            final keyName = endpointName.split('/').last;
            allResults[keyName] = data;
          } else {
            debugPrint('⚠️ Formato desconocido para el endpoint $endpointName: ${data.runtimeType}');
          }
        } else {
          throw Exception('Failed to load ${endpoints[i]}: ${responses[i].statusCode}');
        }
      }

      return allResults;
    } catch (e) {
      throw Exception('Sync error: $e');
    }
  }

  // Keep old method for compatibility if needed, but point to new logic or mark as deprecated
  Future<Map<String, dynamic>> fetchPrograms() async {
    return fetchAllData();
  }

  Future<dynamic> fetchHistorialMuestras(String programa, List<String> estaciones) async {
    final config = await _dbHelper.getActiveUrlConfig();
    if (config == null) throw Exception('No hay una configuración de API activa.');

    final baseUrl = config['url']; // e.g. ...sync.php?endpoint=
    final auth = '${config['usuario']}:${config['contrasenia']}';
    final String basicAuth = 'Basic ${base64Encode(utf8.encode(auth))}';
    
    final endpointData = await _dbHelper.getEndpoints();
    String endpointName = 'muestras'; // Fallback
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
      final response = await http.post(
        Uri.parse(fullUrl),
        headers: {
          'Authorization': basicAuth,
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'programa': programa,
          'estaciones': estaciones,
        }),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to fetch muestras: ${response.statusCode}');
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
