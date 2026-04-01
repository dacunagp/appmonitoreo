import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/app_drawer.dart';

class UsuariosScreen extends StatefulWidget {
  const UsuariosScreen({super.key});

  @override
  State<UsuariosScreen> createState() => _UsuariosScreenState();
}

class _UsuariosScreenState extends State<UsuariosScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  bool _isLoading = true;
  List<Usuario> _usuarios = [];
  String _searchQuery = '';

  String _loadingMessage = 'Iniciando...';

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers({bool showMessage = false}) async {
    setState(() => _isLoading = true);
    try {
      final usuarios = await _dbHelper.getUsuarios();
      setState(() {
        _usuarios = usuarios;
        _isLoading = false;
      });
      if (showMessage && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lista de usuarios actualizada')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar usuarios: $e')),
        );
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _syncAndLoadUsers() async {
    setState(() {
      _isLoading = true;
      _loadingMessage = 'Iniciando sincronización...';
    });
    
    try {
      final ApiService apiService = ApiService();
      
      setState(() => _loadingMessage = 'Conectando con el servidor...');
      
      // Usar el método unificado que ya maneja las listas de FastAPI
      await apiService.fetchAllData();
      
      setState(() => _loadingMessage = 'Actualizando lista de usuarios...');
      await _loadUsers(showMessage: false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sincronización completada exitosamente.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showFormDialog({Usuario? user}) {
    final bool isEdit = user != null;
    final TextEditingController c1 = TextEditingController(text: isEdit ? user.nombre : '');
    final TextEditingController c2 = TextEditingController(text: isEdit ? user.apellido : '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${isEdit ? 'Editar' : 'Crear'} Usuario'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: c1, decoration: const InputDecoration(labelText: 'Nombre')),
            TextField(controller: c2, decoration: const InputDecoration(labelText: 'Apellido')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
          ElevatedButton(
            onPressed: () async {
              if (c1.text.trim().isEmpty || c2.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Por favor, rellene todos los campos.'), backgroundColor: Colors.redAccent),
                );
                return;
              }

              try {
                final u = Usuario(
                  idUsuario: isEdit ? user.idUsuario : DateTime.now().millisecondsSinceEpoch % 10000,
                  nombre: c1.text.trim(),
                  apellido: c2.text.trim(),
                );
                isEdit ? await _dbHelper.updateUsuario(u) : await _dbHelper.addUsuario(u);
                if (mounted) Navigator.pop(context);
                _loadUsers();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            },
            child: const Text('GUARDAR'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(int id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar Eliminación'),
        content: const Text('¿Está seguro de que desea eliminar este usuario?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
          TextButton(
            onPressed: () async {
              await _dbHelper.deleteUsuario(id);
              if (mounted) Navigator.pop(context);
              _loadUsers();
            },
            child: const Text('ELIMINAR', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredUsers = _usuarios.where((u) {
      if (_searchQuery.isEmpty) return true;
      final full = '${u.nombre} ${u.apellido}'.toLowerCase();
      return full.contains(_searchQuery.toLowerCase());
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
        title: const Text('Usuarios'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refrescar',
            onPressed: () => _syncAndLoadUsers(),
          ),
        ],
      ),
      drawer: const AppDrawer(currentRoute: '/usuarios'),
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
                if (_usuarios.length > 5)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'Buscar...',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) => setState(() => _searchQuery = value),
                    ),
                  ),
                Expanded(
                  child: filteredUsers.isEmpty
                      ? const Center(child: Text('Sin usuarios'))
                      : ListView.builder(
                        itemCount: filteredUsers.length,
                        itemBuilder: (context, index) {
                          final user = filteredUsers[index];
                          return ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.person)),
                            title: Text('${user.nombre} ${user.apellido}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.blue),
                                  onPressed: () => _showFormDialog(user: user),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => _confirmDelete(user.idUsuario),
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
