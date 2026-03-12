import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../widgets/app_drawer.dart';

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
      return '${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')}/${dt.year} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
    } catch (_) {
      return isoStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final colorGris = isDarkMode ? Colors.grey.shade400 : Colors.black54;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Monitoreos'),
        actions: [
          IconButton(icon: const Icon(Icons.filter_list), onPressed: () {}),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: () {}),
          IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
        ],
      ),
      drawer: const AppDrawer(currentRoute: '/monitoreos'),
      body: Column(
        children: [
          // 1. Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0)),
              ),
            ),
          ),

          // 2. Summary Bar
          ListTile(
            leading: const Icon(Icons.engineering, color: Colors.blueAccent, size: 28),
            title: Text('Total Monitoreos', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: Colors.greenAccent, borderRadius: BorderRadius.circular(12)),
              child: Text('${_filteredMonitoreos.length}', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ),
          const Divider(height: 1),

          // 3. ListView
          Expanded(
            child: _isLoading 
                ? const Center(child: CircularProgressIndicator())
                : _filteredMonitoreos.isEmpty
                    ? const Center(child: Text('No hay registros de monitoreo'))
                    : ListView.separated(
                        itemCount: _filteredMonitoreos.length,
                        separatorBuilder: (ctx, i) => const Divider(height: 1),
                        itemBuilder: (ctx, index) {
                          final item = _filteredMonitoreos[index];
                          return ListTile(
                            leading: const Icon(Icons.location_on, color: Colors.blueAccent, size: 28),
                            title: Text(item['estacion_name'] ?? 'Sin Estación', style: const TextStyle(fontWeight: FontWeight.w500)),
                            subtitle: Text(_formatDate(item['fecha_hora'] ?? '')),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.done_all, color: Colors.green, size: 20),
                                const SizedBox(width: 8),
                                Icon(Icons.chevron_right, color: colorGris),
                              ],
                            ),
                            onTap: () {
                              // Ver detalle
                            },
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
