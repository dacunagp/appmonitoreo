import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../database/database_helper.dart';
import '../models/models.dart';

class EnviarCorreoForm extends StatefulWidget {
  const EnviarCorreoForm({super.key});

  @override
  State<EnviarCorreoForm> createState() => _EnviarCorreoFormState();
}

class _EnviarCorreoFormState extends State<EnviarCorreoForm> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _destinatarioController = TextEditingController();
  final TextEditingController _asuntoController = TextEditingController();
  final TextEditingController _cuerpoController = TextEditingController();
  
  bool _isSending = false;
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Map<String, dynamic>> _selectedRecords = [];

  String _formatDate(String? isoString) {
    if (isoString == null || isoString.isEmpty) return 'Sin fecha';
    try {
      final DateTime dt = DateTime.parse(isoString);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return isoString;
    }
  }

  Future<void> _pickRecords() async {
    final allRecords = await _dbHelper.getSentMonitoreosList();
    if (!mounted) return;

    String dialogSearchQuery = '';
    
    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final filtered = allRecords.where((r) {
            final name = (r['nombre_estacion'] ?? '').toString().toLowerCase();
            return name.contains(dialogSearchQuery.toLowerCase());
          }).toList();

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.attachment, color: Colors.blue),
                SizedBox(width: 10),
                Text('Adjuntar Registros'),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 500,
              child: Column(
                children: [
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Buscar por estación...',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                    onChanged: (val) {
                      setDialogState(() => dialogSearchQuery = val);
                    },
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: filtered.isEmpty 
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_off, size: 48, color: Colors.grey.withOpacity(0.5)),
                              const SizedBox(height: 10),
                              const Text('No se encontraron registros enviados', style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final record = filtered[index];
                            final isSelected = _selectedRecords.any((r) => r['id'] == record['id']);
                            
                            return CheckboxListTile(
                              title: Text(record['nombre_estacion'] ?? 'Estación S/N', style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text('Inspector: ${record['nombre_inspector']} • ${_formatDate(record['fecha_hora'])}', style: const TextStyle(fontSize: 12)),
                              value: isSelected,
                              activeColor: Colors.blue,
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedRecords.add(record);
                                  } else {
                                    _selectedRecords.removeWhere((r) => r['id'] == record['id']);
                                  }
                                });
                                setDialogState(() {});
                              },
                            );
                          },
                        ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('CERRAR')),
              ElevatedButton(
                onPressed: () => Navigator.pop(context), 
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                child: const Text('ACEPTAR'),
              ),
            ],
          );
        },
      ),
    );
  }

  String _formatRecordsForEmail() {
    if (_selectedRecords.isEmpty) return '';
    
    StringBuffer buffer = StringBuffer();
    buffer.writeln('\n--- REGISTROS ADJUNTOS ---');
    for (var r in _selectedRecords) {
      buffer.writeln('• Estación: ${r['nombre_estacion']}');
      buffer.writeln('  Inspector: ${r['nombre_inspector']} | Fecha: ${_formatDate(r['fecha_hora'])}');
      if (r['ph'] != null) buffer.writeln('  pH: ${r['ph']}');
      if (r['temperatura'] != null) buffer.writeln('  Temp: ${r['temperatura']}°C');
      if (r['conductividad'] != null) buffer.writeln('  Cond: ${r['conductividad']} uS/cm');
      if (r['nivel'] != null) buffer.writeln('  Nivel: ${r['nivel']} m');
      if (r['observacion'] != null && r['observacion'].toString().isNotEmpty) {
        buffer.writeln('  Obs: ${r['observacion']}');
      }
      buffer.writeln('---------------------------');
    }
    return buffer.toString();
  }

  Future<void> _enviarCorreo() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSending = true);

    final destinatario = _destinatarioController.text.trim();
    final asunto = _asuntoController.text.trim();
    String cuerpo = _cuerpoController.text.trim();
    
    final String adjuntos = _formatRecordsForEmail();
    if (adjuntos.isNotEmpty) {
      cuerpo += '\n$adjuntos';
    }

    try {
      final config = await _dbHelper.getActiveUrlConfig();
      bool success = false;
      String? errorMsg;

      if (config != null) {
        final baseUrl = config['url'];
        final auth = '${config['usuario']}:${config['contrasenia']}';
        final String basicAuth = 'Basic ${base64Encode(utf8.encode(auth))}';
        
        try {
          final response = await http.post(
            Uri.parse('${baseUrl}enviar-correo'), 
            headers: {
              'Authorization': basicAuth,
              'Content-Type': 'application/json',
            },
            body: json.encode({
              'destinatario': destinatario,
              'asunto': asunto,
              'cuerpo': cuerpo,
            }),
          ).timeout(const Duration(seconds: 15));

          if (response.statusCode == 200 || response.statusCode == 201) {
            success = true;
          } else {
            errorMsg = 'Error servidor: ${response.statusCode}';
          }
        } catch (e) {
          errorMsg = e.toString();
        }
      } else {
        errorMsg = 'No hay configuración de API';
      }

      final registro = CorreoEnviado(
        destinatario: destinatario,
        asunto: asunto,
        cuerpo: cuerpo,
        fechaEnvio: DateTime.now(),
        estado: success ? 'Enviado' : 'Error',
        errorMensaje: errorMsg,
      );

      await _dbHelper.saveCorreoHistorial(registro);

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Correo enviado correctamente'), backgroundColor: Colors.green),
        );
        _formKey.currentState!.reset();
        _destinatarioController.clear();
        _asuntoController.clear();
        _cuerpoController.clear();
        setState(() => _selectedRecords = []);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('⚠️ El correo se registró pero el servidor falló: $errorMsg')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ Error inesperado: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Completa los campos para enviar una notificación vía correo electrónico.',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
            const SizedBox(height: 25),
            
            TextFormField(
              controller: _destinatarioController,
              decoration: InputDecoration(
                labelText: 'Destinatario',
                hintText: 'ejemplo@correo.com',
                prefixIcon: const Icon(Icons.email_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value == null || value.isEmpty) return 'Ingresa un destinatario';
                if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                  return 'Ingresa un email válido';
                }
                return null;
              },
            ),
            const SizedBox(height: 20),
            
            TextFormField(
              controller: _asuntoController,
              decoration: InputDecoration(
                labelText: 'Asunto',
                prefixIcon: const Icon(Icons.title),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              validator: (value) => (value == null || value.isEmpty) ? 'Ingresa un asunto' : null,
            ),
            const SizedBox(height: 20),

            Card(
              elevation: 0,
              color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.blueGrey[50],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.blue.withOpacity(0.2), width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.attachment_rounded, size: 20, color: Colors.blue),
                            const SizedBox(width: 8),
                            const Text('Registros Adjuntos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            if (_selectedRecords.isNotEmpty)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(12)),
                                child: Text('${_selectedRecords.length}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                        TextButton.icon(
                          onPressed: _pickRecords,
                          icon: const Icon(Icons.add_circle_outline, size: 20),
                          label: const Text('Adjuntar'),
                          style: TextButton.styleFrom(foregroundColor: Colors.blue),
                        ),
                      ],
                    ),
                  ),
                  if (_selectedRecords.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 0, 16, 20),
                      child: Text('Selecciona registros ya enviados para adjuntar un resumen técnico.', style: TextStyle(fontSize: 13, color: Colors.grey, fontStyle: FontStyle.italic)),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _selectedRecords.length,
                        itemBuilder: (context, idx) {
                          final r = _selectedRecords[idx];
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: isDarkMode ? Colors.black26 : Colors.white70,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.grey.withOpacity(0.1)),
                            ),
                            child: ListTile(
                              dense: true,
                              leading: const CircleAvatar(radius: 14, backgroundColor: Colors.blue, child: Icon(Icons.description, size: 14, color: Colors.white)),
                              title: Text(r['nombre_estacion'] ?? 'S/N', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              subtitle: Text('Inspector: ${r['nombre_inspector']} • ${_formatDate(r['fecha_hora'])}', style: const TextStyle(fontSize: 11)),
                              trailing: IconButton(
                                icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent, size: 20),
                                onPressed: () => setState(() => _selectedRecords.removeWhere((item) => item['id'] == r['id'])),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            TextFormField(
              controller: _cuerpoController,
              maxLines: 8,
              decoration: InputDecoration(
                labelText: 'Mensaje',
                alignLabelWithHint: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              validator: (value) => (value == null || value.isEmpty) ? 'Ingresa el contenido' : null,
            ),
            const SizedBox(height: 30),
            
            ElevatedButton.icon(
              onPressed: _isSending ? null : _enviarCorreo,
              icon: _isSending 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send),
              label: Text(_isSending ? 'Enviando...' : 'ENVIAR CORREO'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                backgroundColor: theme.primaryColor,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
