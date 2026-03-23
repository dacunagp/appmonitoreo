import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';
import '../widgets/app_drawer.dart';
import '../database/database_helper.dart';
import '../models/models.dart';
import '../providers/graph_provider.dart';
import 'registrar_monitoreo_screen.dart'; // To use SearchableDropdown

class GraficosScreen extends StatefulWidget {
  const GraficosScreen({super.key});

  @override
  State<GraficosScreen> createState() => _GraficosScreenState();
}

class _GraficosScreenState extends State<GraficosScreen> with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  
  // State variables
  List<Map<String, dynamic>> _estacionesList = [];
  List<Parametro> _parametrosList = [];

  Map<String, dynamic>? _estacionSeleccionada; 
  List<Parametro> _parametrosSeleccionados = []; 
  
  List<List<ChartData>> _chartDataList = []; 
  bool _isLoadingData = true;
  bool _hasGraphed = false;
  
  // Options state
  bool _invertirEje = false; // Initialized to OFF per spec
  
  // Series colors
  Color _colorSerie1 = const Color(0xFF0D47A1); // Deep Blue
  Color _colorSerie2 = const Color(0xFFFF9800); // Orange

  @override
  late TabController _tabController;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _updateColor1(Color c) {
    setState(() => _colorSerie1 = c);
    if (mounted) {
      Provider.of<GraphProvider>(context, listen: false).updateOptions(color1: c);
    }
  }

  void _updateColor2(Color c) {
    setState(() => _colorSerie2 = c);
    if (mounted) {
      Provider.of<GraphProvider>(context, listen: false).updateOptions(color2: c);
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoadingData = true);
    try {
      final dbHelper = DatabaseHelper();
      
      // 1. Fetch ALL parameters dynamically
      final params = await dbHelper.getParametros();
      
      // 2. Fetch stations with program alias
      final stations = await dbHelper.getStationsWithPrograms();
      
      // 3. Restore from Provider (Scenario B)
      if (mounted) {
        final provider = Provider.of<GraphProvider>(context, listen: false);
        setState(() {
          _parametrosList = params;
          _estacionesList = stations;
          
          _chartDataList = provider.chartDataList;
          _hasGraphed = provider.hasGraphed;
          _parametrosSeleccionados = List.from(provider.parametrosSeleccionados);
          _estacionSeleccionada = provider.selectedStation;
          _invertirEje = provider.invertirEje;
          _colorSerie1 = provider.colorSerie1;
          _colorSerie2 = provider.colorSerie2;
          
          _isLoadingData = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingData = false);
        debugPrint('Error loading catalog data: $e');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al cargar datos: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

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
          title: const Text('Gráficos'),
          actions: [
            IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () {},
            ),
          ],
        ),
        drawer: const AppDrawer(currentRoute: '/graficos'),
        body: Column(
          children: [
            // 1. Chart Area
            _buildChartContent(isDarkMode),

            Container(
              height: 250,
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                children: [
                  TabBar(
                    controller: _tabController,
                    indicatorColor: Colors.blue,
                    labelColor: Colors.blue,
                    unselectedLabelColor: isDarkMode ? Colors.grey.shade400 : Colors.black54,
                    labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    onTap: (index) => setState(() {}),
                    tabs: const [
                      Tab(icon: Icon(Icons.show_chart, size: 20), text: 'GRAFICAR'),
                      Tab(icon: Icon(Icons.settings, size: 20), text: 'OPCIONES'),
                    ],
                  ),
                  Expanded(
                    child: IndexedStack(
                      index: _tabController.index,
                      children: [
                        // View 1: Graficar
                        _buildGraficarView(isDarkMode),
                        // View 2: Opciones
                        _buildOpcionesView(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartContent(bool isDarkMode) {
    if (_isLoadingData) {
      return const Expanded(child: Center(child: CircularProgressIndicator()));
    }

    if (_chartDataList.isEmpty && !_hasGraphed) {
      return Expanded(
        child: Container(
          width: double.infinity,
          color: isDarkMode ? Colors.black87 : Colors.grey.shade200,
          child: Stack(
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Icon(
                    Icons.crop_din,
                    color: isDarkMode ? Colors.grey.shade400 : Colors.black54,
                    size: 20,
                  ),
                ),
              ),
              Center(
                child: Text(
                  'Sin Datos para mostrar',
                  style: TextStyle(
                    color: isDarkMode ? Colors.grey.shade400 : Colors.black54,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_chartDataList.isEmpty && _hasGraphed) {
      return const Expanded(child: Center(child: Text('No hay registros históricos para esta combinación', style: TextStyle(color: Colors.grey, fontSize: 16), textAlign: TextAlign.center)));
    }

    final paramNames = _parametrosSeleccionados.map((p) => p.nombreParametro).join(' / ');
    final titleText = '${_estacionSeleccionada?['estacion'] ?? ""} [$paramNames]';
    final unitsText = _parametrosSeleccionados.map((p) => p.unidad).toSet().join(' / ');

    return Expanded(
      child: SfCartesianChart(
        backgroundColor: Colors.transparent,
        plotAreaBorderWidth: 0,
        title: ChartTitle(
          text: titleText, 
          textStyle: const TextStyle(fontSize: 14, color: Colors.blueAccent, fontWeight: FontWeight.bold)
        ),
        legend: const Legend(isVisible: false),
        tooltipBehavior: TooltipBehavior(enable: true, header: titleText),
        primaryXAxis: DateTimeAxis(
          majorGridLines: const MajorGridLines(width: 0.5, color: Colors.grey),
          labelStyle: const TextStyle(color: Colors.grey, fontSize: 10),
          dateFormat: DateFormat('dd/MM/yyyy'),
        ),
        primaryYAxis: NumericAxis(
          isInversed: _invertirEje,
          minimum: _parametrosSeleccionados.isNotEmpty ? _parametrosSeleccionados[0].min : null,
          maximum: _parametrosSeleccionados.isNotEmpty ? _parametrosSeleccionados[0].max : null,
          title: AxisTitle(
            text: _parametrosSeleccionados.isNotEmpty 
              ? '${_parametrosSeleccionados[0].nombreParametro} [${_parametrosSeleccionados[0].unidad}]' 
              : '', 
            textStyle: TextStyle(color: _colorSerie1, fontSize: 10)
          ),
          majorGridLines: const MajorGridLines(width: 0.5, color: Colors.grey),
          labelStyle: const TextStyle(color: Colors.grey, fontSize: 10),
          labelFormat: '{value}',
        ),
        axes: <ChartAxis>[
          if (_parametrosSeleccionados.length > 1)
            NumericAxis(
              name: 'secondaryYAxis',
              opposedPosition: true,
              minimum: _parametrosSeleccionados[1].min,
              maximum: _parametrosSeleccionados[1].max,
              title: AxisTitle(
                text: '${_parametrosSeleccionados[1].nombreParametro} [${_parametrosSeleccionados[1].unidad}]',
                textStyle: TextStyle(color: _colorSerie2, fontSize: 10),
              ),
              majorGridLines: const MajorGridLines(width: 0),
              labelStyle: const TextStyle(color: Colors.grey, fontSize: 10),
              labelFormat: '{value}',
            ),
        ],
        series: List.generate(_parametrosSeleccionados.length, (index) {
          final p = _parametrosSeleccionados[index];
          final color = index == 0 ? _colorSerie1 : _colorSerie2;
          return LineSeries<ChartData, DateTime>(
            dataSource: _chartDataList.length > index ? _chartDataList[index] : [],
            xValueMapper: (ChartData data, _) => data.x,
            yValueMapper: (ChartData data, _) => data.y,
            yAxisName: index == 1 ? 'secondaryYAxis' : null,
            color: color,
            width: 2,
            markerSettings: const MarkerSettings(
              isVisible: true,
              width: 4,
              height: 4,
            ),
            name: p.nombreParametro,
          );
        }),
      ),
    );
  }

  Widget _buildGraficarView(bool isDarkMode) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Column(
              children: [
                // Compact Horizontal List
                Container(
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.grey.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      // Estaciones Item
                      InkWell(
                        onTap: () {
                          _mostrarDialogoSeleccionManual(
                            titulo: 'Seleccionar Estación / Programa',
                            esEstacion: true,
                            onSeleccionado: (dynamic seleccion) {
                              setState(() {
                                _estacionSeleccionada = seleccion;
                                _hasGraphed = false;
                              });
                              _fetchAndGraphData();
                            },
                          );
                        },
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              const Icon(Icons.location_on, color: Colors.blueAccent, size: 20),
                              const SizedBox(width: 12),
                              const Text('Estaciones', style: TextStyle(fontSize: 14, color: Colors.blueAccent)),
                              const Spacer(),
                              Text(
                                _estacionSeleccionada?['estacion'] ?? 'Seleccione',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDarkMode ? Colors.white70 : Colors.black87,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_drop_down, color: Colors.grey, size: 20),
                            ],
                          ),
                        ),
                      ),
                      // Divider
                      Divider(height: 1, thickness: 1, color: isDarkMode ? Colors.white10 : Colors.black12),
                      // Parámetros Item
                      InkWell(
                        onTap: () {
                          _mostrarDialogoSeleccionParametros(
                            titulo: 'Seleccionar Parámetros (Máx 2)',
                          );
                        },
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              const Icon(Icons.science, color: Colors.green, size: 20),
                              const SizedBox(width: 12),
                              const Text('Parámetros', style: TextStyle(fontSize: 14, color: Colors.blueAccent)),
                              const Spacer(),
                              Text(
                                _parametrosSeleccionados.isEmpty 
                                  ? 'Seleccione' 
                                  : _parametrosSeleccionados.length == 1 
                                    ? _parametrosSeleccionados.first.nombreParametro 
                                    : '${_parametrosSeleccionados.length} Seleccionados',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDarkMode ? Colors.white70 : Colors.black87,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_drop_down, color: Colors.grey, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _mostrarDialogoSeleccionParametros({
    required String titulo,
  }) async {
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            final isDarkMode = Theme.of(context).brightness == Brightness.dark;
            return AlertDialog(
              backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              title: Text(titulo, style: const TextStyle(fontSize: 16)),
              contentPadding: const EdgeInsets.only(top: 12),
              content: SizedBox(
                width: double.maxFinite,
                height: 350,
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _parametrosList.length,
                  itemBuilder: (context, index) {
                    final param = _parametrosList[index];
                    final isSelected = _parametrosSeleccionados.contains(param);
                    return CheckboxListTile(
                      title: Text(param.nombreParametro, style: const TextStyle(fontSize: 14)),
                      secondary: const Icon(Icons.science, color: Colors.green, size: 20),
                      value: isSelected,
                      activeColor: Colors.blueAccent,
                      checkColor: Colors.white,
                      onChanged: (bool? value) {
                        setStateDialog(() {
                          if (value == true) {
                            if (_parametrosSeleccionados.length < 2) {
                              _parametrosSeleccionados.add(param);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Máximo 2 parámetros'), duration: Duration(seconds: 1)),
                              );
                            }
                          } else {
                            _parametrosSeleccionados.remove(param);
                          }
                        });
                        // Update main state to show selection in real-time
                        setState(() {
                          _hasGraphed = false;
                        });
                      },
                    );
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _fetchAndGraphData();
                  },
                  child: const Text('LISTO', style: TextStyle(color: Colors.blueAccent)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _mostrarDialogoSeleccionManual({
    required String titulo,
    required bool esEstacion,
    required Function(dynamic) onSeleccionado,
  }) async {
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          title: Text(titulo, style: const TextStyle(fontSize: 16)),
          contentPadding: const EdgeInsets.only(top: 12),
          content: SizedBox(
            width: double.maxFinite,
            height: 350,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _estacionesList.length,
              itemBuilder: (context, index) {
                final item = _estacionesList[index];
                return ListTile(
                  title: Text(item['estacion'] ?? 'S/N', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  subtitle: Text(item['program_name'] ?? 'Sin programa', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  leading: const Icon(Icons.location_on, color: Colors.blueAccent, size: 20),
                  onTap: () {
                    onSeleccionado(item);
                    Navigator.of(context).pop();
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('CANCELAR', style: TextStyle(color: Colors.blueAccent)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _fetchAndGraphData() async {
    if (_estacionSeleccionada == null || _parametrosSeleccionados.isEmpty) {
      setState(() {
        _chartDataList = [];
        _hasGraphed = false;
      });
      return;
    }

    try {
      final String selectedStationName = _estacionSeleccionada!['estacion'];
      final List<List<ChartData>> newDataList = [];

      final data = await _dbHelper.getHistorialMuestrasByStationName(selectedStationName);

      for (var param in _parametrosSeleccionados) {
        final String selectedInternalKey = param.claveInterna;
        debugPrint('📊 Solicitando gráfico para: $selectedStationName -> $selectedInternalKey');

        final List<ChartData> mappedData = data.where((sample) => sample['parametro'] == selectedInternalKey).map((sample) {
          final dateValue = DateTime.tryParse(sample['fecha'] ?? '');
          final dynamicRaw = sample['valor'];
          final double? yValue = dynamicRaw is double ? dynamicRaw : double.tryParse(dynamicRaw?.toString() ?? '');
          if (dateValue != null && yValue != null) {
            return ChartData(dateValue, yValue);
          }
          return null;
        }).whereType<ChartData>().toList();

        // Sort data by date for proper charting
        mappedData.sort((a, b) => a.x.compareTo(b.x));
        newDataList.add(mappedData);
      }

      setState(() {
        _chartDataList = newDataList;
        _hasGraphed = true;
      });

      // Update Provider for Scenario B
      if (mounted) {
        Provider.of<GraphProvider>(context, listen: false).updateGraphData(
          data: newDataList,
          hasGraphed: true,
          params: _parametrosSeleccionados,
          station: _estacionSeleccionada,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al graficar: $e')));
      }
    }
  }

  Widget _buildOpcionesView() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // "Invert. Eje1" Switch (functional logic implemented)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: _buildSwitchRow(
              label: 'Invert. Eje1',
              value: _invertirEje,
              onChanged: (val) {
                setState(() => _invertirEje = val);
                Provider.of<GraphProvider>(context, listen: false).updateOptions(invertirEje: val);
              },
            ),
          ),
          
          // Dual Color Palette Section in a Floating Card style
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Card(
              color: Colors.white,
              elevation: 4,
              shadowColor: Colors.black26,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Selector 1: Color Parámetro 1
                    const Text(
                      'Color Parámetro 1',
                      style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildColorCircle(const Color(0xFF0D47A1), _colorSerie1 == const Color(0xFF0D47A1), _updateColor1),
                        const SizedBox(width: 12),
                        _buildColorCircle(const Color(0xFF008080), _colorSerie1 == const Color(0xFF008080), _updateColor1),
                        const SizedBox(width: 12),
                        _buildColorCircle(const Color(0xFF4CAF50), _colorSerie1 == const Color(0xFF4CAF50), _updateColor1),
                      ],
                    ),
                    
                    const SizedBox(height: 20),
                    
                    // Selector 2: Color Parámetro 2
                    const Text(
                      'Color Parámetro 2',
                      style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _buildColorCircle(const Color(0xFFFF9800), _colorSerie2 == const Color(0xFFFF9800), _updateColor2),
                        const SizedBox(width: 12),
                        _buildColorCircle(const Color(0xFF9C27B0), _colorSerie2 == const Color(0xFF9C27B0), _updateColor2),
                        const SizedBox(width: 12),
                        _buildColorCircle(const Color(0xFFF44336), _colorSerie2 == const Color(0xFFF44336), _updateColor2),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildColorCircle(Color color, bool isSelected, ValueChanged<Color> onTap) {
    return GestureDetector(
      onTap: () => onTap(color),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isSelected ? Border.all(color: Colors.blue, width: 3) : null,
        ),
      ),
    );
  }

  Widget _buildSwitchRow({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.blue,
              fontWeight: FontWeight.w500,
              fontSize: 15,
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: Colors.blue,
          ),
        ],
      ),
    );
  }
}