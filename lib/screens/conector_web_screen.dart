import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../models/models.dart';
import '../services/api_service.dart';
import '../widgets/app_drawer.dart';

class ConectorWebScreen extends StatefulWidget {
  const ConectorWebScreen({super.key});

  @override
  State<ConectorWebScreen> createState() => _ConectorWebScreenState();
}

class _ConectorWebScreenState extends State<ConectorWebScreen> {
  final ApiService _apiService = ApiService();
  final DatabaseHelper _dbHelper = DatabaseHelper();

  bool _isLoading = false;
  String _syncStatusMessage = '';
  String _muestrasStatusMessage = '';

  // Form State
  List<Program> _programs = [];
  List<Station> _stations = [];
  Program? _selectedProgram;
  final Set<Station> _selectedStations = {};
  bool _isAllStationsChecked = false;

  // UI State for Custom Dropdowns
  bool _expandPrograma = false;
  bool _expandEstaciones = false;
  final TextEditingController _searchProgramaController = TextEditingController();
  final TextEditingController _searchEstacionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadPrograms();
  }

  @override
  void dispose() {
    _searchProgramaController.dispose();
    _searchEstacionController.dispose();
    super.dispose();
  }

  Future<void> _loadPrograms() async {
    final programs = await _dbHelper.getPrograms();
    setState(() {
      _programs = programs;
    });
  }

  Future<void> _syncData() async {
    setState(() {
      _isLoading = true;
      _syncStatusMessage = 'Conectando al servidor...';
    });
    try {
      final data = await _apiService.fetchAllData();
      setState(() => _syncStatusMessage = 'Descargando programas e información...');
      
      await _dbHelper.syncData(data);
      setState(() => _syncStatusMessage = 'Guardando en base de datos local...');
      
      await _loadPrograms();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Datos sincronizados correctamente')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error de conexión: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _onProgramChanged(Program program) async {
    setState(() {
      _selectedProgram = program;
      _selectedStations.clear();
      _stations = [];
      _expandPrograma = false;
    });

    final stations = await _dbHelper.getStationsByProgram(program.id);
    setState(() {
      _stations = stations;
    });
  }

  Future<void> _onGetDataPressed() async {
    if (_selectedProgram == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor seleccione un programa')),
      );
      return;
    }

    if (!_isAllStationsChecked && _selectedStations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor seleccione al menos una estación o marque "Todas las estaciones"')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      
      // Dynamic Loading Text Logic
      List<String> selectedNames = [];
      if (_isAllStationsChecked) {
        selectedNames = ["todas las estaciones"];
      } else {
        selectedNames = _selectedStations.map((s) => s.name).toList();
      }

      String loadingText = 'Descargando datos...';
      if (selectedNames.length == 1) {
        loadingText = 'Se están obteniendo datos de ${selectedNames[0]}...';
      } else if (selectedNames.length == 2) {
        loadingText = 'Descargando ${selectedNames[0]} y ${selectedNames[1]}...';
      } else if (selectedNames.length > 2) {
        loadingText = 'Descargando ${selectedNames[0]}, ${selectedNames[1]} y ${selectedNames.length - 2} más...';
      }
      _muestrasStatusMessage = loadingText;
    });

    try {
      // 1. Prepare stations list
      List<String> estacionesList;
      if (_isAllStationsChecked) {
        estacionesList = await _dbHelper.getEstacionesNombresByPrograma(_selectedProgram!.id);
      } else {
        estacionesList = _selectedStations.map((s) => s.name).toList();
      }

      int totalSincronizados = 0;

      // 2. Loop through stations for real-time progress
      for (int i = 0; i < estacionesList.length; i++) {
        final stationName = estacionesList[i];
        
        setState(() {
          _muestrasStatusMessage = 'Descargando datos de $stationName...\n(Estación ${i + 1} de ${estacionesList.length})';
        });

        // Fetch data for this specific station
        final dynamic decodedJson = await _apiService.fetchHistorialMuestras(
          _selectedProgram!.id.toString(),
          [stationName],
        );

        // Robust Parsing (existing logic adapted for single station results)
        List<dynamic> apiRecords = [];
        if (decodedJson is List) {
          apiRecords = decodedJson;
        } else if (decodedJson is Map<String, dynamic>) {
          if (decodedJson.containsKey('data') && decodedJson['data'] is List) {
            apiRecords = decodedJson['data'];
          } else if (decodedJson.containsKey('muestras') && decodedJson['muestras'] is List) {
            apiRecords = decodedJson['muestras'];
          } else {
            apiRecords = [decodedJson];
          }
        }

        final List<Map<String, dynamic>> parsedData = _apiService.transformToLongFormat(apiRecords);
        
        // Save incrementally
        await _dbHelper.syncHistoricalData(parsedData);
        totalSincronizados += parsedData.length;

        // Small delay to allow the user to read the message if the API is fast
        await Future.delayed(const Duration(milliseconds: 300));
      }

      setState(() {
        _muestrasStatusMessage = '¡Sincronización finalizada con éxito!';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Se sincronizaron $totalSincronizados mediciones históricas')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al obtener datos: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Sincronizar'),
            actions: [
              IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: () {},
              ),
            ],
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            labelStyle: TextStyle(fontWeight: FontWeight.bold),
            tabs: [
              Tab(text: 'PROGRAMAS'),
              Tab(text: 'MUESTRAS'),
            ],
          ),
          ),
          drawer: const AppDrawer(currentRoute: '/conector_web'),
          body: TabBarView(
            children: [
              _buildProgramasTab(),
              _buildMuestrasTab(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgramasTab() {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.map_outlined,
              size: 80,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Actualizar Programas',
            style: TextStyle(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 40),
          if (_isLoading) ...[
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              _syncStatusMessage,
              style: TextStyle(color: theme.colorScheme.primary, fontSize: 13, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ] else
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: LinearGradient(
                  colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
                ),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _syncData,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 16),
                ),
                child: const Text(
                  'ACTUALIZAR',
                  style: TextStyle(fontSize: 16, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMuestrasTab() {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Column(
              children: [
                Icon(Icons.cloud_download_outlined, color: theme.colorScheme.secondary, size: 50),
                const SizedBox(height: 10),
                Text(
                  "Actualizar muestras", 
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          Card(
            elevation: isDarkMode ? 0 : 3,
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  // Custom Program Dropdown
                  ListTile(
                    title: Row(
                      children: [
                        const Text("Programa", style: TextStyle(fontWeight: FontWeight.bold)),
                        const Spacer(),
                        Expanded(
                          child: Text(
                            _selectedProgram?.name ?? "Seleccione",
                            style: TextStyle(color: _selectedProgram == null ? Colors.grey : null),
                            textAlign: TextAlign.end,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    trailing: Icon(
                      _expandPrograma ? Icons.expand_less : Icons.expand_more,
                      color: isDarkMode ? Colors.white70 : Colors.blueAccent,
                    ),
                    onTap: () => setState(() => _expandPrograma = !_expandPrograma),
                  ),
                  if (_expandPrograma) ...[
                    _buildBuscador(_searchProgramaController, "Buscar programa..."),
                    SizedBox(
                      height: 200,
                      child: ListView.builder(
                        itemCount: _programs.length,
                        itemBuilder: (context, index) {
                          final program = _programs[index];
                          if (_searchProgramaController.text.isNotEmpty &&
                              !program.name.toLowerCase().contains(_searchProgramaController.text.toLowerCase())) {
                            return Container();
                          }
                          final isSelected = _selectedProgram == program;
                          return ListTile(
                            onTap: () => _onProgramChanged(program),
                            selected: isSelected,
                            selectedTileColor: theme.brightness == Brightness.dark
                                ? Colors.blueGrey[800]
                                : Colors.grey[200],
                            leading: Icon(
                              isSelected ? Icons.check_circle : Icons.circle_outlined,
                              color: isSelected ? theme.primaryColor : (theme.brightness == Brightness.dark ? Colors.white54 : Colors.grey),
                            ),
                            title: Text(
                              program.name,
                              style: TextStyle(
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected 
                                    ? (theme.brightness == Brightness.dark ? Colors.white : theme.primaryColor)
                                    : null,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],

                  const Divider(),

                  // Custom Station Dropdown
                  ListTile(
                    title: Row(
                      children: [
                        const Text("Estaciones", style: TextStyle(fontWeight: FontWeight.bold)),
                        const Spacer(),
                        Text(
                          _isAllStationsChecked ? "Todas" : "(${_selectedStations.length})",
                          style: TextStyle(
                            color: _selectedStations.isEmpty && !_isAllStationsChecked ? Colors.grey : null,
                          ),
                        ),
                      ],
                    ),
                    trailing: Icon(
                      _expandEstaciones ? Icons.expand_less : Icons.expand_more,
                      color: isDarkMode ? Colors.white70 : Colors.blueAccent,
                    ),
                    onTap: _selectedProgram == null || _isAllStationsChecked
                        ? null
                        : () => setState(() => _expandEstaciones = !_expandEstaciones),
                  ),
                  if (_expandEstaciones && !_isAllStationsChecked) ...[
                    _buildBuscador(_searchEstacionController, "Buscar estación..."),
                    SizedBox(
                      height: 200,
                      child: ListView.builder(
                        itemCount: _stations.length,
                        itemBuilder: (context, index) {
                          final station = _stations[index];
                          if (_searchEstacionController.text.isNotEmpty &&
                              !station.name.toLowerCase().contains(_searchEstacionController.text.toLowerCase())) {
                            return Container();
                          }
                          final isSelected = _selectedStations.contains(station);
                          return ListTile(
                            onTap: () {
                              setState(() {
                                if (isSelected) {
                                  _selectedStations.remove(station);
                                } else {
                                  _selectedStations.add(station);
                                }
                              });
                            },
                            selected: isSelected,
                            selectedTileColor: theme.brightness == Brightness.dark
                                ? Colors.blueGrey[800]
                                : Colors.grey[200],
                            leading: Icon(
                              isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                              color: isSelected ? theme.primaryColor : (theme.brightness == Brightness.dark ? Colors.white54 : Colors.grey),
                            ),
                            title: Text(
                              station.name,
                              style: TextStyle(
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected 
                                    ? (theme.brightness == Brightness.dark ? Colors.white : theme.primaryColor)
                                    : null,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],

                  const Divider(),

                  // Todas las estaciones Checkbox
                  CheckboxListTile(
                    title: const Text("Todas las estaciones", style: TextStyle(fontWeight: FontWeight.bold)),
                    value: _isAllStationsChecked,
                    activeColor: theme.primaryColor,
                    onChanged: (val) {
                      setState(() {
                        _isAllStationsChecked = val ?? false;
                        if (_isAllStationsChecked) {
                          _selectedStations.clear();
                          _expandEstaciones = false;
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 50),
          if (_isLoading) ...[
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 16),
            Text(
              _muestrasStatusMessage,
              style: TextStyle(color: theme.colorScheme.secondary, fontSize: 13, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
          ] else
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: LinearGradient(
                  colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
                ),
                boxShadow: [
                  BoxShadow(
                    color: theme.colorScheme.primary.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: _onGetDataPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('OBTENER DATOS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBuscador(TextEditingController controller, String hint) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onChanged: (val) => setState(() {}),
      ),
    );
  }
}