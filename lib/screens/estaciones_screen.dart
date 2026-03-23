import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/models.dart';
import '../widgets/app_drawer.dart';
import '../services/api_service.dart';

class EstacionesScreen extends StatefulWidget {
  const EstacionesScreen({super.key});

  @override
  State<EstacionesScreen> createState() => _EstacionesScreenState();
}

class _EstacionesScreenState extends State<EstacionesScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  bool _isLoading = true;
  List<Map<String, dynamic>> _estaciones = [];
  List<Program> _programas = [];
  String _searchQuery = '';
  int? _selectedProgramFilter;

  String _loadingMessage = 'Iniciando...';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final estaciones = await _dbHelper.getStationsWithPrograms();
      final programas = await _dbHelper.getPrograms();
      setState(() {
        _estaciones = estaciones;
        _programas = programas;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar datos: $e')),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshData() async {
    setState(() {
      _isLoading = true;
      _loadingMessage = 'Iniciando sincronización...';
    });
    
    try {
      final ApiService apiService = ApiService();
      setState(() => _loadingMessage = 'Conectando con el servidor...');
      final data = await apiService.fetchAllData();
      
      setState(() => _loadingMessage = 'Sincronizando programas y estaciones...');
      await _dbHelper.syncData(data);
      
      setState(() => _loadingMessage = 'Actualizando datos locales...');
      await _loadData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sincronización completada exitosamente.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error al actualizar la información.'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showFormDialog({Map<String, dynamic>? station}) {
    final bool isEdit = station != null;
    final TextEditingController c1 = TextEditingController(text: isEdit ? station['name'] : '');
    final TextEditingController c2 = TextEditingController(text: isEdit ? station['latitude'].toString() : '0.0');
    final TextEditingController c3 = TextEditingController(text: isEdit ? station['longitude'].toString() : '0.0');
    int? selectedProgramId = isEdit ? station['program_id'] : null;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${isEdit ? 'Editar' : 'Crear'} Estación'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: c1, decoration: const InputDecoration(labelText: 'Nombre')),
                TextField(controller: c2, decoration: const InputDecoration(labelText: 'Latitud'), keyboardType: TextInputType.number),
                TextField(controller: c3, decoration: const InputDecoration(labelText: 'Longitud'), keyboardType: TextInputType.number),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  value: selectedProgramId,
                  decoration: const InputDecoration(labelText: 'Asignar a Programa'),
                  items: _programas.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))).toList(),
                  onChanged: (val) => setDialogState(() => selectedProgramId = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
            ElevatedButton(
              onPressed: () async {
                if (c1.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Por favor, ingrese un nombre.'), backgroundColor: Colors.redAccent),
                  );
                  return;
                }
                if (!isEdit && selectedProgramId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Debe seleccionar un programa.'), backgroundColor: Colors.redAccent),
                  );
                  return;
                }

                try {
                  final s = Station(
                    id: isEdit ? station['id'] : DateTime.now().millisecondsSinceEpoch % 10000,
                    name: c1.text.trim(),
                    latitude: double.tryParse(c2.text) ?? 0.0,
                    longitude: double.tryParse(c3.text) ?? 0.0,
                  );

                  if (isEdit) {
                    await _dbHelper.updateStation(s);
                  } else {
                    await _dbHelper.addStation(s, selectedProgramId!);
                  }

                  if (mounted) Navigator.pop(context);
                  _loadData();
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              },
              child: const Text('GUARDAR'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(int id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Eliminación'),
        content: const Text('¿Está seguro de que desea eliminar esta estación?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
          TextButton(
            onPressed: () async {
              await _dbHelper.deleteStation(id);
              if (mounted) Navigator.pop(context);
              _loadData();
            },
            child: const Text('ELIMINAR', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredStations = _estaciones.where((item) {
      bool matchesSearch = true;
      if (_searchQuery.isNotEmpty) {
        final name = (item['name'] ?? '').toString().toLowerCase();
        matchesSearch = name.contains(_searchQuery.toLowerCase());
      }
      bool matchesProgram = true;
      if (_selectedProgramFilter != null) {
        matchesProgram = item['program_id'] == _selectedProgramFilter;
      }
      return matchesSearch && matchesProgram;
    }).toList();

    return PopScope(
      canPop: false,
      onPopInvoked: (bool didPop) {
        if (didPop) return;
        if (context.mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/monitoreos',
            (route) => false,
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Estaciones'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _refreshData(),
            ),
          ],
        ),
        drawer: const AppDrawer(currentRoute: '/estaciones'),
        body: _isLoading
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    Text(
                      _loadingMessage,
                      style: const TextStyle(fontSize: 16, color: Colors.blue),
                    ),
                  ],
                ),
              )
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            decoration: const InputDecoration(
                              hintText: 'Buscar...',
                              prefixIcon: Icon(Icons.search),
                              isDense: true,
                            ),
                            onChanged: (value) => setState(() => _searchQuery = value),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 1,
                          child: DropdownButtonFormField<int?>(
                            isExpanded: true,
                            value: _selectedProgramFilter,
                            decoration: const InputDecoration(
                              labelText: 'Programa',
                              isDense: true,
                            ),
                            items: [
                              const DropdownMenuItem(value: null, child: Text("Todos")),
                              ..._programas.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis))),
                            ],
                            onChanged: (val) => setState(() => _selectedProgramFilter = val),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: filteredStations.isEmpty
                        ? const Center(child: Text('Sin estaciones guardadas'))
                        : ListView.builder(
                            itemCount: filteredStations.length,
                            itemBuilder: (context, index) {
                              final station = filteredStations[index];
                              return ListTile(
                                leading: const CircleAvatar(child: Icon(Icons.location_on)),
                                title: Text(station['name']),
                                subtitle: Text('Programa: ${station['program_name'] ?? 'N/A'}'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit, color: Colors.blue),
                                      onPressed: () => _showFormDialog(station: station),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () => _confirmDelete(station['id']),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showFormDialog(),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}