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
    setState(() => _isLoading = true);
    try {
      final data = await _apiService.fetchAllData();
      await _dbHelper.syncData(data);
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

  void _onGetDataPressed() {
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

    // Process data logic
    debugPrint('Programa: ${_selectedProgram?.name}');
    debugPrint('Estaciones: ${_isAllStationsChecked ? "Todas" : _selectedStations.map((e) => e.name).toList()}');

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Obteniendo datos...')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
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
    );
  }

  Widget _buildProgramasTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.map_outlined,
            size: 80,
            color: Colors.greenAccent.shade400,
          ),
          const SizedBox(height: 10),
          const Text(
            'Actualizar Programas',
            style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 30),
          if (_isLoading)
            const CircularProgressIndicator()
          else
            OutlinedButton(
              onPressed: _syncData,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.blue),
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
              ),
              child: const Text('ACTUALIZAR'),
            ),
        ],
      ),
    );
  }

  Widget _buildMuestrasTab() {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color containerColor = isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFF3F4F6);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Column(
              children: [
                Icon(Icons.cloud_download_outlined, color: Colors.greenAccent.shade400, size: 50),
                const SizedBox(height: 10),
                const Text("Actualizar muestras", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
          ),
          const SizedBox(height: 30),
          Container(
            decoration: BoxDecoration(
              color: containerColor,
              borderRadius: BorderRadius.circular(4.0),
            ),
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
                  trailing: Icon(_expandPrograma ? Icons.expand_less : Icons.expand_more),
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
                        return InkWell(
                          onTap: () => _onProgramChanged(program),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                            child: Row(
                              children: [
                                Icon(
                                  _selectedProgram == program ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                  color: Colors.blue,
                                ),
                                const SizedBox(width: 10),
                                Expanded(child: Text(program.name)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],

                const Divider(height: 1),

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
                  trailing: Icon(_expandEstaciones ? Icons.expand_less : Icons.expand_more),
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
                        return InkWell(
                          onTap: () {
                            setState(() {
                              if (isSelected) {
                                _selectedStations.remove(station);
                              } else {
                                _selectedStations.add(station);
                              }
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                            child: Row(
                              children: [
                                Icon(
                                  isSelected ? Icons.check_box : Icons.check_box_outline_blank,
                                  color: Colors.blue,
                                ),
                                const SizedBox(width: 10),
                                Expanded(child: Text(station.name)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],

                const Divider(height: 1),

                // Todas las estaciones Checkbox
                InkWell(
                  onTap: () {
                    setState(() {
                      _isAllStationsChecked = !_isAllStationsChecked;
                      if (_isAllStationsChecked) {
                        _selectedStations.clear();
                        _expandEstaciones = false;
                      }
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Icon(
                          _isAllStationsChecked ? Icons.check_box : Icons.check_box_outline_blank,
                          color: Colors.blue,
                        ),
                        const SizedBox(width: 10),
                        const Text("Todas las estaciones", style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 50),
          OutlinedButton(
            onPressed: _onGetDataPressed,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              side: const BorderSide(color: Colors.blue),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('OBTENER DATOS'),
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
