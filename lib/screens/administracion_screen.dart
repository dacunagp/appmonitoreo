import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/app_drawer.dart';
import '../utils/security_utils.dart';

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
  List<Map<String, dynamic>> _equipos = [];
  List<TipoEquipo> _tiposEquipo = [];
  List<Parametro> _parametros = [];
  List<Map<String, dynamic>> _endpoints = [];
  String _searchQuery = '';
  int? _selectedProgramaFilter;

  // Fase 109: Reserved Keys for Internal Use (Fixed Columns in Monitoreos Table)
  static const List<String> _reservedKeys = [
    'ph', 'temperatura', 'conductividad', 'oxigeno', 
    'turbiedad', 'profundidad', 'nivel', 'caudal', 'latitud', 'longitud'
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _searchQuery = '';
        });
      }
    });
    _loadAllData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    if (args != null && args.containsKey('initialTab')) {
      final int initialIndex = args['initialTab'];
      if (_tabController.index != initialIndex) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _tabController.animateTo(initialIndex);
            // Clear arguments once used to prevent re-triggering on rebuild
            ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>?; // Just a dummy read
          }
        });
      }
    }
  }


  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      // 0. Perform Category Sync/Migration (Phase 102.1)
      await _dbHelper.migrateCategories();
      
      final usuarios = await _dbHelper.getUsuarios();
      final metodos = await _dbHelper.getMetodos();
      final matrices = await _dbHelper.getMatrices();
      final programas = await _dbHelper.getPrograms(); 
      final estaciones = await _dbHelper.getStationsWithPrograms();
      
      final equipos = await _dbHelper.getAllEquiposWithTipo();
      final tiposEquipo = await _dbHelper.getTiposEquipo();
      final parametros = await _dbHelper.getParametros();
      final endpoints = await _dbHelper.getEndpoints();

      setState(() {
        _usuarios = usuarios;
        _metodos = metodos;
        _matrices = matrices;
        _programas = programas;
        _estacionesConPrograma = estaciones;
        _equipos = equipos; 
        _tiposEquipo = tiposEquipo; 
        _parametros = parametros;
        _endpoints = endpoints;
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
      await _apiService.fetchAllData();
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

  void _showFormDialog({dynamic item, required String type}) {
    final bool isEdit = item != null;
    final TextEditingController c1 = TextEditingController();
    final TextEditingController c2 = TextEditingController();
    final TextEditingController c3 = TextEditingController(); 
    final TextEditingController _claveController = TextEditingController();
    final TextEditingController _unidadController = TextEditingController();
    final TextEditingController _minController = TextEditingController();
    final TextEditingController _maxController = TextEditingController();
    
    // Fase 109: Auto-generation logic for claveInterna + Phase 117: Unit Suggestion
    if (type == 'Parámetro' && !isEdit) {
      c1.addListener(() {
        final name = c1.text;
        _claveController.text = _normalizeClave(name);
        
        // Phase 117: Suggest units based on name to avoid hardcoding mg/L everywhere
        final lower = name.toLowerCase();
        if (lower.contains('turbiedad')) {
          _unidadController.text = 'NTU';
        } else if (lower.contains('caudal')) {
          _unidadController.text = 'L/s';
        } else if (lower.contains('profundidad') || lower.contains('nivel')) {
          _unidadController.text = 'm';
        } else if (lower == 'ph') {
          _unidadController.text = 'Adim.';
        }
      });
    }

    int? selectedProgramId;
    int? selectedTipoId;

    String? selectedCategoria;
    final List<String> categories = ['Datos de Monitoreo', 'Nivel Freático', 'Multiparámetro', 'Turbiedad', 'Parámetros Adicionales'];

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
      } else if (type == 'Equipo') {
        c1.text = item['codigo'];
        selectedTipoId = item['id_form_fk'];
      } else if (type == 'Parámetro') {
        final p = item as Parametro;
        c1.text = p.nombreParametro;
        _claveController.text = p.claveInterna;
        _unidadController.text = p.unidad;
        _minController.text = p.min?.toString() ?? '';
        _maxController.text = p.max?.toString() ?? '';
        
        // [NEW] Safety check for legacy or invalid categories
        if (p.categoria != null && categories.contains(p.categoria)) {
          selectedCategoria = p.categoria;
        } else {
          selectedCategoria = null; // Force user to pick a valid one
        }
      } else if (type == 'Endpoint') {
        c1.text = item['nombre'] ?? '';
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
                ] else if (type == 'Equipo') ...[
                  TextField(controller: c1, decoration: const InputDecoration(labelText: 'Código Equipo')),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    value: selectedTipoId,
                    decoration: const InputDecoration(labelText: 'Categoría de Equipo'),
                    items: _tiposEquipo.map((t) => DropdownMenuItem(value: t.idForm, child: Text(t.tipo))).toList(),
                    onChanged: (val) => setDialogState(() => selectedTipoId = val),
                  ),
                ] else if (type == 'Parámetro') ...[
                  TextField(controller: c1, decoration: const InputDecoration(labelText: 'Nombre Parámetro')),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: selectedCategoria,
                    decoration: const InputDecoration(labelText: 'Categoría'),
                    items: categories.map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
                    onChanged: (val) => setDialogState(() => selectedCategoria = val),
                  ),
                  const SizedBox(height: 8),
                  const SizedBox(height: 8),
                  Visibility(
                    visible: true, // Show always in Phase 109 to let user review the auto-gen key
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: _claveController,
                          readOnly: true, // Fase 109: Auto-generated internal key is read-only
                          decoration: InputDecoration(
                            labelText: 'Clave Interna (Auto-generada)',
                            helperText: isEdit ? 'La clave interna no se puede modificar' : 'Se genera automáticamente del nombre',
                            filled: true,
                            fillColor: Theme.of(context).brightness == Brightness.dark ? Colors.black12 : Colors.grey.shade100,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                  TextField(controller: _unidadController, decoration: const InputDecoration(labelText: 'Unidad')),
                  if (item == null || (item is Parametro && item.claveInterna.toLowerCase() == 'ph')) ...[
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _minController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Mínimo'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _maxController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Máximo'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ] else if (type == 'Endpoint') ...[
                  TextField(controller: c1, decoration: const InputDecoration(labelText: 'Nombre del Endpoint')),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
            ElevatedButton(
              onPressed: () async {
                // Validación de campos vacíos
                if (type == 'Usuario') {
                  if (c1.text.trim().isEmpty || c2.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Por favor, rellene todos los campos (Nombre y Apellido).'), backgroundColor: Colors.redAccent),
                    );
                    return;
                  }
                } else if (type == 'Método' || type == 'Matriz' || type == 'Programa') {
                  if (c1.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Por favor, ingrese el nombre del registro.'), backgroundColor: Colors.redAccent),
                    );
                    return;
                  }
                } else if (type == 'Parámetro') {
                  if (c1.text.trim().isEmpty || _claveController.text.trim().isEmpty || _unidadController.text.trim().isEmpty || selectedCategoria == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Por favor, rellene todos los campos, incluyendo la Categoría.'), backgroundColor: Colors.redAccent),
                    );
                    return;
                  }

                  final newClave = _claveController.text.trim().toLowerCase();

                  // 1. Check against Reserved System Keys (Phase 109)
                  if (_reservedKeys.contains(newClave)) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('El nombre base "$newClave" está reservado por el sistema. Intente agregar un número o sufijo (ej: ${c1.text} 2).'),
                        backgroundColor: Colors.redAccent,
                        duration: const Duration(seconds: 4),
                      ),
                    );
                    return;
                  }

                  // 2. Check against Existing Parameters (excluding itself if editing)
                  final bool isDuplicate = _parametros.any((p) {
                    if (isEdit && p.idParametro == (item as Parametro).idParametro) return false;
                    return p.claveInterna.toLowerCase() == newClave;
                  });

                  if (isDuplicate) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Ya existe un parámetro con una clave interna similar. Use un nombre más específico.'),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                    return;
                  }
                }

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
                  } else if (type == 'Equipo') {
                    final e = {
                      'id': isEdit ? item['id'] : DateTime.now().millisecondsSinceEpoch % 10000,
                      'codigo': c1.text,
                      'id_form_fk': selectedTipoId ?? 0,
                      'tipo': selectedTipoId != null 
                              ? _tiposEquipo.firstWhere((t) => t.idForm == selectedTipoId, orElse: () => TipoEquipo(idForm: 0, tipo: 'General')).tipo 
                              : 'General',
                    };
                    isEdit ? await _dbHelper.updateEquipo(e) : await _dbHelper.addEquipo(e);
                  } else if (type == 'Parámetro') {
                    final p = Parametro(
                      idParametro: isEdit
                          ? (item as Parametro).idParametro
                          : DateTime.now().millisecondsSinceEpoch % 10000,
                      nombreParametro: c1.text.trim(),
                      claveInterna: _claveController.text.trim(),
                      unidad: _unidadController.text.trim(),
                      min: double.tryParse(_minController.text.trim()),
                      max: double.tryParse(_maxController.text.trim()),
                      categoria: selectedCategoria,
                    );
                    isEdit ? await _dbHelper.updateParametro(p) : await _dbHelper.addParametro(p);
                  } else if (type == 'Endpoint') {
                    final name = c1.text.trim();
                    if (name.isEmpty) throw Exception('El nombre no puede estar vacío');
                    isEdit ? await _dbHelper.updateEndpoint(item['id'], name) : await _dbHelper.addEndpoint(name);
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

  void _confirmDelete(int id, String type) async {
    final authorized = await SecurityUtils.requirePin(context);
    if (!authorized) return;

    if (!mounted) return;
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
              else if (type == 'Equipo') await _dbHelper.deleteEquipo(id);
              else if (type == 'Parámetro') await _dbHelper.deleteParametro(id);
              else if (type == 'Endpoint') await _dbHelper.deleteEndpoint(id);
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
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold),
            tabs: const [
              Tab(text: 'Métodos'),
              Tab(text: 'Matrices'),
              Tab(text: 'Programas'),
              Tab(text: 'Equipos'),
              Tab(text: 'Parámetros'),
            ],
          ),
        ),
        drawer: const AppDrawer(currentRoute: '/administracion'),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildTabList(_metodos, 'Método'),
                  _buildTabList(_matrices, 'Matriz'),
                  _buildTabList(_programas, 'Programa'),
                  _buildEquiposTab(),
                  _buildTabList(_parametros, 'Parámetro'),
                ],
              ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            final types = ['Método', 'Matriz', 'Programa', 'Equipo', 'Parámetro'];
            _showFormDialog(type: types[_tabController.index]);
          },
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildTabList(List<dynamic> items, String type) {
    if (items.isEmpty) return const Center(child: Text('Sin datos'));

    final filteredItems = items.where((item) {
      if (_searchQuery.isEmpty) return true;
      String searchField = '';
      if (type == 'Usuario') {
        searchField = '${item.nombre} ${item.apellido}';
      } else if (type == 'Método') {
        searchField = item.metodo;
      } else if (type == 'Matriz') {
        searchField = item.nombreMatriz;
      } else if (type == 'Programa') {
        searchField = item.name;
      } else if (type == 'Parámetro') {
        searchField = item.nombreParametro;
      } else if (type == 'Endpoint') {
        searchField = item['nombre'] ?? '';
      }
      return searchField.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();

    return Column(
      children: [
        if (items.length > 11)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Buscar...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: filteredItems.length,
            itemBuilder: (context, index) {
              final item = filteredItems[index];
              String title = '';
              String subtitle = '';
              int id = 0;

              if (type == 'Usuario') {
                title = '${item.nombre} ${item.apellido}';
                subtitle = ''; 
                id = item.idUsuario;
              } else if (type == 'Método') {
                title = item.metodo;
                subtitle = ''; 
                id = item.idMetodo;
              } else if (type == 'Matriz') {
                title = item.nombreMatriz;
                subtitle = ''; 
                id = item.idMatriz;
              } else if (type == 'Programa') {
                title = item.name;
                subtitle = ''; 
                id = item.id;
              } else if (type == 'Parámetro') {
                title = item.nombreParametro;
                subtitle = '${item.categoria ?? 'Sin Categoría'} [${item.unidad}]';
                id = item.idParametro;
              } else if (type == 'Endpoint') {
                title = item['nombre'] ?? 'S/N';
                subtitle = '';
                id = item['id'];
              }

              return ListTile(
                title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.left),
                subtitle: subtitle.isNotEmpty ? Text(subtitle, textAlign: TextAlign.left) : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (type == 'Parámetro')
                      Switch(
                        value: (item as Parametro).activo == 1,
                        activeColor: Colors.greenAccent,
                        onChanged: (bool value) async {
                          await _dbHelper.toggleParametroStatus(id, value);
                          setState(() {
                            item.activo = value ? 1 : 0;
                          });
                        },
                      ),
                    IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () {
                          _showFormDialog(item: item, type: type);
                        }),
                    IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _confirmDelete(id, type)),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStationsTab() {
    if (_estacionesConPrograma.isEmpty) return const Center(child: Text('Sin datos'));

    final filteredItems = _estacionesConPrograma.where((item) {
      bool matchesSearch = true;
      if (_searchQuery.isNotEmpty) {
        final name = (item['name'] ?? '').toString().toLowerCase();
        matchesSearch = name.contains(_searchQuery.toLowerCase());
      }
      
      bool matchesProgram = true;
      if (_selectedProgramaFilter != null) {
        matchesProgram = item['program_id'] == _selectedProgramaFilter;
      }
      
      return matchesSearch && matchesProgram;
    }).toList();

    return Column(
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
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: DropdownButtonFormField<int?>(
                  isExpanded: true,
                  value: _selectedProgramaFilter,
                  decoration: const InputDecoration(
                    labelText: 'Programa',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text("Todos")),
                    ..._programas.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (val) {
                    setState(() {
                      _selectedProgramaFilter = val;
                    });
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: filteredItems.length,
            itemBuilder: (context, index) {
              final item = filteredItems[index];
              return ListTile(
                title: Text(item['name']),
                subtitle: Text('Programa: ${item['program_name'] ?? 'N/A'}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () =>
                            _showFormDialog(item: item, type: 'Estación')),
                    IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _confirmDelete(item['id'], 'Estación')),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEquiposTab() {
    if (_equipos.isEmpty) return const Center(child: Text('Sin datos'));

    final filteredItems = _equipos.where((item) {
      if (_searchQuery.isEmpty) return true;
      final codigo = (item['codigo'] ?? '').toString().toLowerCase();
      return codigo.contains(_searchQuery.toLowerCase());
    }).toList();

    return Column(
      children: [
        if (_equipos.length > 11)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Buscar...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: filteredItems.length,
            itemBuilder: (context, index) {
              final item = filteredItems[index];
              return ListTile(
                title: Text(item['codigo'] ?? 'Sin código'),
                subtitle: Text('Tipo: ${item['tipo'] ?? 'N/A'}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _showFormDialog(item: item, type: 'Equipo')),
                    IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _confirmDelete(item['id'], 'Equipo')),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _getUbicacionParametro(String nombre) {
    final lowerName = nombre.toLowerCase();
    if (lowerName.contains('temperatura') || 
        lowerName.contains('ph') || 
        lowerName.contains('conductividad') || 
        lowerName.contains('oxigeno')) {
      return 'Registrar Monitoreo - Multiparámetro';
    } else if (lowerName.contains('turbiedad')) {
      return 'Registrar Monitoreo - Turbiedad';
    } else if (lowerName.contains('nivel')) {
      return 'Registrar Monitoreo - Nivel Freático';
    } else if (lowerName.contains('profundidad')) {
      return 'Registrar Monitoreo - Datos de Monitoreo';
    }
    // Fallback for parameters not currently mapped in the UI (e.g., Uranio, Caudal)
    return 'Registrar Monitoreo - Parámetros Adicionales';
  }

  // --- FASE 109: HELPER PARA NORMALIZAR CLAVE INTERNA ---
  String _normalizeClave(String name) {
    String normalized = name.toLowerCase().trim();
    
    // Replace accents/diacritics
    normalized = normalized.replaceAll(RegExp(r'[áàäâ]'), 'a');
    normalized = normalized.replaceAll(RegExp(r'[éèëê]'), 'e');
    normalized = normalized.replaceAll(RegExp(r'[íìïî]'), 'i');
    normalized = normalized.replaceAll(RegExp(r'[óòöô]'), 'o');
    normalized = normalized.replaceAll(RegExp(r'[úùüû]'), 'u');
    normalized = normalized.replaceAll(RegExp(r'[ñ]'), 'n');

    // Replace spaces and special chars with underscores
    normalized = normalized.replaceAll(RegExp(r'[^a-z0-9]'), '_');
    
    // Remove multiple consecutive underscores
    normalized = normalized.replaceAll(RegExp(r'_+'), '_');
    
    // Remove leading/trailing underscores
    normalized = normalized.replaceAll(RegExp(r'^_+|_+$'), '');

    return normalized;
  }
}