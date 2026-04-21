import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../database/database_helper.dart';
import '../widgets/app_drawer.dart';
import '../models/models.dart';

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
      await _log('✅ Conexión establecida (Status: ${response.statusCode})');
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Conexión establecida con éxito'), backgroundColor: Colors.green)
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ No se pudo conectar al servidor. Verifica tu red e IP.'), backgroundColor: Colors.red),
      );
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
        return base64Encode(compressedBytes);
      } else {
        // Fallback to original bytes if compression fails
        final bytes = await file.readAsBytes();
        debugPrint('⚠️ Falló compresión para payload, usando original: ${(bytes.length / 1024).toStringAsFixed(2)} KB');
        return base64Encode(bytes);
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

    final int totalEnvios = _selectedIds.length;
    int enviosCompletados = 0;
    int enviosExitosos = 0;
    List<String> syncErrors = [];
    StateSetter? dialogSetState;

    // 1. Mostrar Loader Dinámico con StatefulBuilder
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            dialogSetState = setState;
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(color: Colors.blue),
                    const SizedBox(height: 20),
                    Text(
                      'Enviando ${enviosCompletados + 1 > totalEnvios ? totalEnvios : enviosCompletados + 1} de $totalEnvios...',
                      style: const TextStyle(color: Colors.blue, fontSize: 16, fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    final Stopwatch cronometroTotal = Stopwatch()..start();
    final Stopwatch cronometroRed = Stopwatch();
    debugPrint('⏱️ [TIEMPOS] Iniciando proceso de envío secuencial para $totalEnvios registros...');

    try {
      final config = await _dbHelper.getActiveUrlConfig();
      if (config == null) throw Exception('No hay URL configurada activa');
      
      final endpoints = await _dbHelper.getEndpoints();
      String endpointPath = 'sync/monitoreos';
      try {
        final target = endpoints.firstWhere((e) => e['nombre'].toString().contains('sync'));
        endpointPath = target['nombre'];
      } catch (_) {}

      final Uri syncUrl = Uri.parse(config['url'] + endpointPath);
      
      final prefs = await SharedPreferences.getInstance();
      final String token = prefs.getString('token') ?? '';
      
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

      // 🗺️ FETCH UNITS MAP ONCE FOR ALL RECORDS (PHASE 127)
      final List<Parametro> allParams = await _dbHelper.getParametros();
      final Map<String, String> unitsMap = {
        for (var p in allParams) p.claveInterna: p.unidad
      };

      // --- LOGICA SECUENCIAL ---
      for (var record in _recordsPending) {
        if (_selectedIds.contains(record['id'])) {
          try {
            final Stopwatch recordTimer = Stopwatch()..start();
            debugPrint('⏱️ [TIEMPOS] 🚀 Iniciando envío ${enviosCompletados + 1} de $totalEnvios (ID: ${record['id']})...');

            final List<Map<String, dynamic>> rawDetails = await _dbHelper.getHistorialMedicionesByMonitoreoId(record['id']);
            final List<Map<String, String>> formattedDetails = rawDetails.map((d) => {
              "parametro": d['parametro']?.toString() ?? '',
              "valor": d['valor']?.toString() ?? '0.0',
            }).toList();

            final monitoreo = Monitoreo.fromMap(record);
            final item = await monitoreo.toJsonForSync(
              compressPhoto: _compressAndEncodeImage,
              legacyDetalles: formattedDetails,
              unitsMap: unitsMap, // 🗺️ PASS UNITS HERE
            );

            final payload = {"monitoreos": [item]};
            final jsonBody = jsonEncode(payload);

            // 🩻 [DEEP DEBUG] Verify architecture BEFORE sending (trimmed for logs)
            final debugItem = Map<String, dynamic>.from(item)
              ..['foto_path'] = item['foto_path'] != null ? '[BASE64_IMAGE]' : null
              ..['foto_multiparametro'] = item['foto_multiparametro'] != null ? '[BASE64_IMAGE]' : null
              ..['foto_turbiedad'] = item['foto_turbiedad'] != null ? '[BASE64_IMAGE]' : null
              ..['foto_caudal'] = item['foto_caudal'] != null ? '[BASE64_IMAGE]' : null
              ..['foto_nivel_freatico'] = item['foto_nivel_freatico'] != null ? '[BASE64_IMAGE]' : null
              ..['foto_muestreo'] = item['foto_muestreo'] != null ? '[BASE64_IMAGE]' : null;
            
            debugPrint('🩻 [PHASE 115] Payload structure for ID ${record['id']}: ${jsonEncode({"monitoreos": [debugItem]})}');
            debugPrint('🩻 [DEEP DEBUG] Sending full payload (ID: ${record['id']})...');

            cronometroRed.start();
            final response = await http.post(
              syncUrl,
              headers: headers,
              body: jsonBody,
            ).timeout(const Duration(seconds: 30));
            cronometroRed.stop();

            debugPrint('🩻 [DEEP DEBUG] Status Code recibido: ${response.statusCode}');
            debugPrint('🩻 [DEEP DEBUG] Body recibido del servidor:');
            debugPrint(response.body); // El HTML o JSON con el stack trace del error 500

            if (response.statusCode == 200 || response.statusCode == 201) {
              final responseData = jsonDecode(response.body);

              if (responseData['status'] == 'success') {
                await _dbHelper.updateRegistroMonitoreo(record['id'], {'is_draft': 2});
                enviosExitosos++;
                if (dialogSetState != null) dialogSetState!(() {});
                debugPrint('⏱️ [TIEMPOS] ✅ Éxito: ${responseData['mensaje']} (${recordTimer.elapsedMilliseconds} ms)');
              } else {
                debugPrint('⏱️ [TIEMPOS] ⚠️ Rechazado: ${responseData['mensaje']} (${recordTimer.elapsedMilliseconds} ms)');
                throw Exception('Rechazado por API: ${responseData['mensaje'] ?? 'Error desconocido'}');
              }
            } else {
              String errorSnippet = response.body.length > 150 ? '${response.body.substring(0, 150)}...' : response.body;
              throw Exception('Error del servidor (${response.statusCode}): $errorSnippet');
            }
          } catch (e) {
            debugPrint('❌ [ENVIAR] Registro ${record['id']} falló: $e');
            syncErrors.add('ID ${record['id']}: ${e.toString().replaceAll('Exception: ', '')}');
          } finally {
            enviosCompletados++;
            if (dialogSetState != null) {
              dialogSetState!(() {});
            }
          }
        }
      }

      if (mounted) {
        Navigator.pop(context); // Cerrar loader
        
        if (syncErrors.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Todos los datos sincronizados correctamente'), backgroundColor: Colors.green)
          );
        } else {
          // Mostrar resumen de errores
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: enviosExitosos > 0 ? Colors.orange : Colors.red),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Resumen de Sincronización', overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('✔️ Éxitos: $enviosExitosos'),
                  Text('❌ Fallidos: ${syncErrors.length}'),
                  const Divider(),
                  const Text('Detalles de Errores:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 150,
                    width: double.maxFinite,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: syncErrors.length,
                      itemBuilder: (ctx, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 4.0),
                        child: Text('• ${syncErrors[i]}', style: const TextStyle(fontSize: 12, color: Colors.redAccent)),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('ENTENDIDO'),
                ),
              ],
            ),
          );
        }
        _loadData();
      }
    } catch (e) {
      debugPrint('❌ [ENVIAR] ERROR CRÍTICO FUERA DEL LOOP: $e');
      if (!mounted) return;
      Navigator.pop(context); // Cerrar loader
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error de conexión: $e'), backgroundColor: Colors.redAccent)
      );
    } finally {
      cronometroTotal.stop();
      debugPrint('⏱️ [TIEMPOS] 🏁 Proceso completo finalizado en ${cronometroTotal.elapsedMilliseconds / 1000} segundos.');
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

                    return InkWell(
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _selectedIds.remove(id);
                          } else {
                            _selectedIds.add(id);
                          }
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            Checkbox(
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
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    record['nombre_estacion'] ?? 'Estación Desconocida',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    formatDateTime(record['fecha_hora']),
                                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.check_circle_outline, color: Colors.amber),
                          ],
                        ),
                      ),
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
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.cloud_done, color: Colors.green),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record['nombre_estacion'] ?? 'Estación Desconocida',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      formatDateTime(record['fecha_hora']),
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}