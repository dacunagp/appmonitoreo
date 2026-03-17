import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../database/database_helper.dart';
import 'dart:math';

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
  List<double> _historicalData = [];
  late Future<void> _chartDataFuture;
  double _mean = 0;
  double _sigma = 0;
  bool _isOutOfRange = false;

  @override
  void initState() {
    super.initState();
    _chartDataFuture = _loadAndCalculateData();
  }

  Future<void> _loadAndCalculateData() async {
    // 1. Fetch optimized data
    final data = await _dbHelper.getHistoricalValues(widget.estacion, widget.parametro);
    
    if (data.isEmpty) return;

    // 2. Do the math
    final double sum = data.reduce((a, b) => a + b);
    _mean = sum / data.length;
    
    final double variance = data.map((x) => pow(x - _mean, 2)).reduce((a, b) => a + b) / data.length;
    _sigma = data.length > 1 && variance > 0 ? sqrt(variance) : 0.0;
    
    if (widget.currentInputValue != null) {
      _isOutOfRange = widget.currentInputValue! < (_mean - 3 * _sigma) || widget.currentInputValue! > (_mean + 3 * _sigma);
    }

    // 3. Assign data for the chart
    _historicalData = data; 
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.estacion} [${widget.parametro}]'),
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
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: _buildChart(),
                ),
              ),
              _buildStatsCards(),
            ],
          );
        },
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
    return SfCartesianChart(
      primaryXAxis: const NumericAxis(title: AxisTitle(text: 'Muestras (Index)')),
      series: <CartesianSeries>[
        LineSeries<double, int>(
          dataSource: _historicalData,
          xValueMapper: (_, index) => index,
          yValueMapper: (double val, _) => val,
          name: widget.parametro,
          markerSettings: const MarkerSettings(isVisible: true),
        ),
        if (widget.currentInputValue != null)
          ScatterSeries<double, int>(
            dataSource: [widget.currentInputValue!],
            xValueMapper: (_, __) => _historicalData.length,
            yValueMapper: (val, _) => val,
            color: Colors.blue,
            markerSettings: const MarkerSettings(isVisible: true, shape: DataMarkerType.circle, width: 15, height: 15),
          ),
      ],
    );
  }

  Widget _buildStatsCards() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatCard('Media (μ)', _mean.toStringAsFixed(2)),
          _buildStatCard('Sig (σ)', _sigma.toStringAsFixed(2)),
          _buildStatCard('Promedio', _mean.toStringAsFixed(2)),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
