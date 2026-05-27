import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import '../database/database_helper.dart';
import 'dart:convert';
import '../models/models.dart';
import '../widgets/app_drawer.dart';

class TrazabilidadScreen extends StatefulWidget {
  final int? monitoreoId; // Opcional: para filtrar por un monitoreo específico

  const TrazabilidadScreen({super.key, this.monitoreoId});

  @override
  State<TrazabilidadScreen> createState() => _TrazabilidadScreenState();
}

class _TrazabilidadScreenState extends State<TrazabilidadScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<AuditoriaCambio> _historial = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistorial();
  }

  Future<void> _loadHistorial() async {
    setState(() => _isLoading = true);
    try {
      // Regularizar estados de logs cuyos monitoreos ya subieron
      await _dbHelper.syncAuditoriaWithMonitoreoSincronizado();

      List<AuditoriaCambio> data;
      if (widget.monitoreoId != null) {
        data = await _dbHelper.getAuditoriaPorMonitoreo(widget.monitoreoId!);
      } else {
        final db = await _dbHelper.database;
        final List<Map<String, dynamic>> maps = await db.query(
          'trazabilidad_cambios',
          orderBy: 'registro_id DESC, created_at DESC'
        );
        data = maps.map((m) => AuditoriaCambio.fromMap(m)).toList();
      }
      setState(() => _historial = data);
    } catch (e) {
      debugPrint('Error cargando trazabilidad: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Agrupa el historial por registro_id manteniendo el orden
  Map<int, List<AuditoriaCambio>> _agruparPorMonitoreo() {
    final Map<int, List<AuditoriaCambio>> grupos = {};
    for (final item in _historial) {
      grupos.putIfAbsent(item.registroId, () => []).add(item);
    }
    return grupos;
  }

  Future<void> _confirmarBorrado() async {
    final TextEditingController passwordController = TextEditingController();
    bool obscureText = true;

    final bool? result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Confirmar Borrado'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.monitoreoId != null 
                ? '¿Estás seguro de que deseas borrar el historial de este registro?' 
                : '¿Estás seguro de que deseas borrar TODO el historial de trazabilidad?'),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                obscureText: obscureText,
                keyboardType: TextInputType.number,
                maxLength: 4,
                decoration: InputDecoration(
                  labelText: 'Ingresa el PIN de seguridad',
                  counterText: '',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(obscureText ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setDialogState(() => obscureText = !obscureText),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCELAR')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true), 
              child: const Text('BORRAR', style: TextStyle(color: Colors.white))
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      final storedPin = await _dbHelper.getPin();
      if (passwordController.text != storedPin) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PIN de seguridad incorrecto'), backgroundColor: Colors.red)
        );
        return;
      }

      if (widget.monitoreoId != null) {
        await _dbHelper.deleteAuditoriaPorMonitoreo(widget.monitoreoId!);
      } else {
        await _dbHelper.clearAllAuditoria();
      }
      
      _loadHistorial();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Historial borrado correctamente'))
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.monitoreoId != null 
          ? 'Cambios en Registro #${widget.monitoreoId}' 
          : 'Trazabilidad de Cambios'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_forever, color: Colors.white),
            onPressed: _confirmarBorrado,
            tooltip: 'Borrar historial',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadHistorial,
          )
        ],
      ),
      drawer: widget.monitoreoId == null ? const AppDrawer(currentRoute: '/trazabilidad') : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _historial.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history_toggle_off, size: 60, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      const Text('No se han registrado cambios todavía.',
                          style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                )
              : widget.monitoreoId != null
                  // Vista filtrada por un monitoreo específico: lista plana
                  ? _buildFlatList(isDarkMode)
                  // Vista global: agrupada por monitoreo ID
                  : _buildGroupedList(isDarkMode),
    );
  }

  /// Vista agrupada por monitoreo ID (pantalla global)
  Widget _buildGroupedList(bool isDarkMode) {
    final grupos = _agruparPorMonitoreo();
    final monitoreoIds = grupos.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: monitoreoIds.length,
      itemBuilder: (context, index) {
        final monitoreoId = monitoreoIds[index];
        final cambios = grupos[monitoreoId]!;
        final ultimaFecha = cambios.first.createdAt;

        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              leading: CircleAvatar(
                backgroundColor: Colors.blueAccent.withOpacity(0.15),
                child: Text(
                  '#$monitoreoId',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.blueAccent,
                  ),
                ),
              ),
              title: Text(
                cambios.first.idUnica ?? cambios.first.registroRef ?? 'Monitoreo #$monitoreoId',
                style: TextStyle(
                  fontWeight: FontWeight.bold, 
                  fontSize: 14,
                  fontFamily: cambios.first.idUnica != null ? 'monospace' : null,
                  color: cambios.first.idUnica != null ? Colors.blueAccent : null,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (cambios.first.idUnica != null && cambios.first.registroRef != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, bottom: 4),
                      child: Text(
                        cambios.first.registroRef!,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600], fontStyle: FontStyle.italic),
                      ),
                    ),
                  Row(
                    children: [
                      // Chip: cantidad de cambios
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${cambios.length} cambio${cambios.length == 1 ? '' : 's'}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.deepOrange),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Chip: estado de sincronización
                      Builder(builder: (_) {
                        final allSynced = cambios.every((c) => c.isSynced);
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: allSynced
                                ? Colors.green.withOpacity(0.12)
                                : Colors.amber.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                allSynced ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined,
                                size: 12,
                                color: allSynced ? Colors.green[700] : Colors.amber[800],
                              ),
                              const SizedBox(width: 4),
                              Text(
                                allSynced ? 'Enviado' : 'Pendiente',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: allSynced ? Colors.green[700] : Colors.amber[800],
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.grey.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            DateFormat('dd/MM/yyyy HH:mm').format(ultimaFecha),
                            style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              children: cambios.map((item) => _buildCambioCard(item, isDarkMode)).toList(),
            ),
          ),
        );
      },
    );
  }

  /// Vista plana (cuando se filtra por un monitoreo específico)
  Widget _buildFlatList(bool isDarkMode) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _historial.length,
      itemBuilder: (context, index) {
        return _buildCambioCard(_historial[index], isDarkMode);
      },
    );
  }

  /// Card individual de un cambio
  Widget _buildCambioCard(AuditoriaCambio item, bool isDarkMode) {
    Map<String, dynamic> cambiosParseados = {};
    try {
      if (item.cambios.isNotEmpty) {
        cambiosParseados = jsonDecode(item.cambios);
      }
    } catch (_) {}

    final List<Widget> camposWidgets = [];
    
    if (item.accion == 'delete') {
      camposWidgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            children: [
              const Icon(Icons.delete_forever, color: Colors.redAccent, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'REGISTRO ELIMINADO',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.redAccent,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'Este monitoreo fue borrado permanentemente del dispositivo.',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      cambiosParseados.forEach((campo, detalle) {
        String valorAnterior = '';
        String valorNuevo = '';
        if (detalle is Map) {
          valorAnterior = detalle['antes']?.toString() ?? '';
          valorNuevo = detalle['despues']?.toString() ?? '';
        }
        
        bool isCreation = valorAnterior.isEmpty;

        camposWidgets.add(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Campo: ${campo.toUpperCase()}',
                style: TextStyle(
                  fontSize: 11, 
                  color: Colors.grey[500], 
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w500
                ),
              ),
              const Divider(height: 16),
              if (isCreation)
                _buildValueColumn(
                  'Nuevo Valor', 
                  valorNuevo, 
                  Colors.green.withOpacity(0.1),
                  isDarkMode
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: _buildValueColumn(
                        'Valor Anterior', 
                        valorAnterior, 
                        Colors.red.withOpacity(0.1),
                        isDarkMode
                      ),
                    ),
                    const Icon(Icons.arrow_forward, size: 20, color: Colors.grey),
                    Expanded(
                      child: _buildValueColumn(
                        'Valor Nuevo', 
                        valorNuevo, 
                        Colors.green.withOpacity(0.1),
                        isDarkMode
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 12),
            ]
          )
        );
      });
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Card(
        elevation: 1,
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Fila 1: Referencia + Fecha ---
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.registroRef?.isEmpty ?? true ? 'Sin Contexto' : item.registroRef!,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blueAccent,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.access_time, size: 12, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          DateFormat('dd/MM/yyyy HH:mm').format(item.createdAt),
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.grey[700]),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // --- Fila 2: Sync badge + ID Única ---
              Row(
                children: [
                  // Badge de sincronización
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: item.isSynced
                          ? Colors.green.withOpacity(0.12)
                          : Colors.amber.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: item.isSynced ? Colors.green.shade300 : Colors.amber.shade400,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          item.isSynced ? Icons.cloud_done : Icons.cloud_upload_outlined,
                          size: 13,
                          color: item.isSynced ? Colors.green[700] : Colors.amber[800],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          item.isSynced ? 'Enviado a la Web' : 'Pendiente de envío',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: item.isSynced ? Colors.green[700] : Colors.amber[800],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ID Única (si existe asociada al registro)
                  if (item.idUnica != null) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.blueAccent.withOpacity(0.3), width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.tag, size: 13, color: Colors.blueAccent.withOpacity(0.8)),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                item.idUnica!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueAccent,
                                  fontFamily: 'monospace',
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),

              // --- Detalle de cambios ---
              if (camposWidgets.isNotEmpty)
                ...camposWidgets
              else
                const Text('No se pudo decodificar el detalle JSON del cambio',
                    style: TextStyle(color: Colors.red, fontSize: 12)),

              // --- Usuario ---
              Row(
                children: [
                  Icon(Icons.person, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(item.usuarioNombre, style: const TextStyle(fontWeight: FontWeight.w500)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildValueColumn(String label, String value, Color bgColor, bool isDarkMode) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.black26 : bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(
            value.isEmpty 
              ? (label == 'Valor Anterior' ? 'Nuevo' : '[Vacío]') 
              : value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
