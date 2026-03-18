import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:intl/intl.dart';
import '../database/database_helper.dart';
import 'dart:math';

class ChartData {
  ChartData(this.x, this.y);
  final DateTime x;
  final double y;
}

class ChartAnalysisScreen extends StatefulWidget {
  final String estacion;
  final String parametro;
  final double? currentInputValue;

  const ChartAnalysisScreen({
    super.key,
    required this.estacion,
    required this.parametro,
    this.currentInputValue,
  });

  @override
  State<ChartAnalysisScreen> createState() => _ChartAnalysisScreenState();
}

class _ChartAnalysisScreenState extends State<ChartAnalysisScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<ChartData> _historicalData = [];
  late Future<void> _chartDataFuture;
  
  double _mean = 0;
  double _sigma = 0;
  double? _min3Sigma;
  double? _max3Sigma;
  bool _isOutOfRange = false;
  
  // Custom unit mapping (simplified)
  String _unit = '';

  double? _dynamicInputValue;
  late TextEditingController _overrideController;

  @override
  void initState() {
    super.initState();
    _loadUnit(); // 🚨 NEW: Fetch unit dynamically from SQLite
    _dynamicInputValue = widget.currentInputValue;
    _overrideController = TextEditingController(text: _dynamicInputValue?.toStringAsFixed(2) ?? '');
    _chartDataFuture = _loadAndCalculateData();
  }

  @override
  void dispose() {
    _overrideController.dispose();
    super.dispose();
  }

  void _updateChartValue() {
    final double? parsedValue = double.tryParse(_overrideController.text);
    if (parsedValue != null) {
      setState(() {
        _dynamicInputValue = parsedValue;
        if (_min3Sigma != null && _max3Sigma != null) {
          _isOutOfRange = parsedValue < _min3Sigma! || parsedValue > _max3Sigma!;
        }
      });
      FocusScope.of(context).unfocus();
    }
  }

  Future<void> _loadUnit() async {
    try {
      final db = await _dbHelper.database;
      final List<Map<String, dynamic>> result = await db.query(
        'parametros',
        columns: ['unidad'],
        where: 'clave_interna = ? OR nombre = ?',
        whereArgs: [widget.parametro, widget.parametro],
        limit: 1,
      );

      if (mounted) {
        setState(() {
          if (result.isNotEmpty && result.first['unidad'] != null) {
            _unit = result.first['unidad'].toString();
          } else {
            // Fallback for control fields not in the parameters catalog
            if (widget.parametro.toLowerCase().contains('profundidad') ||
                widget.parametro.toLowerCase().contains('nivel')) {
              _unit = 'm';
            } else {
              _unit = '';
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading unit from DB: $e');
    }
  }

  Future<void> _loadAndCalculateData() async {
    // Fetch from normalized table
    final historyRows = await _dbHelper.getHistorialMuestrasByStationName(widget.estacion);
    
    // Filter by parameter
    final paramRows = historyRows.where((row) => row['parametro'] == widget.parametro).toList();
    
    // Sort by date ascending
    paramRows.sort((a, b) => (a['fecha'] as String).compareTo(b['fecha'] as String));

    final List<ChartData> parsedData = [];
    final List<double> numericValues = [];

    for (var row in paramRows) {
      if (row['valor'] != null && row['fecha'] != null) {
        final val = (row['valor'] as num).toDouble();
        final date = DateTime.tryParse(row['fecha'].toString());
        if (date != null) {
          parsedData.add(ChartData(date, val));
          numericValues.add(val);
        }
      }
    }

    if (numericValues.isEmpty) return;

    // Do the math
    _calculateRanges(numericValues);

    // Assign data for the chart
    _historicalData = parsedData; 
  }

  void _calculateRanges(List<double> data) {
    if (data.isEmpty) return;
    
    final double sum = data.reduce((a, b) => a + b);
    _mean = sum / data.length;
    
    final double variance = data.map((x) => pow(x - _mean, 2)).reduce((a, b) => a + b) / (data.length > 1 ? data.length - 1 : 1);
    _sigma = variance > 0 ? sqrt(variance) : 0.0;
    
    setState(() {
      _min3Sigma = _mean - (3 * _sigma);
      _max3Sigma = _mean + (3 * _sigma);
      
      if (_dynamicInputValue != null) {
        _isOutOfRange = _dynamicInputValue! < _min3Sigma! || _dynamicInputValue! > _max3Sigma!;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.estacion),
        centerTitle: true,
      ),
      body: FutureBuilder<void>(
        future: _chartDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.blueAccent),
            );
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error al cargar datos: ${snapshot.error}'));
          }

          if (_historicalData.isEmpty) {
            return const Center(child: Text('Sin datos históricos para este punto'));
          }
          
          return Column(
            children: [
              _buildStatusBanner(),
              _buildDataInputBar(),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: _buildChart(),
                ),
              ),
              const SizedBox(height: 16),
              _buildStatsCards(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDataInputBar() {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final String paramName = widget.parametro;
    final String capitalizedParam = paramName.isNotEmpty ? '${paramName[0].toUpperCase()}${paramName.substring(1)}' : 'Valor';
    
    return Container(
      width: double.infinity,
      color: isDarkMode ? Colors.black.withValues(alpha: 0.2) : Colors.grey.shade100,
      padding: const EdgeInsets.all(16.0),
      margin: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          const Icon(Icons.arrow_forward, size: 20, color: Colors.grey),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$capitalizedParam [ $_unit ]',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Text(
                  _dynamicInputValue?.toStringAsFixed(2) ?? 'S/D',
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 80,
            child: TextField(
              controller: _overrideController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: '00.00',
              ),
              onSubmitted: (_) => _updateChartValue(),
            ),
          ),
          const SizedBox(width: 16),
          Material(
            color: Colors.blueAccent,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: _updateChartValue,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.all(12),
                child: const Icon(Icons.trending_up, size: 24, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBanner() {
    final bool outOfRange = _isOutOfRange;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      color: outOfRange ? Colors.redAccent.withValues(alpha: 0.2) : Colors.greenAccent.withValues(alpha: 0.2),
      child: Row(
        children: [
          Icon(
            outOfRange ? Icons.warning_amber_rounded : Icons.check_circle_outline,
            color: outOfRange ? Colors.red : Colors.green,
          ),
          const SizedBox(width: 12),
          Text(
            outOfRange ? 'Valor fuera de rango típico (3σ)' : 'Valor normal y típico',
            style: TextStyle(
              color: outOfRange ? Colors.red[900] : Colors.green[900],
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChart() {
    final TooltipBehavior tooltip = TooltipBehavior(
      enable: true,
      header: '',
      format: 'Fecha: point.x\nValor: point.y $_unit',
      color: Colors.grey.shade800,
    );

    final String paramName = widget.parametro;
    final String capitalizedParam = paramName.isNotEmpty ? '${paramName[0].toUpperCase()}${paramName.substring(1)}' : 'Valor';
    final String yAxisLabel = '$capitalizedParam [$_unit]';

    return SfCartesianChart(
      legend: const Legend(
        isVisible: true,
        position: LegendPosition.bottom,
        toggleSeriesVisibility: true,
        overflowMode: LegendItemOverflowMode.wrap,
      ),
      tooltipBehavior: tooltip,
      primaryXAxis: DateTimeAxis(
        title: const AxisTitle(text: ''),
        dateFormat: DateFormat('dd/MM/yyyy'),
        majorGridLines: const MajorGridLines(width: 0),
      ),
      primaryYAxis: NumericAxis(
        title: AxisTitle(text: yAxisLabel),
      ),
      series: <CartesianSeries<ChartData, DateTime>>[
        // 1. LimSup (Dashed Red Line)
        if (_max3Sigma != null && _historicalData.isNotEmpty)
          LineSeries<ChartData, DateTime>(
            // 🚨 CRITICAL FIX: Only two points to allow dashArray to render properly
            dataSource: [
              ChartData(_historicalData.first.x, _max3Sigma!),
              ChartData(_historicalData.last.x, _max3Sigma!),
            ],
            xValueMapper: (ChartData data, _) => data.x,
            yValueMapper: (ChartData data, _) => data.y,
            color: Colors.red,
            dashArray: const <double>[5, 5],
            name: 'LimSup',
            enableTooltip: false,
            markerSettings: const MarkerSettings(isVisible: false),
          ),
        // 2. LimInf (Dashed Orange Line)
        if (_min3Sigma != null && _historicalData.isNotEmpty)
          LineSeries<ChartData, DateTime>(
            // 🚨 CRITICAL FIX: Only two points
            dataSource: [
              ChartData(_historicalData.first.x, _min3Sigma!),
              ChartData(_historicalData.last.x, _min3Sigma!),
            ],
            xValueMapper: (ChartData data, _) => data.x,
            yValueMapper: (ChartData data, _) => data.y,
            color: Colors.orange,
            dashArray: const <double>[5, 5],
            name: 'LimInf',
            enableTooltip: false,
            markerSettings: const MarkerSettings(isVisible: false),
          ),
        LineSeries<ChartData, DateTime>(
          dataSource: _historicalData,
          xValueMapper: (ChartData data, _) => data.x,
          yValueMapper: (ChartData data, _) => data.y,
          color: Theme.of(context).brightness == Brightness.dark ? Colors.tealAccent : Colors.teal,
          name: widget.estacion,
          markerSettings: const MarkerSettings(isVisible: false),
        ),
        if (_dynamicInputValue != null)
          ScatterSeries<ChartData, DateTime>(
            dataSource: [ChartData(DateTime.now(), _dynamicInputValue!)],
            xValueMapper: (ChartData data, _) => data.x,
            yValueMapper: (ChartData data, _) => data.y,
            color: Colors.red, // 1. Sets the legend color
            name: 'Valor Actual',
            markerSettings: const MarkerSettings(
              isVisible: true,
              height: 16, 
              width: 16,
              shape: DataMarkerType.circle,
              color: Colors.red, // 🚨 CRITICAL FIX: Forces the marker fill to be red
              borderColor: Colors.white, // Thin white border for contrast
              borderWidth: 2,
            ),
          ),
      ],
    );
  }

  Widget _buildStatsCards() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard('Desviacion Estandar (σ)', _sigma.toStringAsFixed(2), _unit),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildStatCard('Promedio', _mean.toStringAsFixed(2), _unit),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, [String unit = '']) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0), // Reduce padding slightly to save space
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 10, color: Colors.grey),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          // Numerical Value (Number on top)
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          // Unit (Measurement on bottom)
          if (unit.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              unit,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
