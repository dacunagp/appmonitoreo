import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../widgets/app_drawer.dart';
import 'registrar_monitoreo_screen.dart';

class MonitoreosScreen extends StatefulWidget {
  const MonitoreosScreen({super.key});

  @override
  State<MonitoreosScreen> createState() => _MonitoreosScreenState();
}

class _MonitoreosScreenState extends State<MonitoreosScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  bool _isLoading = true;
  List<Map<String, dynamic>> _monitoreos = [];
  List<Map<String, dynamic>> _filteredMonitoreos = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadMonitoreos();
    _searchController.addListener(_filterMonitoreos);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMonitoreos() async {
    setState(() => _isLoading = true);
    try {
      final data = await _dbHelper.getMonitoreosList();
      setState(() {
        _monitoreos = data;
        _filteredMonitoreos = data;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
      setState(() => _isLoading = false);
    }
  }

  void _filterMonitoreos() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredMonitoreos = _monitoreos.where((m) {
        final station = (m['estacion_name'] ?? '').toString().toLowerCase();
        return station.contains(query);
      }).toList();
    });
  }

  String _formatDate(String isoStr) {
    try {
      final dt = DateTime.parse(isoStr);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final colorGris = isDarkMode ? Colors.grey.shade400 : Colors.black54;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Monitoreos'),
        actions: [
          IconButton(icon: const Icon(Icons.filter_list), onPressed: () {}),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmarEliminarTodo(context),
          ),
          IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
        ],
      ),
      drawer: const AppDrawer(currentRoute: '/monitoreos'),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const RegistrarMonitoreoScreen()),
          ).then((_) => _loadMonitoreos());
        },
        backgroundColor: Colors.blueAccent,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: Column(
        children: [
          // 1. Modern Pill Search Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
            child: Container(
              decoration: BoxDecoration(
                boxShadow: isDarkMode
                    ? null
                    : [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Buscar registro...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: BorderSide(
                        color: Theme.of(context).primaryColor.withOpacity(0.5),
                        width: 1),
                  ),
                ),
              ),
            ),
          ),

          // 2. Summary Card
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Card(
              elevation: 1,
              color: isDarkMode ? null : Colors.blue.withAlpha(10),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.blueAccent.withAlpha(30),
                  child: const Icon(Icons.engineering, color: Colors.blueAccent),
                ),
                title: Text('Total Monitoreos',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface)),
                trailing: Chip(
                  label: Text('${_filteredMonitoreos.length}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  backgroundColor: isDarkMode
                      ? Colors.green.withAlpha(50)
                      : const Color(0xFFC8E6C9),
                ),
              ),
            ),
          ),

          // 3. ListView
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredMonitoreos.isEmpty
                    ? const Center(child: Text('No hay registros de monitoreo'))
                    : ListView.builder(
                        itemCount: _filteredMonitoreos.length,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        itemBuilder: (ctx, index) {
                          final item = _filteredMonitoreos[index];
                          final bool isDraft = item['is_draft'] == 1;
                          final bool isFallido = item['monitoreo_fallido'] == 'true' || item['monitoreo_fallido'] == 1 || item['monitoreo_fallido'] == 'SI';
                          
                          final String stationName = item['estacion_name'] ?? item['estacion_id']?.toString() ?? 'Sin Estación';
                          final String fechaStr = item['fecha_hora'] ?? item['fecha'] ?? 'Sin Fecha';
                          final String fecha = fechaStr.contains('T') ? fechaStr.split('T')[0] : fechaStr;

                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            child: Dismissible(
                              key: Key(item['id'].toString()),
                              direction: DismissDirection.endToStart,
                              background: Container(
                                decoration: BoxDecoration(
                                  color: Colors.redAccent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                alignment: Alignment.centerRight,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20),
                                child: const Icon(Icons.delete_outline,
                                    color: Colors.white),
                              ),
                              onDismissed: (direction) async {
                                await _dbHelper.deleteRegistroMonitoreo(item['id']);
                                setState(() {
                                  _monitoreos.removeWhere(
                                      (m) => m['id'] == item['id']);
                                  _filterMonitoreos();
                                });
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Registro eliminado')),
                                  );
                                }
                              },
                              child: Card(
                                margin: EdgeInsets.zero,
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  leading: CircleAvatar(
                                    backgroundColor: isDraft 
                                        ? Colors.orangeAccent 
                                        : (isFallido ? Colors.redAccent : Colors.green),
                                    child: Icon(
                                      isDraft ? Icons.edit_note : (isFallido ? Icons.error : Icons.check),
                                      color: Colors.white,
                                    ),
                                  ),
                                  title: Text(
                                    'Punto: $stationName',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Text(
                                        'Fecha: $fecha',
                                        style: TextStyle(color: colorGris, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                  trailing: isDraft
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.orange.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: Colors.orange),
                                          ),
                                          child: const Text('BORRADOR', style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold)),
                                        )
                                      : const Icon(Icons.arrow_forward_ios, size: 16),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) =>
                                            RegistrarMonitoreoScreen(
                                                registroId: item['id']),
                                      ),
                                    ).then((_) => _loadMonitoreos());
                                  },
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmarEliminarTodo(BuildContext context) async {
    final bool? confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar Todos los Registros',
            style: TextStyle(color: Colors.red)),
        content: const Text(
            '¿Está seguro de que desea eliminar TODOS los monitoreos guardados localmente? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR',
                style: TextStyle(color: Colors.blueAccent)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ELIMINAR', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmar == true) {
      await _dbHelper.deleteAllRegistrosMonitoreo();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Todos los registros eliminados'),
            backgroundColor: Colors.red,
          ),
        );
        _loadMonitoreos();
      }
    }
  }
}
