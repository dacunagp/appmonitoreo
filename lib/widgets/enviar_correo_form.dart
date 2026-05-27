import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../database/database_helper.dart';
import '../models/models.dart';
import '../services/auth_service.dart';

class EnviarCorreoForm extends StatefulWidget {
  const EnviarCorreoForm({super.key});

  @override
  State<EnviarCorreoForm> createState() => _EnviarCorreoFormState();
}

class _EnviarCorreoFormState extends State<EnviarCorreoForm> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _asuntoController = TextEditingController();
  final TextEditingController _mensajeExtraController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  
  bool _isSending = false;
  final DatabaseHelper _dbHelper = DatabaseHelper();
  
  List<Usuario> _usuarios = [];
  List<String> _destinatariosSeleccionados = [];
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadDestinatarios();
  }

  Future<void> _loadDestinatarios() async {
    final users = await _dbHelper.getUsuarios();
    setState(() {
      _usuarios = users;
    });
  }

  @override
  void dispose() {
    _asuntoController.dispose();
    _mensajeExtraController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _enviarCorreo() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_destinatariosSeleccionados.isEmpty) {
      _showSnackBar('Seleccione al menos un destinatario', isError: true);
      return;
    }

    setState(() => _isSending = true);

    final asunto = _asuntoController.text.trim();
    final cuerpo = _mensajeExtraController.text.trim();

    try {
      final config = await _dbHelper.getActiveUrlConfig();
      bool success = false;
      String? errorMsg;

      if (config != null) {
        final baseUrl = config['url'];
        final auth = '${config['usuario']}:${config['contrasenia']}';
        final String basicAuth = 'Basic ${base64Encode(utf8.encode(auth))}';
        
        final endpoints = await _dbHelper.getEndpoints();
        String endpointPath = 'enviar-correo';
        try {
          final target = endpoints.firstWhere((e) => e['nombre'].toString().contains('enviar-correo'));
          endpointPath = target['nombre'];
        } catch (_) {}

        final String fullUrl = '${baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'}$endpointPath';
        
        final response = await http.post(
          Uri.parse(fullUrl),
          headers: {
            'Authorization': basicAuth,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'destinatario': _destinatariosSeleccionados.join(','),
            'asunto': asunto,
            'cuerpo': cuerpo,
          }),
        ).timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          success = true;
        } else {
          errorMsg = jsonDecode(response.body)['detail'] ?? 'Error de servidor';
        }
      } else {
        errorMsg = "Configuración de servidor no encontrada.";
      }

      if (!mounted) return;
      
      try {
        await _dbHelper.saveCorreoHistorial(
          CorreoEnviado(
            destinatario: _destinatariosSeleccionados.join(','),
            asunto: asunto,
            cuerpo: cuerpo,
            fechaEnvio: DateTime.now(),
            estado: success ? 'Enviado' : 'Error',
            errorMensaje: success ? null : errorMsg,
          ),
        );
      } catch (dbErr) {
        debugPrint('Error guardando historial: $dbErr');
      }

      if (success) {
        _showSnackBar('✅ Notificación enviada', isError: false);
        
        // --- ANALYTICS NOTIFICATION (Fire and Forget) ---
        // Pasamos null en estacionId ya que se eliminó el selector
        _notificarAnalytics(asunto, cuerpo, null);

        setState(() {
          _asuntoController.clear();
          _mensajeExtraController.clear();
          _destinatariosSeleccionados.clear(); // Limpiar destinatarios
          _searchController.clear();
          _searchQuery = '';
        });
      } else {
        _showSnackBar('❌ Error: $errorMsg', isError: true);
      }
    } catch (e) {
      if (mounted) _showSnackBar('❌ Error: $e', isError: true);
      
      try {
        await _dbHelper.saveCorreoHistorial(
          CorreoEnviado(
            destinatario: _destinatariosSeleccionados.join(','),
            asunto: asunto,
            cuerpo: cuerpo,
            fechaEnvio: DateTime.now(),
            estado: 'Error',
            errorMensaje: e.toString(),
          ),
        );
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _notificarAnalytics(String asunto, String mensaje, int? estacionId) async {
    try {
      final config = await _dbHelper.getActiveUrlConfig();
      if (config == null) return;

      final baseUrl = config['url'];
      final auth = '${config['usuario']}:${config['contrasenia']}';
      final String basicAuth = 'Basic ${base64Encode(utf8.encode(auth))}';
      final String inspector = await AuthService().getUserName() ?? 'Inspector Desconocido';
      
      final String fullUrl = '${baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'}comunicaciones/notificar-email';

      await http.post(
        Uri.parse(fullUrl),
        headers: {
          'Authorization': basicAuth,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'inspector': inspector,
          'asunto': asunto,
          'mensaje': mensaje,
          'fecha': DateTime.now().toIso8601String(),
          'estacion_id': estacionId, // Será null, Laravel lo aceptará sin problema
        }),
      ).timeout(const Duration(seconds: 5));
      
      debugPrint('📊 [ANALYTICS] Notificación enviada exitosamente a FastAPI');
    } catch (e) {
      debugPrint('⚠️ [ANALYTICS] Error silencioso al notificar analíticas: $e');
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.blueAccent,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF121212) : const Color(0xFFF5F7FA),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 32),
              
              _buildSectionLabel('CONFIGURACIÓN DE ENVÍO'),
              const SizedBox(height: 12),
              _buildSectionCard(
                isDarkMode: isDarkMode,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildMultiSelectField(
                      label: 'Destinatarios',
                      icon: Icons.alternate_email_rounded,
                      isDarkMode: isDarkMode,
                    ),
                    const SizedBox(height: 20),
                    
                    TextFormField(
                      controller: _asuntoController,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        labelText: 'Asunto del reporte',
                        hintText: 'Ej: Reporte de fallas, Consulta de insumos...',
                        prefixIcon: const Icon(Icons.short_text_rounded, color: Colors.blueAccent),
                        filled: true,
                        fillColor: isDarkMode ? Colors.black26 : const Color(0xFFF8F9FA),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: const BorderSide(color: Colors.blueAccent, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Por favor, ingrese un asunto';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 28),
              
              _buildSectionLabel('DETALLES TÉCNICOS'),
              const SizedBox(height: 12),
              _buildSectionCard(
                isDarkMode: isDarkMode,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _mensajeExtraController,
                      maxLines: 8,
                      style: const TextStyle(fontSize: 15, height: 1.4),
                      decoration: InputDecoration(
                        hintText: 'Por favor, describa detalladamente la incidencia, solicitud o reporte aquí...',
                        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                        filled: true,
                        fillColor: isDarkMode ? Colors.black26 : const Color(0xFFF8F9FA),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: const BorderSide(color: Colors.blueAccent, width: 1.5),
                        ),
                        contentPadding: const EdgeInsets.all(20),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'La descripción técnica es obligatoria';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 48),
              _buildSubmitButton(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Centro de Notificaciones',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -1),
        ),
        SizedBox(height: 8),
        Text(
          'Envíe reportes, solicitudes o notificaciones directas al equipo de supervisión.',
          style: TextStyle(fontSize: 14, color: Colors.blueGrey, height: 1.4),
        ),
      ],
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: Colors.blueAccent,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildSectionCard({required Widget child, required bool isDarkMode}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDarkMode ? 0.2 : 0.04),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(
          color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.blueGrey.withOpacity(0.05),
        ),
      ),
      child: child,
    );
  }

  Widget _buildMultiSelectField({
    required String label,
    required IconData icon,
    required bool isDarkMode,
  }) {
    final filteredUsers = _usuarios.where((u) {
      final query = _searchQuery.toLowerCase();
      final name = '${u.nombre} ${u.apellido}'.toLowerCase();
      final email = (u.email ?? '').toLowerCase();
      return name.contains(query) || email.contains(query);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Theme(
          data: Theme.of(context).copyWith(
            dividerColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
          ),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            onExpansionChanged: (expanded) {
              if (!expanded) {
                FocusScope.of(context).unfocus();
              }
            },
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 16, color: Colors.blueAccent),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.blueAccent.withOpacity(0.9),
                      ),
                    ),
                  ],
                ),
                Text(
                  _destinatariosSeleccionados.isEmpty 
                      ? 'Seleccione' 
                      : '${_destinatariosSeleccionados.length} seleccionados',
                  style: TextStyle(
                    fontSize: 13, 
                    fontWeight: FontWeight.w500,
                    color: _destinatariosSeleccionados.isEmpty ? Colors.grey : Colors.blueAccent,
                  ),
                ),
              ],
            ),
            children: [
              Container(
                margin: const EdgeInsets.only(top: 8, bottom: 8),
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.white.withOpacity(0.05) : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    icon: Icon(Icons.search, size: 18, color: Colors.grey[600]),
                    hintText: 'Buscar destinatario...',
                    hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              Container(
                constraints: const BoxConstraints(maxHeight: 250),
                child: filteredUsers.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text('No se encontraron resultados', style: TextStyle(color: Colors.grey, fontSize: 13)),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: filteredUsers.length,
                        itemBuilder: (context, index) {
                          final u = filteredUsers[index];
                          final isSelected = _destinatariosSeleccionados.contains(u.email);
                          return CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: Colors.blueAccent,
                            dense: true,
                            title: Text(
                              '${u.nombre} ${u.apellido}',
                              style: const TextStyle(fontSize: 14),
                            ),
                            subtitle: Text(
                              u.email ?? 'Sin correo',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            value: isSelected,
                            onChanged: u.email == null || u.email!.isEmpty ? null : (bool? checked) {
                              setState(() {
                                if (checked == true) {
                                  _destinatariosSeleccionados.add(u.email!);
                                } else {
                                  _destinatariosSeleccionados.remove(u.email);
                                }
                              });
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        if (_destinatariosSeleccionados.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _destinatariosSeleccionados.map((email) {
              final usersMatched = _usuarios.where((u) => u.email == email);
              final displayName = usersMatched.isNotEmpty 
                  ? '${usersMatched.first.nombre} ${usersMatched.first.apellido}'.trim() 
                  : email;
              return Chip(
                label: Text(displayName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                deleteIcon: const Icon(Icons.cancel_rounded, size: 16),
                onDeleted: () {
                  setState(() {
                    _destinatariosSeleccionados.remove(email);
                  });
                },
                backgroundColor: isDarkMode ? Colors.blueAccent.withOpacity(0.15) : Colors.blueAccent.withOpacity(0.08),
                labelStyle: TextStyle(color: isDarkMode ? Colors.blue[200] : Colors.blue[800]),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: isDarkMode ? Colors.blueAccent.withOpacity(0.3) : Colors.blueAccent.withOpacity(0.2)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
              );
            }).toList(),
          ),
        ],
        if (_destinatariosSeleccionados.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10.0, left: 4),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 14, color: Colors.red[400]),
                const SizedBox(width: 6),
                Text('Selección requerida para enviar el reporte', 
                  style: TextStyle(color: Colors.red[400], fontSize: 12, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildSubmitButton() {
    return Container(
      width: double.infinity,
      height: 62,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF448AFF), Color(0xFF1976D2)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1976D2).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _isSending ? null : _enviarCorreo,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        child: _isSending 
            ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.send_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 12),
                  Text(
                    'ENVIAR REPORTE',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 0.5),
                  ),
                ],
              ),
      ),
    );
  }
}