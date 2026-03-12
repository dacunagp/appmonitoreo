import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/app_drawer.dart';

class AdministracionScreen extends StatefulWidget {
  const AdministracionScreen({super.key});

  @override
  State<AdministracionScreen> createState() => _AdministracionScreenState();
}

class _AdministracionScreenState extends State<AdministracionScreen> with SingleTickerProviderStateMixin {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final ApiService _apiService = ApiService();
  late TabController _tabController;
  bool _isLoading = true;
  bool _isSyncing = false;

  List<Usuario> _usuarios = [];
  List<Metodo> _metodos = [];
  List<Matriz> _matrices = [];
  List<Program> _programas = [];
  List<Map<String, dynamic>> _estacionesConPrograma = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      setState(() {}); // For FAB logic
    });
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      final usuarios = await _dbHelper.getUsuarios();
      final metodos = await _dbHelper.getMetodos();
      final matrices = await _dbHelper.getMatrices();
      final programas = await _dbHelper.getPrograms();
      final estaciones = await _dbHelper.getStationsWithPrograms();

      setState(() {
        _usuarios = usuarios;
        _metodos = metodos;
        _matrices = matrices;
        _programas = programas;
        _estacionesConPrograma = estaciones;
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

  Future<void> _handleSync() async {
    setState(() => _isSyncing = true);
    try {
      final data = await _apiService.fetchAllData();
      await _dbHelper.syncData(data);
      await _loadAllData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Datos sincronizados correctamente')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error de sincronización: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  // --- Dialogs ---

  void _showFormDialog({dynamic item, required String type}) {
    final bool isEdit = item != null;
    final TextEditingController c1 = TextEditingController();
    final TextEditingController c2 = TextEditingController();
    final TextEditingController c3 = TextEditingController(); // For lat/long or secondary values
    int? selectedProgramId;

    if (isEdit) {
      if (type == 'Usuario') {
        c1.text = (item as Usuario).nombre;
        c2.text = item.apellido;
      } else if (type == 'Método') {
        c1.text = (item as Metodo).metodo;
      } else if (type == 'Matriz') {
        c1.text = (item as Matriz).nombreMatriz;
      } else if (type == 'Programa') {
        c1.text = (item as Program).name;
      } else if (type == 'Estación') {
        c1.text = item['name'];
        c2.text = item['latitude'].toString();
        c3.text = item['longitude'].toString();
        selectedProgramId = item['program_id'];
      }
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${isEdit ? 'Editar' : 'Crear'} $type'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (type == 'Usuario') ...[
                  TextField(controller: c1, decoration: const InputDecoration(labelText: 'Nombre')),
                  TextField(controller: c2, decoration: const InputDecoration(labelText: 'Apellido')),
                ] else if (type == 'Método') ...[
                  TextField(controller: c1, decoration: const InputDecoration(labelText: 'Método')),
                ] else if (type == 'Matriz') ...[
                  TextField(controller: c1, decoration: const InputDecoration(labelText: 'Nombre Matriz')),
                ] else if (type == 'Programa') ...[
                  TextField(controller: c1, decoration: const InputDecoration(labelText: 'Nombre Programa')),
                ] else if (type == 'Estación') ...[
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
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
            ElevatedButton(
              onPressed: () async {
                try {
                  if (type == 'Usuario') {
                    final u = Usuario(idUsuario: isEdit ? (item as Usuario).idUsuario : DateTime.now().millisecondsSinceEpoch % 10000, nombre: c1.text, apellido: c2.text);
                    isEdit ? await _dbHelper.updateUsuario(u) : await _dbHelper.addUsuario(u);
                  } else if (type == 'Método') {
                    final m = Metodo(idMetodo: isEdit ? (item as Metodo).idMetodo : DateTime.now().millisecondsSinceEpoch % 10000, metodo: c1.text);
                    isEdit ? await _dbHelper.updateMetodo(m) : await _dbHelper.addMetodo(m);
                  } else if (type == 'Matriz') {
                    final m = Matriz(idMatriz: isEdit ? (item as Matriz).idMatriz : DateTime.now().millisecondsSinceEpoch % 10000, nombreMatriz: c1.text);
                    isEdit ? await _dbHelper.updateMatriz(m) : await _dbHelper.addMatriz(m);
                  } else if (type == 'Programa') {
                    final p = Program(id: isEdit ? (item as Program).id : DateTime.now().millisecondsSinceEpoch % 10000, name: c1.text);
                    isEdit ? await _dbHelper.updateProgram(p) : await _dbHelper.addProgram(p);
                  } else if (type == 'Estación') {
                    final s = Station(id: isEdit ? item['id'] : DateTime.now().millisecondsSinceEpoch % 10000, name: c1.text, latitude: double.tryParse(c2.text) ?? 0, longitude: double.tryParse(c3.text) ?? 0);
                    if (isEdit) {
                       await _dbHelper.updateStation(s);
                    } else {
                      if (selectedProgramId == null) throw Exception('Debe seleccionar un programa');
                      await _dbHelper.addStation(s, selectedProgramId!);
                    }
                  }
                  if (mounted) Navigator.pop(context);
                  _loadAllData();
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

  void _confirmDelete(int id, String type) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Eliminación'),
        content: Text('¿Está seguro de que desea eliminar este $type?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
          TextButton(
            onPressed: () async {
              if (type == 'Usuario') await _dbHelper.deleteUsuario(id);
              else if (type == 'Método') await _dbHelper.deleteMetodo(id);
              else if (type == 'Matriz') await _dbHelper.deleteMatriz(id);
              else if (type == 'Programa') await _dbHelper.deleteProgram(id);
              else if (type == 'Estación') await _dbHelper.deleteStation(id);
              if (mounted) Navigator.pop(context);
              _loadAllData();
            },
            child: const Text('ELIMINAR', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administración'),
        actions: [
          if (_isSyncing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))),
            )
          else
            IconButton(
              icon: const Icon(Icons.sync),
              tooltip: 'Sincronizar con Servidor',
              onPressed: _handleSync,
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Usuarios'),
            Tab(text: 'Métodos'),
            Tab(text: 'Matrices'),
            Tab(text: 'Programas'),
            Tab(text: 'Estaciones'),
          ],
        ),
      ),
      drawer: const AppDrawer(currentRoute: '/administracion'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildTabList(_usuarios, 'Usuario'),
                _buildTabList(_metodos, 'Método'),
                _buildTabList(_matrices, 'Matriz'),
                _buildTabList(_programas, 'Programa'),
                _buildStationsTab(),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          final types = ['Usuario', 'Método', 'Matriz', 'Programa', 'Estación'];
          _showFormDialog(type: types[_tabController.index]);
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildTabList(List<dynamic> items, String type) {
    if (items.isEmpty) return const Center(child: Text('Sin datos'));
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        String title = '';
        String subtitle = '';
        int id = 0;

        if (type == 'Usuario') {
          title = '${item.nombre} ${item.apellido}';
          subtitle = 'ID: ${item.idUsuario}';
          id = item.idUsuario;
        } else if (type == 'Método') {
          title = item.metodo;
          subtitle = 'ID: ${item.idMetodo}';
          id = item.idMetodo;
        } else if (type == 'Matriz') {
          title = item.nombreMatriz;
          subtitle = 'ID: ${item.idMatriz}';
          id = item.idMatriz;
        } else if (type == 'Programa') {
          title = item.name;
          subtitle = 'ID: ${item.id}';
          id = item.id;
        }

        return ListTile(
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _showFormDialog(item: item, type: type)),
              IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _confirmDelete(id, type)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStationsTab() {
    if (_estacionesConPrograma.isEmpty) return const Center(child: Text('Sin datos'));
    return ListView.builder(
      itemCount: _estacionesConPrograma.length,
      itemBuilder: (context, index) {
        final item = _estacionesConPrograma[index];
        return ListTile(
          title: Text(item['name']),
          subtitle: Text('Programa: ${item['program_name'] ?? 'N/A'}'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(icon: const Icon(Icons.edit, color: Colors.blue), onPressed: () => _showFormDialog(item: item, type: 'Estación')),
              IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _confirmDelete(item['id'], 'Estación')),
            ],
          ),
        );
      },
    );
  }
}
