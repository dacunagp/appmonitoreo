import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../widgets/app_drawer.dart';

class HistorialScreen extends StatefulWidget {
  const HistorialScreen({super.key});

  @override
  State<HistorialScreen> createState() => _HistorialScreenState();
}

class _HistorialScreenState extends State<HistorialScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Map<String, dynamic>> _muestras = [];
  List<Map<String, dynamic>> _filteredMuestras = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadMuestras();
  }

  Future<void> _loadMuestras() async {
    setState(() => _isLoading = true);
    final data = await _dbHelper.getHistorialMuestras();
    setState(() {
      _muestras = data;
      _filteredMuestras = data;
      _isLoading = false;
    });
  }

  void _filterMuestras(String query) {
    setState(() {
      _filteredMuestras = _muestras
          .where((m) =>
              (m['estacion'] ?? '').toLowerCase().contains(query.toLowerCase()) ||
              (m['certificado'] ?? '').toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial de Muestras'),
      ),
      drawer: const AppDrawer(currentRoute: '/historial'),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              onChanged: _filterMuestras,
              decoration: InputDecoration(
                hintText: 'Buscar por estación o certificado...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: isDarkMode ? Colors.grey[900] : Colors.white,
              ),
            ),
          ),
          // List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredMuestras.isEmpty
                    ? const Center(child: Text('No se encontraron muestras'))
                    : ListView.builder(
                        itemCount: _filteredMuestras.length,
                        padding: const EdgeInsets.only(bottom: 20),
                        itemBuilder: (context, index) {
                          final item = _filteredMuestras[index];
                          return _buildMuestraCard(item, isDarkMode);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildMuestraCard(Map<String, dynamic> item, bool isDarkMode) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.science, color: Colors.blueAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item['estacion'] ?? 'Sin Estación',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                Text(
                  item['fecha'] ?? '',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Certificado: ${item['certificado'] ?? 'N/A'}',
              style: TextStyle(color: Colors.blueAccent.withOpacity(0.8), fontWeight: FontWeight.w500),
            ),
            const Divider(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _buildParam('pH', item['ph']),
                _buildParam('Cond.', item['conductividad'], unit: 'µS/cm'),
                _buildParam('SDT', item['SDT'], unit: 'mg/L'),
                _buildParam('Nivel', item['nivel'], unit: 'm'),
                _buildParam('Caudal', item['caudal'], unit: 'L/s'),
                _buildParam('Temp.', item['temperatura'], unit: '°C'),
                _buildParam('O2', item['oxigeno'], unit: 'mg/L'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildParam(String label, dynamic value, {String unit = ''}) {
    if (value == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.blueAccent.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$label: $value $unit',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
}
