import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  static const String _baseUrl = 'https://gpconsultores.cl/apicollector/sync.php?endpoint=';
  static const String _auth = 'collector:gp2026';

  Future<Map<String, dynamic>> fetchAllData() async {
    final String basicAuth = 'Basic ${base64Encode(utf8.encode(_auth))}';

    final endpoints = ['campanas', 'usuarios', 'metodos', 'matriz_aguas', 'equipos'];
    
    final Map<String, dynamic> allResults = {};

    try {
      final responses = await Future.wait(
        endpoints.map((e) => http.get(
          Uri.parse('$_baseUrl$e'),
          headers: {'Authorization': basicAuth},
        )),
      );

      for (int i = 0; i < endpoints.length; i++) {
        if (responses[i].statusCode == 200) {
          final data = json.decode(responses[i].body);
          allResults.addAll(data as Map<String, dynamic>);
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
}
