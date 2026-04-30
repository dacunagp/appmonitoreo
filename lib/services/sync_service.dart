import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../database/database_helper.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  bool _isSyncing = false;

  Future<void> performAutoSync() async {
    if (_isSyncing) return;
    
    final prefs = await SharedPreferences.getInstance();
    final bool autoSync = prefs.getBool('auto_sync') ?? false;
    if (!autoSync) return;

    _isSyncing = true;
    debugPrint('🔄 [SyncService] Iniciando auto-sync...');

    try {
      final dbHelper = DatabaseHelper();
      final List<Map<String, dynamic>> pending = await dbHelper.getPendingToSendMonitoreos();
      
      if (pending.isEmpty) {
        debugPrint('✅ [SyncService] No hay registros pendientes.');
        _isSyncing = false;
        return;
      }

      debugPrint('📤 [SyncService] Enviando ${pending.length} registros...');
      
      final config = await dbHelper.getActiveUrlConfig();
      if (config == null) {
        debugPrint('⚠️ [SyncService] No hay configuración de servidor activa.');
        _isSyncing = false;
        return;
      }

      final endpoints = await dbHelper.getEndpoints();
      String endpointPath = 'sync/monitoreos';
      try {
        final target = endpoints.firstWhere((e) => e['nombre'].toString().contains('sync'));
        endpointPath = target['nombre'];
      } catch (_) {}

      final Uri syncUrl = Uri.parse(config['url'] + endpointPath);
      final String token = prefs.getString('token') ?? '';
      
      List<Map<String, dynamic>> payloadList = [];
      for (var record in pending) {
        payloadList.add({
          "id": record['id'],
          "device_id": "AUTO-SYNC",
          "programa_id": record['programa_id'],
          "estacion_id": record['estacion_id'],
          "fecha_hora": record['fecha_hora'],
          "monitoreo_fallido": record['monitoreo_fallido'],
          "observacion": record['observacion'],
          "matriz_id": record['matriz_id'],
          "equipo_multi_id": record['equipo_multi_id'],
          "turbidimetro_id": record['turbidimetro_id'],
          "metodo_id": record['metodo_id'],
          "hidroquimico": record['hidroquimico'],
          "isotopico": record['isotopico'],
          "cod_laboratorio": record['cod_laboratorio'],
          "usuario_id": record['usuario_id'],
          "is_draft": 0,
          "equipo_nivel_id": record['equipo_nivel_id'],
          "tipo_pozo": record['tipo_pozo'],
          "fecha_hora_nivel": record['fecha_hora_nivel'],
          "temperatura": record['temperatura'],
          "ph": record['ph'],
          "conductividad": record['conductividad'],
          "oxigeno": record['oxigeno'],
          "turbiedad": record['turbiedad'],
          "profundidad": record['profundidad'],
          "nivel": record['nivel'],
          "latitud": record['latitud'],
          "longitud": record['longitud'],
          "detalles_json": record['detalles_json'],
          "multiparametros_json": record['multiparametros_json'],
          "equipo_caudal": record['equipo_caudal'],
          "nivel_caudal": record['nivel_caudal'],
          "fecha_hora_caudal": record['fecha_hora_caudal'],
          "foto_path": await _encodeImage(record['foto_path']),
          "foto_multiparametro": await _encodeImage(record['foto_multiparametro']),
          "foto_turbiedad": await _encodeImage(record['foto_turbiedad']),
          "foto_caudal": await _encodeImage(record['foto_caudal']),
          "foto_nivel_freatico": await _encodeImage(record['foto_nivel_freatico']),
          "foto_muestreo": await _encodeImage(record['foto_muestreo']),
          "firma_path": await _encodeImage(record['firma_path']),
        });
      }

      final payload = {"monitoreos": payloadList};
      
      Map<String, String> headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

      if (token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      } else {
        final auth = '${config['usuario']}:${config['contrasenia']}';
        headers['Authorization'] = 'Basic ${base64Encode(utf8.encode(auth))}';
      }

      final response = await http.post(
        syncUrl,
        headers: headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 60));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final db = await dbHelper.database;
        for (var record in pending) {
          await db.update('monitoreos', {
            'is_draft': 2,
            'sync_status': 'success'
          }, where: 'id = ?', whereArgs: [record['id']]);
        }
        debugPrint('✅ [SyncService] Sincronización exitosa.');
      } else {
        debugPrint('⚠️ [SyncService] Error en respuesta API: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('🚨 [SyncService] Error crítico: $e');
    } finally {
      _isSyncing = false;
    }
  }

  Future<String?> _encodeImage(String? path) async {
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    try {
      final Uint8List? compressedBytes = await FlutterImageCompress.compressWithFile(
        path,
        minWidth: 800,
        minHeight: 800,
        quality: 70,
      );
      if (compressedBytes != null) {
        return base64Encode(compressedBytes);
      } else {
        return base64Encode(file.readAsBytesSync());
      }
    } catch (e) {
      debugPrint('Error comprimiendo imagen: $e');
      return base64Encode(file.readAsBytesSync());
    }
  }
}
