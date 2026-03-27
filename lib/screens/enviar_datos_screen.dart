import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../database/database_helper.dart';
import '../widgets/app_drawer.dart';

class EnviarDatosScreen extends StatefulWidget {
  const EnviarDatosScreen({super.key});

  @override
  State<EnviarDatosScreen> createState() => _EnviarDatosScreenState();
}

class _EnviarDatosScreenState extends State<EnviarDatosScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  
  List<Map<String, dynamic>> _recordsPending = [];
  List<Map<String, dynamic>> _recordsSent = [];
  Set<int> _selectedIds = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  String formatDateTime(String? isoString) {
    if (isoString == null || isoString.isEmpty) return 'Sin fecha';
    try {
      final DateTime dt = DateTime.parse(isoString);
      return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return isoString; // fallback
    }
  }

  Future<void> _log(String message) async {
    debugPrint(message);
    // Aquí puedes mantener la lógica de escribir en el archivo txt si la tienes en dbHelper
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final allRecords = await _dbHelper.getMonitoreosList();
      setState(() {
        _recordsPending = allRecords.where((m) => m['is_draft'] == 0).toList();
        _recordsSent = allRecords.where((m) => m['is_draft'] == 2).toList();
        _selectedIds.clear();
      });
    } catch (e) {
      await _log('Error cargando datos: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _verificarConexion() async {
    try {
      final config = await _dbHelper.getActiveUrlConfig();
      if (config == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ No hay URL configurada')));
        return;
      }
      final String baseUrl = config['url'];
      final Uri testUrl = Uri.parse(baseUrl);
      
      await _log('🔍 Verificando conexión a: $baseUrl');
      
      final response = await http.get(testUrl).timeout(const Duration(seconds: 10));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ Conexión exitosa con el servidor en: $baseUrl'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ No se pudo conectar al servidor. Verifica tu red e IP.'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<String?> _compressAndEncodeImage(String? path) async {
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    try {
      // 🚨 COMPRESS BEFORE ENCODING TO BASE64
      final Uint8List? compressedBytes = await FlutterImageCompress.compressWithFile(
        path,
        minWidth: 800,
        minHeight: 800,
        quality: 70,
      );

      if (compressedBytes != null) {
        debugPrint('✅ Imagen comprimida para payload: ${(compressedBytes.length / 1024).toStringAsFixed(2)} KB');
        return 'data:image/jpeg;base64,${base64Encode(compressedBytes)}';
      } else {
        // Fallback to original bytes if compression fails
        final bytes = await file.readAsBytes();
        debugPrint('⚠️ Falló compresión para payload, usando original: ${(bytes.length / 1024).toStringAsFixed(2)} KB');
        return 'data:image/jpeg;base64,${base64Encode(bytes)}';
      }
    } catch (e) {
      await _log('Error comprimiendo imagen: $e');
      return null;
    }
  }

  Future<void> _enviarDatosSeleccionados() async {
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecciona al menos un registro para enviar')));
      return;
    }

    // 1. Mostrar Loader Estático
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                CircularProgressIndicator(color: Colors.blue),
                SizedBox(height: 20),
                Text(
                  'Sincronizando monitoreos con el servidor...',
                  style: TextStyle(color: Colors.blue, fontSize: 16, fontWeight: FontWeight.w500),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );

    try {
      final config = await _dbHelper.getActiveUrlConfig();
      if (config == null) throw Exception('No hay URL configurada activa');
      debugPrint('═══════════════════════════════════════════════════');
      debugPrint('🚀 [ENVIAR] Config activa: url=${config['url']}, usuario=${config['usuario']}');

      final endpoints = await _dbHelper.getEndpoints();
      debugPrint('🚀 [ENVIAR] Endpoints disponibles: ${endpoints.map((e) => e['nombre']).toList()}');
      String endpointPath = 'sync/monitoreos'; // Fallback
      
      try {
        final target = endpoints.firstWhere((e) => e['nombre'].toString().contains('sync'));
        endpointPath = target['nombre'];
        debugPrint('🚀 [ENVIAR] Endpoint encontrado: $endpointPath');
      } catch (_) {
        debugPrint('⚠️ [ENVIAR] No se encontró endpoint "sync", usando predeterminado: $endpointPath');
      }

      final Uri syncUrl = Uri.parse(config['url'] + endpointPath);
      debugPrint('🚀 [ENVIAR] URL completa: $syncUrl');
      List<Map<String, dynamic>> payloadList = [];

      final prefs = await SharedPreferences.getInstance();
      final String token = prefs.getString('token') ?? '';
      debugPrint('🚀 [ENVIAR] Token presente: ${token.isNotEmpty} (longitud: ${token.length})');

      for (var record in _recordsPending) {
        if (_selectedIds.contains(record['id'])) {
          final item = {
            "id": record['id'],
            "device_id": "MOBILE-DATA",
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
            "foto_path": await _compressAndEncodeImage(record['foto_path']),
            "foto_multiparametro": await _compressAndEncodeImage(record['foto_multiparametro']),
            "foto_turbiedad": await _compressAndEncodeImage(record['foto_turbiedad']),
          };
          debugPrint('───────────────────────────────────────────────────');
          debugPrint('📦 [ENVIAR] Registro id=${record['id']}:');
          item.forEach((key, value) {
            if (key.contains('foto') && value != null) {
              debugPrint('   $key: [base64 imagen, ${(value as String).length} chars]');
            } else {
              debugPrint('   $key: $value');
            }
          });
          payloadList.add(item);
        }
      }

      debugPrint('───────────────────────────────────────────────────');
      debugPrint('🚀 [ENVIAR] Total registros en payload: ${payloadList.length}');

      final payload = {"monitoreos": payloadList};
      final jsonBody = jsonEncode(payload);
      debugPrint('🚀 [ENVIAR] Tamaño del body JSON: ${jsonBody.length} caracteres');
      
      Map<String, String> headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

      if (token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
        debugPrint('🔑 [ENVIAR] Usando Autenticación Bearer Token.');
      } else {
        final auth = '${config['usuario']}:${config['contrasenia']}';
        headers['Authorization'] = 'Basic ${base64Encode(utf8.encode(auth))}';
        debugPrint('🔑 [ENVIAR] Token vacío. Usando Autenticación Basic (user: ${config['usuario']}).');
      }

      debugPrint('🚀 [ENVIAR] Headers: $headers');
      debugPrint('🚀 [ENVIAR] Enviando POST a $syncUrl ...');

      final response = await http.post(
        syncUrl,
        headers: headers,
        body: jsonBody,
      ).timeout(const Duration(seconds: 30));

      debugPrint('═══════════════════════════════════════════════════');
      debugPrint('📥 [RESPUESTA] Status Code: ${response.statusCode}');
      debugPrint('📥 [RESPUESTA] Headers: ${response.headers}');
      debugPrint('📥 [RESPUESTA] Body: ${response.body}');
      debugPrint('═══════════════════════════════════════════════════');

      if (response.statusCode == 200 || response.statusCode == 201) {
        for (int id in _selectedIds) {
          await _dbHelper.updateRegistroMonitoreo(id, {'is_draft': 2}); // 2 = Enviado
        }
        debugPrint('✅ [ENVIAR] Todos los registros marcados como enviados.');
        if (mounted) {
          Navigator.pop(context); // Cerrar loader
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Datos sincronizados correctamente'), backgroundColor: Colors.green));
          _loadData();
        }
      } else {
        debugPrint('❌ [ENVIAR] Error del servidor: ${response.statusCode} - ${response.body}');
        throw Exception('Error del servidor: ${response.statusCode} - ${response.body}');
      }
    } catch (e, stackTrace) {
      debugPrint('═══════════════════════════════════════════════════');
      debugPrint('❌ [ENVIAR] EXCEPCIÓN: $e');
      debugPrint('❌ [ENVIAR] STACK TRACE: $stackTrace');
      debugPrint('═══════════════════════════════════════════════════');
      if (mounted) {
        Navigator.pop(context); // Cerrar loader
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error al enviar: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Enviar Datos'),
          backgroundColor: Theme.of(context).primaryColor,
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onSelected: (value) {
                if (value == 'enviar') _enviarDatosSeleccionados();
                if (value == 'verificar') _verificarConexion();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'enviar', child: ListTile(leading: Icon(Icons.cloud_upload), title: Text('Enviar datos a servidor'))),
                const PopupMenuItem(value: 'verificar', child: ListTile(leading: Icon(Icons.sync_alt), title: Text('Verificar conexion con servidor'))),
              ],
            )
          ],
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'SIN ENVIAR'),
              Tab(text: 'ENVIADOS'),
            ],
          ),
        ),
        drawer: const AppDrawer(currentRoute: '/enviar_datos'),
        body: TabBarView(
          children: [
            _buildSinEnviarTab(isDark),
            _buildEnviadosTab(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildSinEnviarTab(bool isDark) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    
    final bool allSelected = _recordsPending.isNotEmpty && _selectedIds.length == _recordsPending.length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Buscar',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Theme.of(context).cardColor,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8.0),
          child: Row(
            children: [
              Checkbox(
                value: allSelected,
                onChanged: (val) {
                  setState(() {
                    if (val == true) {
                      _selectedIds = _recordsPending.map((r) => r['id'] as int).toSet();
                    } else {
                      _selectedIds.clear();
                    }
                  });
                },
              ),
              const Text('Seleccionar Todo', style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              if (_selectedIds.isNotEmpty)
                Text('${_selectedIds.length} seleccionados', style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        const Divider(),
        Expanded(
          child: _recordsPending.isEmpty
              ? const Center(child: Text('No hay datos pendientes de envío', style: TextStyle(color: Colors.grey)))
              : ListView.builder(
                  itemCount: _recordsPending.length,
                  itemBuilder: (context, index) {
                    final record = _recordsPending[index];
                    final int id = record['id'];
                    final bool isSelected = _selectedIds.contains(id);

                    return ListTile(
                      leading: Checkbox(
                        value: isSelected,
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedIds.add(id);
                            } else {
                              _selectedIds.remove(id);
                            }
                          });
                        },
                      ),
                      title: Text(record['nombre_estacion'] ?? 'Estación Desconocida', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(formatDateTime(record['fecha_hora'])),
                      trailing: const Icon(Icons.check_circle_outline, color: Colors.amber),
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _selectedIds.remove(id);
                          } else {
                            _selectedIds.add(id);
                          }
                        });
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEnviadosTab(bool isDark) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_recordsSent.isEmpty) return const Center(child: Text('No hay datos enviados', style: TextStyle(color: Colors.grey)));

    return ListView.builder(
      itemCount: _recordsSent.length,
      itemBuilder: (context, index) {
        final record = _recordsSent[index];
        return ListTile(
          leading: const Icon(Icons.cloud_done, color: Colors.green),
          title: Text(record['nombre_estacion'] ?? 'Estación Desconocida', style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(formatDateTime(record['fecha_hora'])),
        );
      },
    );
  }
}