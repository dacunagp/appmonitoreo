import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import '../widgets/app_drawer.dart';

class HistorialScreen extends StatefulWidget {
  const HistorialScreen({super.key});

  @override
  State<HistorialScreen> createState() => _HistorialScreenState();
}

class _HistorialScreenState extends State<HistorialScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Map<String, dynamic>> _groupedPoints = [];
  List<Map<String, dynamic>> _filteredPoints = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    String? dateFilter;
    if (_selectedDate != null) {
      dateFilter = DateFormat('yyyy-MM-dd').format(_selectedDate!);
    }
    
    final data = await _dbHelper.getHistorialMuestras(dateFilter: dateFilter);

    // Grouping in Dart using collection package
    final grouped = groupBy(data, (Map m) => m['estacion'] ?? 'Sin Estación');

    final List<Map<String, dynamic>> processedPoints =
        grouped.entries.map((entry) {
      final samples = entry.value;
      // Sort samples by date descending to get the last sync date
      samples.sort((a, b) => (b['fecha'] ?? '').compareTo(a['fecha'] ?? ''));

      // 🚨 FIX: Parse and format the raw ISO date string
      String formattedDate = 'N/A';
      if (samples.isNotEmpty && samples.first['fecha'] != null) {
        try {
          DateTime dt = DateTime.parse(samples.first['fecha']);
          formattedDate = DateFormat('dd/MM/yyyy').format(dt);
        } catch (e) {
          formattedDate = samples.first['fecha'].toString();
        }
      }

      return {
        'estacion': entry.key,
        'count': samples.length,
        'last_sync_date': formattedDate,
      };
    }).toList();

    setState(() {
      _groupedPoints = processedPoints;
      _filteredPoints = processedPoints;
      _isLoading = false;
    });
  }

  void _filterPoints(String query) {
    setState(() {
      _filteredPoints = _groupedPoints
          .where((p) =>
              (p['estacion'] ?? '').toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  Future<void> _deleteStationGroup(String stationName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Borrado'),
        content: Text(
            '¿Desea eliminar TODAS las muestras de la estación "$stationName"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('ELIMINAR'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _dbHelper.deleteSampleGroupByStation(stationName);
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Estación $stationName eliminada')),
        );
      }
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      helpText: 'Filtrar por fecha',
      cancelText: 'Limpiar Filtro',
      confirmText: 'FILTRAR',
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
      _loadData();
    } else {
      // Si el usuario cancela, podríamos querer limpiar el filtro
      // Pero usualmente el botón "Cancelar" solo cierra.
      // Sin embargo, si queremos una forma de limpiar:
      if (_selectedDate != null) {
        setState(() {
          _selectedDate = null;
        });
        _loadData();
      }
    }
  }

  Future<void> _showDeleteAllConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar registros'),
        content: const Text(
            '¿Estás seguro de que deseas borrar todas las muestras mostradas? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('ELIMINAR', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _dbHelper.deleteAllHistorialMuestras();
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Todos los registros han sido eliminados')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Historial de Muestras'),
        actions: [
          IconButton(
            icon: Icon(
              _selectedDate == null ? Icons.filter_list : Icons.filter_list_off,
              color: _selectedDate != null ? Colors.orange : (isDarkMode ? Colors.white : null),
            ),
            onPressed: () => _selectDate(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _showDeleteAllConfirmation,
            color: isDarkMode ? Colors.white : null,
          ),
        ],
      ),
      drawer: const AppDrawer(currentRoute: '/historial'),
      body: Column(
        children: [
          // Search Bar - Relaxed Pill Shape
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
                onChanged: _filterPoints,
                style: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
                decoration: InputDecoration(
                  hintText: 'Buscar punto de monitoreo...',
                  hintStyle: TextStyle(
                    color: isDarkMode ? Colors.grey.shade400 : Colors.grey,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    size: 20,
                    color: isDarkMode ? Colors.white : Colors.grey,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
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
                        color: theme.primaryColor.withOpacity(0.5), width: 1),
                  ),
                ),
              ),
            ),
          ),
          // List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredPoints.isEmpty
                    ? const Center(
                        child: Text('No se encontraron puntos de monitoreo'))
                    : ListView.builder(
                        itemCount: _filteredPoints.length,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        itemBuilder: (context, index) {
                          final point = _filteredPoints[index];
                          final stationName = point['estacion'];

                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            child: Dismissible(
                              key: Key(stationName),
                              direction: DismissDirection.endToStart,
                              confirmDismiss: (direction) async {
                                await _deleteStationGroup(stationName);
                                return false;
                              },
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
                              child: Card(
                                margin: EdgeInsets.zero,
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  leading: CircleAvatar(
                                    backgroundColor: isDarkMode
                                        ? Colors.blueAccent.withAlpha(30)
                                        : const Color(
                                            0xFFE3F2FD), // Light gray-blue
                                    child: const Icon(Icons.science,
                                        color: Colors.blueAccent),
                                  ),
                                  title: Text(
                                    stationName,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: isDarkMode
                                          ? Colors.white
                                          : const Color(0xFF212121),
                                      fontSize: 16,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Text(
                                        'Última sincronización',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isDarkMode
                                              ? Colors.grey.shade400
                                              : theme.hintColor,
                                        ),
                                      ),
                                      Text(
                                        point['last_sync_date'],
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: isDarkMode
                                              ? Colors.grey.shade300
                                              : const Color(0xFF757575),
                                        ),
                                      ),
                                    ],
                                  ),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${point['count']}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                          color: isDarkMode
                                              ? Colors.blueAccent
                                              : theme.primaryColor,
                                        ),
                                      ),
                                      Text(
                                        'muestras',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: isDarkMode
                                              ? Colors.blueAccent.withOpacity(0.8)
                                              : Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                  onTap: () {},
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
}
