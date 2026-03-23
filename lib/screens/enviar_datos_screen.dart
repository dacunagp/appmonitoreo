import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../widgets/app_drawer.dart';
import '../database/database_helper.dart';

class EnviarDatosScreen extends StatefulWidget {
  const EnviarDatosScreen({super.key});

  @override
  State<EnviarDatosScreen> createState() => _EnviarDatosScreenState();
}

class _EnviarDatosScreenState extends State<EnviarDatosScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Map<String, dynamic>> _records = [];
  Set<int> _selectedIds = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPendingData();
  }

  Future<void> _loadPendingData() async {
    setState(() => _isLoading = true);
    final data = await _dbHelper.getPendingToSendMonitoreos();
    setState(() {
      _records = data;
      _isLoading = false;
      _selectedIds.clear();
    });
  }

  Future<void> _log(String message) async {
    final timestamp = DateTime.now().toIso8601String();
    final logMessage = '[$timestamp] $message';
    debugPrint(logMessage);
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/sync_log.txt');
      await file.writeAsString('$logMessage\n', mode: FileMode.append);
    } catch (e) {
      debugPrint('🚨 Error writing log: $e');
    }
  }

  Future<String?> _compressAndEncodeImage(String? path) async {
    if (path == null || path.isEmpty) return null;
    final file = File(path);
    if (!await file.exists()) return null;

    try {
      // NOTE: Without flutter_image_compress or 'image' package, 
      // we perform a straightforward Base64 encoding. 
      // Resizing logic would typically be inserted here.
      final bytes = await file.readAsBytes();
      final base64String = base64Encode(bytes);
      return 'data:image/jpeg;base64,$base64String';
    } catch (e) {
      await _log('⚠️ Error encoding image ($path): $e');
      return null;
    }
  }

  Future<void> _enviarDatosSeleccionados() async {
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, selecciona al menos un registro.')),
      );
      return;
    }

    await _log('🚀 [SYNC] Iniciando envío de ${_selectedIds.length} monitoreos al servidor...');
    
    // Show loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final config = await _dbHelper.getActiveUrlConfig();
      if (config == null) throw Exception('No hay una configuración de API activa.');

      final List<Map<String, dynamic>> payloadList = [];
      
      for (var record in _records) {
        if (_selectedIds.contains(record['id'])) {
          await _log('📦 [SYNC] Procesando registro ID: ${record['id']} (${record['nombre_estacion']})');
          
          final fotoPath = await _compressAndEncodeImage(record['foto_path']);
          final fotoMulti = await _compressAndEncodeImage(record['foto_multiparametro']);
          final fotoTurb = await _compressAndEncodeImage(record['foto_turbiedad']);

          payloadList.add({
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
            "foto_path": fotoPath,
            "foto_multiparametro": fotoMulti,
            "foto_turbiedad": fotoTurb,
          });
        }
      }

      final Map<String, dynamic> finalPayload = {"monitoreos": payloadList};
      final syncUrl = '${config['url']}sync/monitoreos';
      
      await _log('🌐 [SYNC] POST Request a: $syncUrl');
      await _log('📦 [SYNC] Payload a enviar: ${jsonEncode(finalPayload)}');
      
      final auth = '${config['usuario']}:${config['contrasenia']}';
      final String basicAuth = 'Basic ${base64Encode(utf8.encode(auth))}';

      final response = await http.post(
        Uri.parse(syncUrl),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'Authorization': basicAuth,
        },
        body: jsonEncode(finalPayload),
      ).timeout(const Duration(seconds: 30));

      await _log('📡 [SYNC] Respuesta del servidor: ${response.statusCode}');
      await _log('📄 [SYNC] Body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Mark as sent (is_draft = 2)
        for (int id in _selectedIds) {
          await _dbHelper.updateMonitoreoStatus(id, 2);
        }
        
        if (mounted) {
          Navigator.pop(context); // Close loading
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sincronización exitosa.')),
          );
          _loadPendingData();
        }
      } else {
        throw Exception('Servidor respondió con código ${response.statusCode}');
      }
    } catch (e) {
      await _log('❌ [SYNC] Error crítico: $e');
      if (mounted) {
        Navigator.pop(context); // Close loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _verificarConexion() async {
    await _log('🔍 [DEBUG] Verificando conexión con el servidor...');
    try {
      final config = await _dbHelper.getActiveUrlConfig();
      if (config == null) throw Exception('No hay configuración activa.');
      
      final auth = '${config['usuario']}:${config['contrasenia']}';
      final String basicAuth = 'Basic ${base64Encode(utf8.encode(auth))}';

      final response = await http.get(
        Uri.parse(config['url']),
        headers: {'Authorization': basicAuth},
      ).timeout(const Duration(seconds: 10));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Conexión: ${response.statusCode == 200 ? 'OK' : 'Error ${response.statusCode}'}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        drawer: const AppDrawer(currentRoute: '/enviar_datos'),
        appBar: AppBar(
          backgroundColor: Theme.of(context).primaryColor,
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text('Enviar Datos', style: TextStyle(color: Colors.white)),
          actions: [
            IconButton(
              icon: const Icon(Icons.storage, color: Colors.white),
              onPressed: _selectedIds.isEmpty ? null : _enviarDatosSeleccionados,
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onSelected: (value) {
                if (value == 'enviar') _enviarDatosSeleccionados();
                if (value == 'verificar') _verificarConexion();
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'enviar',
                  child: ListTile(
                    leading: Icon(Icons.storage),
                    title: Text('Enviar datos a servidor'),
                    dense: true,
                  ),
                ),
                const PopupMenuItem(
                  value: 'verificar',
                  child: ListTile(
                    leading: Icon(Icons.sync_alt),
                    title: Text('Verificar conexion con servidor'),
                    dense: true,
                  ),
                ),
              ],
            ),
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
        body: TabBarView(
          children: [
            // Tab 1: SIN ENVIAR
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildPendingList(),
            
            // Tab 2: ENVIADOS
            const Center(
              child: Text(
                'Sin elementos enviados',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingList() {
    if (_records.isEmpty) {
      return const Center(
        child: Text(
          'No hay datos pendientes de envío',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }

    final bool allSelected = _selectedIds.length == _records.length && _records.isNotEmpty;

    return Column(
      children: [
        // --- SEARCH BAR ---
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Buscar',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: Theme.of(context).cardColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.0),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 0),
            ),
          ),
        ),

        // --- SELECCIONAR TODO row ---
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4.0),
          child: Row(
            children: [
              Checkbox(
                value: allSelected,
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _selectedIds = _records.map((r) => r['id'] as int).toSet();
                    } else {
                      _selectedIds.clear();
                    }
                  });
                },
              ),
              const Text(
                'Seleccionar Todo',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (_selectedIds.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: Text(
                    '${_selectedIds.length} seleccionados',
                    style: TextStyle(color: Theme.of(context).primaryColor, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),

        const Divider(),

        // --- DATA LIST ---
        Expanded(
          child: ListView.separated(
            itemCount: _records.length,
            separatorBuilder: (context, index) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final record = _records[index];
              final int id = record['id'];
              final bool isSelected = _selectedIds.contains(id);

              return ListTile(
                leading: Checkbox(
                  value: isSelected,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selectedIds.add(id);
                      } else {
                        _selectedIds.remove(id);
                      }
                    });
                  },
                ),
                title: Text(
                  record['nombre_estacion'] ?? 'Estación Desconocida',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(record['fecha_hora'] ?? 'S/F'),
                trailing: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.yellowAccent.withValues(alpha: 0.5)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(
                    Icons.check_circle_outline,
                    color: Colors.yellowAccent,
                    size: 20,
                  ),
                ),
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
}
