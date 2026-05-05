import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
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
      List<AuditoriaCambio> data;
      if (widget.monitoreoId != null) {
        data = await _dbHelper.getAuditoriaPorMonitoreo(widget.monitoreoId!);
      } else {
        // Si no hay ID, cargamos todo el historial global
        final db = await _dbHelper.database;
        final List<Map<String, dynamic>> maps = await db.query(
          'trazabilidad_cambios',
          orderBy: 'fecha_cambio DESC'
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
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _historial.length,
                  itemBuilder: (context, index) {
                    final item = _historial[index];

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.contexto.isEmpty ? 'Sin Contexto' : item.contexto,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.blueAccent,
                                          fontSize: 15,
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
                                            DateFormat('dd/MM/yy HH:mm').format(item.fechaCambio),
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w500,
                                              color: Colors.grey[700],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Campo: ${item.campo.toUpperCase()}',
                                  style: TextStyle(
                                    fontSize: 11, 
                                    color: Colors.grey[500], 
                                    fontStyle: FontStyle.italic,
                                    fontWeight: FontWeight.w500
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 20),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildValueColumn(
                                    'Valor Anterior', 
                                    item.valorAnterior, 
                                    Colors.red.withOpacity(0.1),
                                    isDarkMode
                                  ),
                                ),
                                const Icon(Icons.arrow_forward, size: 20, color: Colors.grey),
                                Expanded(
                                  child: _buildValueColumn(
                                    'Valor Nuevo', 
                                    item.valorNuevo, 
                                    Colors.green.withOpacity(0.1),
                                    isDarkMode
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Icon(Icons.person, size: 16, color: Colors.grey[600]),
                                const SizedBox(width: 4),
                                Text(item.nombreUsuario, 
                                  style: const TextStyle(fontWeight: FontWeight.w500)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildValueColumn(String label, String value, Color bgColor, bool isDarkMode) {
    return Container(
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
            value.isEmpty ? '[Vacío]' : value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
