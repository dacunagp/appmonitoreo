import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../database/database_helper.dart';
import '../widgets/app_drawer.dart';
import '../models/models.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio_cache_interceptor_file_store/dio_cache_interceptor_file_store.dart';

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
      final programs = await _dbHelper.getPrograms();
      final stations = await _dbHelper.getAllStations();
      
      // Initialize Cache Path for Offline Maps
      final cacheDir = await getApplicationDocumentsDirectory();
      
      // Fetch Sync Statuses
      final Map<int, int> statuses = {};
      for (var s in stations) {
        statuses[s.id] = await _dbHelper.getStationSyncStatus(s.id);
      }
      
      setState(() {
        _programs = programs;
        _allStations = stations;
        _filteredStations = stations;
        _stationStatuses = statuses;
        _cachePath = '${cacheDir.path}/map_tiles_cache';
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading initial data: $e');
      setState(() => _isLoading = false);
    }
  }

  void _onProgramChanged(int? programId) async {
    setState(() {
      _selectedProgramId = programId;
      _selectedStationId = null;
      _isLoading = true;
    });
    
    try {
      if (programId == null) {
        final stations = await _dbHelper.getAllStations();
        setState(() {
          _filteredStations = stations;
          _isLoading = false;
        });
      } else {
        final stations = await _dbHelper.getStationsByProgram(programId);
        final Map<int, int> statuses = {};
        for (var s in stations) {
          statuses[s.id] = await _dbHelper.getStationSyncStatus(s.id);
        }
        setState(() {
          _filteredStations = stations;
          _stationStatuses = statuses;
          _isLoading = false;
        });

        if (stations.isNotEmpty) {
          _mapController.move(
            LatLng(stations[0].latitude, stations[0].longitude),
            12,
          );
        }
      }
    } catch (e) {
      debugPrint('Error changing program: $e');
      setState(() => _isLoading = false);
    }
  }

  void _onStationChanged(int? stationId) {
    setState(() => _selectedStationId = stationId);
    if (stationId != null) {
      final station = _allStations.firstWhere((s) => s.id == stationId);
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
              _buildDetailRow(Icons.map, 'Coordenadas', '${station.latitude}, ${station.longitude}'),
              const SizedBox(height: 16),
              const Text(
                'Detalles de la Estación:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                'Esta estación forma parte del programa de monitoreo seleccionado. '
                'Toque el botón inferior para ver el historial de esta estación.',
                style: TextStyle(color: isDarkMode ? Colors.grey[400] : Colors.grey[700]),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    // Navegación desactivada por requerimiento
                    debugPrint('Navegación bloqueada para: ${station.name}');
                  },
                  icon: const Icon(Icons.history),
                  label: const Text('VER HISTORIAL COMPLETO'),
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
          title: Text(
            'Campañas', 
            style: TextStyle(
              color: isDarkMode ? Colors.white : Colors.black87, 
              fontWeight: FontWeight.bold
            )
          ),
          backgroundColor: isDarkMode ? theme.colorScheme.surface : theme.primaryColor,
          elevation: 0,
          iconTheme: IconThemeData(color: isDarkMode ? Colors.white : Colors.black87),
        ),
        drawer: const AppDrawer(currentRoute: '/campanas'),
        body: Stack(
          children: [
            // MAPA
            FlutterMap(
              mapController: _mapController,
              options: const MapOptions(
                initialCenter: LatLng(-33.4489, -70.6693),
                initialZoom: 12,
              ),
              children: [
                TileLayer(
                  urlTemplate: _currentLayerUrl,
                  userAgentPackageName: 'com.example.monitoreo_app',
                  tileProvider: _cachePath != null 
                    ? CachedTileProvider(
                        store: FileCacheStore(_cachePath!),
                      )
                    : null,
                  errorTileCallback: (tile, error, stackTrace) {
                    debugPrint('❌ Error cargando tile: $error');
                  },
                ),
                MarkerLayer(
                  markers: _filteredStations.map((s) {
                    final isSelected = s.id == _selectedStationId;
                    final status = _stationStatuses[s.id] ?? -1;
                    Color markerColor = Colors.red;
                    if (status == 2) markerColor = Colors.green;
                    if (status == 0) markerColor = Colors.orange;
                    if (isSelected) markerColor = Colors.yellow;

                    return Marker(
                      point: LatLng(
                        double.parse(s.latitude.toString()), 
                        double.parse(s.longitude.toString()),
                      ),
                      width: 80,
                      height: 80,
                      child: GestureDetector(
                        onTap: () => _showStationDetails(s),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.location_on,
                              color: markerColor,
                              size: isSelected ? 45 : 35,
                              shadows: const [Shadow(blurRadius: 10, color: Colors.black)],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              s.name,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                shadows: [
                                  Shadow(color: Colors.black, blurRadius: 2.0, offset: Offset(1, 1))
                                ],
                              ),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
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
                          value: _selectedProgramId,
                          hint: const Text('Programa', style: TextStyle(color: Colors.white70, fontSize: 13)),
                          dropdownColor: Colors.grey[900],
                          icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          items: [
                            const DropdownMenuItem<int>(
                              value: null,
                              child: Text('Todos los Programas'),
                            ),
                            ..._programs.map((p) => DropdownMenuItem<int>(
                                  value: p.id,
                                  child: Text(p.name),
                                )),
                          ],
                          onChanged: _onProgramChanged,
                        ),
                      ),
                    ),
                    const VerticalDivider(color: Colors.white30, width: 20),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _selectedStationId,
                          hint: const Text('Seleccione', style: TextStyle(color: Colors.white70, fontSize: 13)),
                          dropdownColor: Colors.grey[900],
                          icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          items: _filteredStations.map((s) => DropdownMenuItem<int>(
                                value: s.id,
                                child: Text(s.name, overflow: TextOverflow.ellipsis),
                              )).toList(),
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
              bottom: 20,
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