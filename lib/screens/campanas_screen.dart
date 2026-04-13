import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../database/database_helper.dart';
import '../widgets/app_drawer.dart';
import '../models/models.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio_cache_interceptor_file_store/dio_cache_interceptor_file_store.dart';
import 'registrar_monitoreo_screen.dart'; // Phase 121
import 'monitoreos_screen.dart'; // Phase 124

class CampanasScreen extends StatefulWidget {
  const CampanasScreen({super.key});

  @override
  State<CampanasScreen> createState() => _CampanasScreenState();
}

class _CampanasScreenState extends State<CampanasScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final MapController _mapController = MapController();

  List<Program> _programs = [];
  List<Station> _allStations = [];
  List<Station> _filteredStations = [];

  int? _selectedProgramId;
  int? _selectedStationId;
  bool _isLoading = true;
  Map<int, int> _stationStatuses = {};
  String? _cachePath;
  String? _selectedLayerUrl;
  final DraggableScrollableController _sheetController = DraggableScrollableController();

  String get _currentLayerUrl {
    if (_selectedLayerUrl != null) return _selectedLayerUrl!;
    return 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  }

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      debugPrint('🗺️ [Inicio] Cargando datos iniciales...');
      final programs = await _dbHelper.getPrograms();
      final stations = await _dbHelper.getAllStations();
      debugPrint('🗺️ [Inicio] ${programs.length} programas y ${stations.length} estaciones encontradas.');
      
      // Initialize Cache Path for Offline Maps
      final cacheDir = await getApplicationDocumentsDirectory();
      
      // Fetch Sync Statuses
      debugPrint('🗺️ [Inicio] Obteniendo estados de sincronización...');
      final Map<int, int> statuses = {};
      for (var s in stations) {
        statuses[s.id] = await _dbHelper.getStationDetailedMonitoringStatus(s.id);
      }
      
      setState(() {
        _programs = programs;
        _allStations = stations;
        _filteredStations = stations;
        _stationStatuses = statuses;
        _cachePath = '${cacheDir.path}/map_tiles_cache';
        _isLoading = false;
      });
      debugPrint('🗺️ [Inicio] Carga completa. Listos para mostrar el mapa.');
    } catch (e) {
      debugPrint('🛑 [ERROR Inicio]: $e');
      setState(() => _isLoading = false);
    }
  }

  void _onProgramChanged(int? programId) async {
    debugPrint('🔍 [Cambio Programa] ID: $programId Seleccionado.');
    setState(() {
      _selectedProgramId = programId;
      _selectedStationId = null;
      _isLoading = true;
    });
    
    try {
      if (programId == null) {
        debugPrint('🔍 [Cambio Programa] Regresando a "Todos los Programas".');
        final stations = await _dbHelper.getAllStations();
        setState(() {
          _filteredStations = stations;
          _isLoading = false;
        });
      } else {
        debugPrint('🔍 [Cambio Programa] Buscando estaciones para programa ID: $programId');
        final stations = await _dbHelper.getStationsByProgram(programId);
        debugPrint('🔍 [Cambio Programa] ${stations.length} estaciones encontradas.');
        
        // 🚨 DIAGNOSTIC LOOP: Print first 3 stations to verify coordinate integrity
        for (int i = 0; i < stations.length && i < 3; i++) {
          debugPrint('🚨 [COORD-CHECK] Estación ${stations[i].name} -> Lat: ${stations[i].latitude}, Lon: ${stations[i].longitude}');
        }
        
        final Map<int, int> statuses = {};
        for (var s in stations) {
          statuses[s.id] = await _dbHelper.getStationDetailedMonitoringStatus(s.id);
        }
        setState(() {
          _filteredStations = stations;
          _stationStatuses = statuses;
          _isLoading = false;
        });

        if (stations.isNotEmpty) {
          final lat = stations[0].latitude;
          final lon = stations[0].longitude;
          debugPrint('📍 [Cambio Programa] Moviendo mapa a primer estación: ${stations[0].name} ($lat, $lon)');
          _mapController.move(LatLng(lat, lon), 12);
        } else {
          debugPrint('⚠️ [Cambio Programa] El programa no tiene estaciones con coordenadas.');
        }
      }
    } catch (e) {
      debugPrint('🛑 [ERROR Cambio Programa]: $e');
      setState(() => _isLoading = false);
    }
  }

  void _onStationChanged(int? stationId) {
    debugPrint('📌 [Selección Estación] ID: $stationId enfocando...');
    setState(() => _selectedStationId = stationId);
    
    // Collapse bottom sheet if attached (Phase 120.2 Fix)
    if (_sheetController.isAttached) {
      _sheetController.animateTo(
        0.12, 
        duration: const Duration(milliseconds: 300), 
        curve: Curves.easeInOut,
      );
    }

    if (stationId != null) {
      final station = _allStations.firstWhere((s) => s.id == stationId);
      debugPrint('📌 [Selección Estación] Moviendo a ${station.name} (${station.latitude}, ${station.longitude})');
      _mapController.move(
        LatLng(station.latitude, station.longitude),
        15,
      );
    }
  }

  void _showStationDetails(Station station) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final theme = Theme.of(context);
        final isDarkMode = theme.brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.location_on, color: isDarkMode ? theme.colorScheme.primary : Colors.blue, size: 30),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      station.name,
                      style: TextStyle(
                        fontSize: 22, 
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 32),
              _buildDetailRow(Icons.map, 'Coordenadas', '${station.latitude.toStringAsFixed(2)}, ${station.longitude.toStringAsFixed(2)}'),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => MonitoreosScreen(
                          initialStationName: station.name,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.history, color: Colors.blueAccent),
                  label: const Text('VER HISTORIAL DE ESTACIÓN', 
                    style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold)
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.blueAccent, width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    // Close the bottom sheet first
                    Navigator.pop(context);
                    
                    // Navigate to registration with IDs
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => RegistrarMonitoreoScreen(
                          initialProgramId: _selectedProgramId,
                          initialStationId: station.id,
                        ),
                      ),
                    );
                    
                    // Refresh map markers when coming back (Phase 121)
                    await _loadInitialData();
                  },
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('REGISTRAR MONITOREO'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey),
        const SizedBox(width: 8),
        Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
        Expanded(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(int status) {
    switch (status) {
      case 1: return Colors.red;
      case 2: return Colors.yellow[700]!; // Borrador
      case 3: return Colors.green;
      case 4: return Colors.orange;
      default: return Colors.grey;
    }
  }

  String _getStatusLabel(int status) {
    switch (status) {
      case 1: return 'FALLIDO';
      case 2: return 'BORRADOR';
      case 3: return 'ENVIADO';
      case 4: return 'PENDIENTE';
      default: return 'SIN INFO';
    }
  }

  IconData _getStatusIcon(int status) {
    switch (status) {
      case 1: return Icons.error_outline;
      case 2: return Icons.edit_note;
      case 3: return Icons.check_circle_outline;
      case 4: return Icons.pending_actions;
      default: return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

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
          title: const Text(
            'Campañas', 
            style: TextStyle(
              color: Colors.white, 
              fontWeight: FontWeight.bold
            )
          ),
          backgroundColor: isDarkMode ? theme.colorScheme.surface : theme.primaryColor,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        drawer: const AppDrawer(currentRoute: '/campanas'),
        body: Stack(
          children: [
            // MAPA
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: const LatLng(-33.4489, -70.6693),
                initialZoom: 12,
                onMapReady: () {
                  debugPrint('🆗 [MAPA] El controlador está listo y el mapa es interactivo.');
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: _currentLayerUrl,
                  userAgentPackageName: 'monitoreo_app.skelletor.monitoring',
                  tileDisplay: const TileDisplay.fadeIn(),
                  // Mejora de diagnóstico
                  errorTileCallback: (tile, error, stackTrace) {
                    debugPrint('❌ [MAPA] Error cargando tile en ${_currentLayerUrl}: $error');
                  },
                ),
                // --- ORDEN DE RENDERIZADO (z-index) ---
                // Para que la estación seleccionada quede siempre arriba, ordenamos una copia de la lista.
                MarkerLayer(
                  markers: (() {
                    final sortedStations = List<Station>.from(_filteredStations);
                    sortedStations.sort((a, b) {
                      if (a.id == _selectedStationId) return 1;
                      if (b.id == _selectedStationId) return -1;
                      return 0;
                    });
                    
                    return sortedStations.map((s) {
                      final bool isSelected = s.id == _selectedStationId;
                      final int syncStatus = _stationStatuses[s.id] ?? 0;
                      
                      // Dynamic color mapping (Phase 118 Sync)
                      final Color markerColor = _getStatusColor(syncStatus);

                      return Marker(
                        point: LatLng(
                          double.parse(s.latitude.toString()), 
                          double.parse(s.longitude.toString()),
                        ),
                        // Wider bounding box for selection
                        width: isSelected ? 110 : 75,
                        height: isSelected ? 110 : 75,
                        child: GestureDetector(
                          onTap: () => _showStationDetails(s),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 1. STROKED ICON (Using hard directional shadows)
                              Icon(
                                Icons.location_on,
                                color: markerColor, 
                                size: isSelected ? 55 : 35, 
                                shadows: const [
                                  Shadow(offset: Offset(-1.5, -1.5), color: Colors.black),
                                  Shadow(offset: Offset(1.5, -1.5), color: Colors.black),
                                  Shadow(offset: Offset(1.5, 1.5), color: Colors.black),
                                  Shadow(offset: Offset(-1.5, 1.5), color: Colors.black),
                                ],
                              ),
                              const SizedBox(height: 2),
                              
                              // 2. STROKED TEXT (Using Stack + Paint)
                              Stack(
                                alignment: Alignment.center,
                                children: [
                                  // STROKE (Outer Border)
                                  Text(
                                    s.name,
                                    style: TextStyle(
                                      fontSize: isSelected ? 16 : 11, // Slightly larger
                                      fontWeight: FontWeight.w900, // Extra bold
                                      foreground: Paint()
                                        ..style = PaintingStyle.stroke
                                        ..strokeWidth = isSelected ? 3.5 : 2.5
                                        ..color = Colors.black,
                                    ),
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.visible,
                                  ),
                                  // FILL (Inner Color)
                                  Text(
                                    s.name,
                                    style: TextStyle(
                                      fontSize: isSelected ? 16 : 11,
                                      fontWeight: FontWeight.w900,
                                      color: Colors.white, // Standard white fill
                                    ),
                                    textAlign: TextAlign.center,
                                    overflow: TextOverflow.visible,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    });
                  })().toList(),
                ),
                const RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution(
                      '© OpenStreetMap contributors',
                    ),
                  ],
                ),
              ],
            ),

            // CONTROLES DE FILTRO (Barra Negra Superior)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                color: isDarkMode ? theme.colorScheme.surface.withOpacity(0.9) : Colors.black.withOpacity(0.85),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          isExpanded: true,
                          value: _selectedProgramId,
                          hint: const Text('Programa', style: TextStyle(color: Colors.white70, fontSize: 13)),
                          dropdownColor: Colors.grey[900],
                          icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          items: [
                            const DropdownMenuItem<int>(
                              value: null,
                              child: Text(
                                'Todos los Programas',
                                style: TextStyle(color: Colors.white),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            ..._programs.map((p) => DropdownMenuItem<int>(
                                  value: p.id,
                                  child: Text(
                                    p.name,
                                    style: const TextStyle(color: Colors.white),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                )),
                          ],
                          onChanged: _onProgramChanged,
                        ),
                      ),
                    ),
                    Container(
                      height: 24,
                      width: 1,
                      color: Colors.white30,
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          isExpanded: true,
                          value: _selectedStationId,
                          hint: const Text('Seleccione', style: TextStyle(color: Colors.white70, fontSize: 13)),
                          dropdownColor: Colors.grey[900],
                          icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          items: _filteredStations.map((s) {
                                final int status = _stationStatuses[s.id] ?? 0;
                                final Color dotColor = _getStatusColor(status);
                                
                                return DropdownMenuItem<int>(
                                  value: s.id,
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          s.name, 
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: Colors.white),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                          onChanged: _onStationChanged,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (_isLoading)
              const Center(child: CircularProgressIndicator(color: Colors.white)),

            Positioned(
              bottom: 120,
              left: 20,
              child: Column(
                children: [
                  _buildMapActionButton(
                    onPressed: () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom + 1),
                    icon: Icons.add,
                  ),
                  const SizedBox(height: 8),
                  _buildMapActionButton(
                    onPressed: () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom - 1),
                    icon: Icons.remove,
                  ),
                ],
              ),
            ),

            Positioned(
              top: 70,
              right: 20,
              child: Theme(
                data: Theme.of(context).copyWith(
                  hoverColor: Colors.transparent,
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                ),
                child: PopupMenuButton<String>(
                  onSelected: (String url) {
                    setState(() => _selectedLayerUrl = url);
                  },
                  offset: const Offset(0, 45),
                  elevation: 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  color: isDarkMode ? theme.colorScheme.surface : Colors.white,
                  padding: EdgeInsets.zero,
                  tooltip: 'Cambiar Capa',
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                    _buildLayerMenuItem('Estándar', 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'),
                    const PopupMenuDivider(height: 1),
                    _buildLayerMenuItem('Carreteras', 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}'),
                    const PopupMenuDivider(height: 1),
                    _buildLayerMenuItem('Satélite', 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'),
                  ],
                  child: _buildMapActionButton(
                    onPressed: null,
                    icon: Icons.layers,
                  ),
                ),
              ),
            ),

            // --- SECCIÓN: LISTA DE ESTACIONES DRAGGABLE (Phase 118) ---
            DraggableScrollableSheet(
              controller: _sheetController,
              initialChildSize: 0.12,
              minChildSize: 0.12,
              maxChildSize: 0.7,
              snap: true,
              builder: (context, scrollController) {
                return Container(
                  decoration: BoxDecoration(
                    color: isDarkMode ? theme.colorScheme.surface : Colors.white,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.15),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                    child: CustomScrollView(
                      controller: scrollController,
                      slivers: [
                        SliverToBoxAdapter(
                          child: Column(
                            children: [
                              const SizedBox(height: 12),
                              Container(
                                width: 40,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.grey[400],
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Row(
                                  children: [
                                    const Text(
                                      'Estaciones',
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '${_filteredStations.length} encontradas',
                                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.only(bottom: 20),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final s = _filteredStations[index];
                                final status = _stationStatuses[s.id] ?? 0;
                                final color = _getStatusColor(status);
                                final label = _getStatusLabel(status);
                                final icon = _getStatusIcon(status);
                                final isSelected = s.id == _selectedStationId;

                                return Card(
                                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                  elevation: isSelected ? 4 : 1,
                                  clipBehavior: Clip.antiAlias,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    side: isSelected 
                                      ? BorderSide(color: theme.colorScheme.primary, width: 2)
                                      : BorderSide.none,
                                    ),
                                  child: InkWell(
                                    onTap: () {
                                      // 1. Reset list scroll position (Phase 120.2)
                                      if (scrollController.hasClients) {
                                        scrollController.jumpTo(0);
                                      }
                                      // 2. Center map and collapse panel
                                      _onStationChanged(s.id);
                                    },
                                    onLongPress: () => _showStationDetails(s),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 8,
                                          height: 80,
                                          color: color,
                                        ),
                                        Expanded(
                                          child: ListTile(
                                            title: Text(
                                              s.name,
                                              style: const TextStyle(fontWeight: FontWeight.bold),
                                            ),
                                            subtitle: Text(
                                              'Lat: ${s.latitude}, Lon: ${s.longitude}',
                                              style: const TextStyle(fontSize: 12),
                                            ),
                                            trailing: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              crossAxisAlignment: CrossAxisAlignment.end,
                                              children: [
                                                Icon(icon, color: color, size: 20),
                                                const SizedBox(height: 4),
                                                Text(
                                                  label,
                                                  style: TextStyle(
                                                    color: color,
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                              childCount: _filteredStations.length,
                            ),
                          ),
                        ),
                      ],
                    ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapActionButton({required VoidCallback? onPressed, required IconData icon}) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? theme.colorScheme.surface.withOpacity(0.9) : Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: isDarkMode ? Colors.white : Colors.blue[800]),
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        padding: EdgeInsets.zero,
      ),
    );
  }

  PopupMenuItem<String> _buildLayerMenuItem(String title, String url) {
    final isSelected = _currentLayerUrl == url;
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return PopupMenuItem<String>(
      value: url,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isSelected ? (isDarkMode ? Colors.blueAccent : Colors.blue) : Colors.grey.shade400,
                width: isSelected ? 4 : 8,
              ),
              color: isSelected ? Colors.white : Colors.grey.shade600,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              color: isDarkMode ? Colors.white : Colors.grey.shade700,
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}