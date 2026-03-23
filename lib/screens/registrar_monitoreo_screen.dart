import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import '../widgets/app_drawer.dart';
import '../database/database_helper.dart';
import '../models/models.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'dart:async';
import 'chart_analysis_screen.dart';

class RegistrarMonitoreoScreen extends StatefulWidget {
  final int? registroId;
  const RegistrarMonitoreoScreen({super.key, this.registroId});

  @override
  State<RegistrarMonitoreoScreen> createState() => _RegistrarMonitoreoScreenState();
}

class _RegistrarMonitoreoScreenState extends State<RegistrarMonitoreoScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  // --- 1. VARIABLES DE ESTADO ---
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isMonitoreoFallido = false;
  int? _currentRegistroId;
  Timer? _debounce;
  bool _isProcessingImage = false;
  bool _isProcessingMulti = false;
  bool _isProcessingTurb = false;
  DateTime? _fechaYHoraMuestreo; 
  String? _imagePath;
  String? _fotoMultiparametroPath;
  String? _fotoTurbiedadPath;
  final ImagePicker _picker = ImagePicker();
  final ScreenshotController _screenshotController = ScreenshotController();
  double? _estacionLatitud;
  double? _estacionLongitud;

  // Listas para dropdowns
  List<Program> _programas = [];
  List<Station> _estaciones = [];
  List<Matriz> _matrices = [];
  List<EquipoDetalle> _equiposMulti = [];
  List<EquipoDetalle> _turbidimetros = [];
  List<Metodo> _metodos = [];
  String? _inspectorSeleccionado;
  List<String> _inspectoresOptions = [];
  List<String> _equiposMultiOptions = [];
  List<String> _turbidimetrosOptions = [];

  // Selecciones (Objetos o IDs para lógica interna)
  Program? _programaSeleccionado;
  Station? _estacionSeleccionada;
  Matriz? _matrizSeleccionada;
  String? _equipoMultiparametroSeleccionado;
  String? _turbidimetroSeleccionado;
  Metodo? _metodoSeleccionado;

  // Controllers para inputs numéricos y texto
  final TextEditingController _tempController = TextEditingController();
  final TextEditingController _phController = TextEditingController();
  final TextEditingController _condController = TextEditingController();
  final TextEditingController _oxigenoController = TextEditingController();
  final TextEditingController _turbiedadController = TextEditingController();
  final TextEditingController _codLabController = TextEditingController();
  final TextEditingController _obsController = TextEditingController();
  final TextEditingController _profundidadController = TextEditingController();
  final TextEditingController _nivelTerrenoController = TextEditingController();
  String? _equipoNivelSeleccionado;
  String? _tipoNivelPozoSeleccionado;
  DateTime? _fechaYHoraNivel;
  
  // STATISTICAL VALIDATION
  bool _hasHistory = false;
  Map<String, Map<String, double?>> _parameterRanges = {};

  bool? _muestreoHidroquimico; 
  bool? _muestreoIsotopico;

  // --- VALIDATION GETTERS ---
  bool get _isDatosMonitoreoComplete {
    if (_isMonitoreoFallido) return _obsController.text.isNotEmpty;
    return _programaSeleccionado != null && 
           _estacionSeleccionada != null && 
           _inspectorSeleccionado != null;
  }

  bool get _isMultiparametroComplete {
    if (_equipoMultiparametroSeleccionado == null) return false;
    return _tempController.text.isNotEmpty &&
        _phController.text.isNotEmpty &&
        _condController.text.isNotEmpty &&
        _oxigenoController.text.isNotEmpty &&
        _fotoMultiparametroPath != null;
  }

  bool get _isTurbiedadComplete {
    if (_turbidimetroSeleccionado == null) return false;
    return _turbiedadController.text.isNotEmpty && _fotoTurbiedadPath != null;
  }

  bool get _isMuestreoComplete {
    return _metodoSeleccionado != null &&
        _muestreoHidroquimico != null &&
        _muestreoIsotopico != null;
  }

  bool get _isFormularioCompleto {
    return _isDatosMonitoreoComplete;
  }

  @override
  void initState() {
    super.initState();
    _currentRegistroId = widget.registroId;
    _loadDropdownData();
    
    // Add listeners for auto-save
    _tempController.addListener(_onFieldChanged);
    _phController.addListener(_onFieldChanged);
    _condController.addListener(_onFieldChanged);
    _oxigenoController.addListener(_onFieldChanged);
    _turbiedadController.addListener(_onFieldChanged);
    _codLabController.addListener(_onFieldChanged);
    _obsController.addListener(_onFieldChanged);
    _profundidadController.addListener(_onFieldChanged);
    _nivelTerrenoController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    // Force UI to rebuild to show green checks immediately as the user types
    setState(() {}); 

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(seconds: 2), () {
      _saveAsDraft();
    });
  }

  Future<void> _saveAsDraft() async {
    // Only save as draft if at least some basic info is selected
    if (_programaSeleccionado == null && _estacionSeleccionada == null) return;
    
    // Dynamically evaluate if it should be a draft
    bool isDraft = !_isFormularioCompleto;
    
    await _guardarInterno(isDraft: isDraft);
    debugPrint('Auto-guardado id: $_currentRegistroId (isDraft: $isDraft)');
  }

  Future<void> _guardarInterno({required bool isDraft}) async {
    try {
      // 1. Build Header Map
      int? inspectorId;
      if (_inspectorSeleccionado != null) {
        final usuarios = await _dbHelper.getUsuarios();
        try {
          final inspector = usuarios.firstWhere((u) => '${u.nombre} ${u.apellido}' == _inspectorSeleccionado);
          inspectorId = inspector.idUsuario;
        } catch (_) {}
      }

      final Map<String, dynamic> header = {
        'id': _currentRegistroId,
        'programa_id': _programaSeleccionado?.id,
        'estacion_id': _estacionSeleccionada?.id,
        'fecha_hora': _fechaYHoraMuestreo?.toIso8601String() ?? DateTime.now().toIso8601String(),
        'monitoreo_fallido': _isMonitoreoFallido ? 1 : 0,
        'observacion': _obsController.text,
        'matriz_id': _matrizSeleccionada?.idMatriz,
        'equipo_multi_id': _equiposMulti.where((e) => e.codigo == _equipoMultiparametroSeleccionado).firstOrNull?.id,
        'turbidimetro_id': _turbidimetros.where((e) => e.codigo == _turbidimetroSeleccionado).firstOrNull?.id,
        'metodo_id': _metodoSeleccionado?.idMetodo,
        'hidroquimico': _muestreoHidroquimico == true ? 1 : 0,
        'isotopico': _muestreoIsotopico == true ? 1 : 0,
        'cod_laboratorio': _codLabController.text,
        'usuario_id': inspectorId,
        'foto_path': _imagePath,
        'foto_multiparametro': _fotoMultiparametroPath,
        'foto_turbiedad': _fotoTurbiedadPath,
        'equipo_nivel_id': _equiposMulti.where((e) => e.codigo == _equipoNivelSeleccionado).firstOrNull?.id,
        'tipo_pozo': _tipoNivelPozoSeleccionado,
        'fecha_hora_nivel': _fechaYHoraNivel?.toIso8601String(),
        'latitud': _estacionLatitud,
        'longitud': _estacionLongitud,
        'temperatura': double.tryParse(_tempController.text),
        'ph': double.tryParse(_phController.text),
        'conductividad': double.tryParse(_condController.text),
        'oxigeno': double.tryParse(_oxigenoController.text),
        'turbiedad': double.tryParse(_turbiedadController.text),
        'profundidad': double.tryParse(_profundidadController.text),
        'nivel': double.tryParse(_nivelTerrenoController.text),
        'is_draft': isDraft ? 1 : 0,
      };

      // CRITICAL FIX: Remove 'id' if null so SQLite auto-increments properly
      if (header['id'] == null) {
        header.remove('id');
      }

      // 2. Build Details List (Parameters) - Empty as we now use flattened schema
      List<Map<String, dynamic>> detalles = [];

      // 3. Save via Transaction
      final id = await _dbHelper.saveMonitoreoTransaction(header, detalles);
      
      if (_currentRegistroId == null) {
        setState(() => _currentRegistroId = id);
      }
    } catch (e) {
      debugPrint('Error en _guardarInterno: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ ERROR GUARDANDO BORRADOR: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          )
        );
      }
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tempController.dispose();
    _phController.dispose();
    _condController.dispose();
    _oxigenoController.dispose();
    _turbiedadController.dispose();
    _codLabController.dispose();
    _obsController.dispose();
    _profundidadController.dispose();
    _nivelTerrenoController.dispose();
    super.dispose();
  }

  Future<void> _loadDropdownData() async {
    setState(() => _isLoading = true);
    try {
      final programas = await _dbHelper.getPrograms();
      final matrices = await _dbHelper.getMatrices();
      final metodos = await _dbHelper.getMetodos();
      final usuarios = await _dbHelper.getUsuarios();
      
      final multiData = await _dbHelper.getEquiposByType('Pozómetro');
      var turbiData = await _dbHelper.getEquiposByType('Turbidímetro');
      if (turbiData.isEmpty) {
        turbiData = await _dbHelper.getEquiposByType('Turbidimetro');
      }

      setState(() {
        _programas = programas;
        _matrices = matrices;
        _metodos = metodos;
        _inspectoresOptions = usuarios.map((u) => '${u.nombre} ${u.apellido}').toList();
        
        _equiposMulti = multiData;
        _equiposMultiOptions = multiData.map((e) => e.codigo.toString()).toList();
        
        _turbidimetros = turbiData;
        _turbidimetrosOptions = turbiData.map((e) => e.codigo.toString()).toList();
        
        _isLoading = false;
      });

      if (widget.registroId != null) {
        await _loadExistingData(widget.registroId!);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadExistingData(int id) async {
    final data = await _dbHelper.getRegistroMonitoreoById(id);
    if (data == null) return;

    setState(() {
      // 1. Basic Fields
      _isMonitoreoFallido = data['monitoreo_fallido'] == 1;
      if (data['fecha_hora'] != null) {
        _fechaYHoraMuestreo = DateTime.parse(data['fecha_hora']);
      }
      _obsController.text = data['observacion'] ?? '';
      _codLabController.text = data['cod_laboratorio'] ?? '';
      _muestreoHidroquimico = data['hidroquimico'] == 1;
      _muestreoIsotopico = data['isotopico'] == 1;

      // 2. Dropdowns - Objects
      if (data['programa_id'] != null) {
        try {
          _programaSeleccionado = _programas.firstWhere((p) => p.id == data['programa_id']);
        } catch (_) {}
      }
      if (data['matriz_id'] != null) {
        try {
          _matrizSeleccionada = _matrices.firstWhere((m) => m.idMatriz == data['matriz_id']);
        } catch (_) {}
      }
      if (data['metodo_id'] != null) {
        try {
          _metodoSeleccionado = _metodos.firstWhere((m) => m.idMetodo == data['metodo_id']);
        } catch (_) {}
      }

      // 3. Dropdowns - Strings (Inverse Lookup)
      if (data['usuario_id'] != null) {
        _dbHelper.getUsuarios().then((usuarios) {
          try {
            final u = usuarios.firstWhere((user) => user.idUsuario == data['usuario_id']);
            setState(() => _inspectorSeleccionado = '${u.nombre} ${u.apellido}');
          } catch (_) {}
        });
      }
      
      if (data['equipo_multi_id'] != null) {
        try {
          final eq = _equiposMulti.firstWhere((e) => e.id == data['equipo_multi_id']);
_equipoMultiparametroSeleccionado = eq.codigo;
        } catch (_) {}
      }
      if (data['turbidimetro_id'] != null) {
        try {
          final eq = _turbidimetros.firstWhere((e) => e.id == data['turbidimetro_id']);
          _turbidimetroSeleccionado = eq.codigo;
        } catch (_) {}
      }

      if (data['equipo_nivel_id'] != null) {
        try {
          final eq = _equiposMulti.firstWhere((e) => e.id == data['equipo_nivel_id']);
          _equipoNivelSeleccionado = eq.codigo;
        } catch (_) {}
      }
      _tipoNivelPozoSeleccionado = data['tipo_pozo'];
      if (data['fecha_hora_nivel'] != null) {
        _fechaYHoraNivel = DateTime.parse(data['fecha_hora_nivel']);
      }

      // 4. Flattened Loading: Load parameters directly from data map
      _tempController.text = data['temperatura']?.toString() ?? '';
      _phController.text = data['ph']?.toString() ?? '';
      _condController.text = data['conductividad']?.toString() ?? '';
      _oxigenoController.text = data['oxigeno']?.toString() ?? '';
      _turbiedadController.text = data['turbiedad']?.toString() ?? '';
      _profundidadController.text = data['profundidad']?.toString() ?? '';
      _nivelTerrenoController.text = data['nivel']?.toString() ?? '';
      _estacionLatitud = data['latitud'];
      _estacionLongitud = data['longitud'];

      _imagePath = data['foto_path'];
      _fotoMultiparametroPath = data['foto_multiparametro'];
      _fotoTurbiedadPath = data['foto_turbiedad'];
    });

    // Special case: Load stations if program is selected
    if (_programaSeleccionado != null) {
      final stations = await _dbHelper.getStationsByProgram(_programaSeleccionado!.id);
      setState(() {
        _estaciones = stations;
        try {
          _estacionSeleccionada = _estaciones.firstWhere((s) => s.id == data['estacion_id']);
        } catch (_) {}
      });

      // TRIGGER: Fetch 3 Sigma ranges for the loaded station
      if (_estacionSeleccionada != null) {
        await _updateHistoricalRanges(_estacionSeleccionada!.name);
      }
    }
  }

  Future<void> _onProgramaChanged(String name) async {
    final programa = _programas.firstWhere((p) => p.name == name);
    setState(() {
      _programaSeleccionado = programa;
      _estacionSeleccionada = null;
      _estaciones = [];
    });

    try {
      final estaciones = await _dbHelper.getStationsByProgram(programa.id);
      setState(() => _estaciones = estaciones);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al cargar puntos: $e')));
      }
    }
    
    _saveAsDraft();
  }

  Future<void> _onStationChanged(String name) async {
    final station = _estaciones.firstWhere((s) => s.name == name);
    setState(() {
      _estacionSeleccionada = station;
      _estacionLatitud = station.latitude;
      _estacionLongitud = station.longitude;
    });

    await _updateHistoricalRanges(station.name);
    _saveAsDraft();
  }

  Future<void> _updateHistoricalRanges(String stationName) async {
    try {
      final history = await _dbHelper.getHistorialMuestrasByStationName(stationName);
      
      if (history.isEmpty) {
        setState(() {
          _hasHistory = false;
          _parameterRanges = {};
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sin datos históricos. Todo valor ingresado se marcará como anómalo.'),
              backgroundColor: Colors.redAccent,
            )
          );
        }
        return;
      }

      // 1. Prepare map with EXACT database keys
      final Map<String, List<double>> values = {
        'temperatura': [], 
        'ph': [], 
        'conductividad': [], 
        'oxigeno': [], 
        'turbiedad': [], 
        'profundidad': [],
        'nivel': []
      };

      // 2. Parse normalized rows (parametro, valor)
      for (var row in history) {
        final String? paramKey = row['parametro']?.toString();
        final dynamic val = row['valor'];
        
        if (paramKey != null && val != null && values.containsKey(paramKey)) {
          values[paramKey]!.add((val as num).toDouble());
        }
      }

      // 3. Calculate 3-Sigma Ranges
      final Map<String, Map<String, double?>> ranges = {};
      values.forEach((key, list) {
        ranges[key] = _calculateThreeSigmaRange(list);
      });

      setState(() {
        _hasHistory = true;
        _parameterRanges = ranges;
      });
    } catch (e) {
      debugPrint('Error calculating ranges: $e');
    }
  }

  Future<void> _navigateToChart(String parameterKey, TextEditingController controller) async {
    // 1. Close keyboard and trace event
    FocusScope.of(context).unfocus();
    debugPrint('🚨 TOCASTE EL PULSO 🚨');
    debugPrint('👉 Parámetro: $parameterKey');
    debugPrint('👉 Estación: "${_estacionSeleccionada?.name}"');

    // 2. Validate the station
    if (_estacionSeleccionada == null) {
      debugPrint('❌ Navegación cancelada: Estación no válida.');
      _showError('Por favor, selecciona un Punto de Control arriba primero.');
      return;
    }

    // 3. Force save draft before leaving
    await _saveAsDraft();

    // 4. Proceed to Navigation
    if (!mounted) return;
    debugPrint('✅ Datos guardados. Navegando a ChartAnalysisScreen...');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChartAnalysisScreen(
          estacion: _estacionSeleccionada!.name,
          parametro: parameterKey,
          currentInputValue: double.tryParse(controller.text),
          onValueUpdated: (double newValue) {
            // 🚨 UPDATE CONTROLLER & TRIGGER DRAFT SAVE
            setState(() {
              controller.text = newValue.toStringAsFixed(2);
            });
            _saveAsDraft();
          },
        ),
      ),
    ).then((_) {
      debugPrint('🔙 Regresaste de la pantalla de gráficos.');
    });
  }

  Map<String, double?> _calculateThreeSigmaRange(List<double> data) {
    if (data.isEmpty) return {'min': null, 'max': null};
    if (data.length == 1) return {'min': data[0], 'max': data[0]}; // Edge case
    
    // Mean (μ)
    double mean = data.reduce((a, b) => a + b) / data.length;
    
    // Variance & Standard Deviation (σ)
    double variance = data.map((x) => pow(x - mean, 2)).reduce((a, b) => a + b) / (data.length - 1); // Sample variance
    double sigma = sqrt(variance);

    return {
      'min': mean - (3 * sigma),
      'max': mean + (3 * sigma),
    };
  }

  Future<void> _guardarMonitoreo() async {
    // 1. Strict Validation
    if (!_isFormularioCompleto) {
      if (_isMonitoreoFallido && _obsController.text.trim().isEmpty) {
        _showError('Debe ingresar una observación explicando por qué falló el monitoreo.');
      } else {
        _showError('Debe seleccionar Programa, Punto de Control e Inspector para guardar.');
      }
      return;
    }

    // 2. Proceed with Final Save
    setState(() => _isSaving = true);
    try {
      await _guardarInterno(isDraft: false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Monitoreo guardado exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pushReplacementNamed(context, '/monitoreos');
      }
    } catch (e) {
      if (mounted) _showError('Error al guardar: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvoked: (bool didPop) async {
        if (didPop) return;
        await _saveAsDraft();
        if (context.mounted) {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          } else {
            Navigator.pushReplacementNamed(context, '/monitoreos');
          }
        }
      },
      child: Scaffold(

      appBar: AppBar(
        title: const Text('Registrar Monitoreo'),
        actions: [IconButton(icon: const Icon(Icons.more_vert), onPressed: () {})],
      ),
      drawer: const AppDrawer(currentRoute: '/registrar_monitoreo'),
      body: ListView(
        children: [
          // --- SECCIÓN 1: DATOS DE MONITOREO ---
          if (_isMonitoreoFallido) ...[
            Container(
              color: const Color(0xFFFF4B61), 
              child: ListTile(
                leading: const Icon(Icons.assignment_outlined, size: 28, color: Colors.white),
                title: const Text('Datos de Monitoreo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.white)),
              ),
            ),
            _buildFormularioDatosMonitoreo(isDarkMode),
          ] else
            _buildSectionTile(
              'Datos de Monitoreo',
              isDarkMode,
              _isDatosMonitoreoComplete,
              [_buildFormularioDatosMonitoreo(isDarkMode)],
            ),

          // --- SECCIÓN 1.5: NIVEL FREÁTICO (Condicional) ---
          if ((_matrizSeleccionada?.nombreMatriz.toLowerCase().contains('subterránea') ?? false) && !_isMonitoreoFallido)
            _buildSectionTile(
              'Nivel Freático',
              isDarkMode,
              _equipoNivelSeleccionado != null && _tipoNivelPozoSeleccionado != null && _nivelTerrenoController.text.isNotEmpty && _fechaYHoraNivel != null,
              [
                SearchableDropdown(
                  label: 'Equipo Nivel',
                  hintText: 'Seleccione equipo de nivel',
                  searchHintText: 'Buscar equipo...',
                  selectedValue: _equipoNivelSeleccionado,
                  options: _equiposMultiOptions,
                  isDarkMode: isDarkMode,
                  onChanged: (val) => setState(() => _equipoNivelSeleccionado = val),
                ),
                SearchableDropdown(
                  label: 'Tipo / Nivel Pozo',
                  hintText: 'Seleccione tipo de pozo',
                  searchHintText: 'Buscar tipo...',
                  selectedValue: _tipoNivelPozoSeleccionado,
                  options: const ['Pozo Monitoreo', 'Pozo Producción', 'Cisterna', 'Otro'],
                  isDarkMode: isDarkMode,
                  onChanged: (val) => setState(() => _tipoNivelPozoSeleccionado = val),
                ),
                CustomParametroInputRow(
                  label: 'Nivel Terreno [m.bnb]',
                  hintText: 'Ingrese nivel terreno',
                  isDarkMode: isDarkMode,
                  controller: _nivelTerrenoController,
                  parameterKey: 'nivel',
                  selectedEstacion: _estacionSeleccionada?.name ?? '',
                  hasHistory: _hasHistory,
                  minAllowed: _parameterRanges['nivel']?['min'],
                  maxAllowed: _parameterRanges['nivel']?['max'],
                  onPulseTap: () => _navigateToChart('nivel', _nivelTerrenoController),
                ),
                CustomFormRow(
                  label: 'Hora Medición - Nivel',
                  value: _fechaYHoraNivel == null ? 'Seleccione Hora y Fecha' : _formatearFechaYHora(_fechaYHoraNivel!),
                  isValid: _fechaYHoraNivel != null,
                  showArrow: false,
                  isDarkMode: isDarkMode,
                  onTap: () async {
                    final DateTime? fecha = await showDatePicker(
                      context: context, initialDate: _fechaYHoraNivel ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100)
                    );
                    if (!mounted || fecha == null) return;
                    final TimeOfDay? hora = await showTimePicker(
                      context: context, initialTime: _fechaYHoraNivel != null ? TimeOfDay.fromDateTime(_fechaYHoraNivel!) : TimeOfDay.now()
                    );
                    if (!mounted || hora == null) return;
                    setState(() => _fechaYHoraNivel = DateTime(fecha.year, fecha.month, fecha.day, hora.hour, hora.minute));
                  },
                ),
                const SizedBox(height: 16),
              ],
              leadingIcon: Icons.water_drop,
            ),

          // --- SECCIONES INFERIORES (Se ocultan si falla el monitoreo) ---
          if (!_isMonitoreoFallido) ...[
            
            // --- SECCIÓN 2: MULTIPARÁMETRO ---
            _buildSectionTile('Multiparámetro', isDarkMode, _isMultiparametroComplete, [
              SearchableDropdown(
                label: 'Equipo Multiparametro',
                hintText: 'Seleccione equipo',
                searchHintText: 'Buscar equipo...',
                selectedValue: _equipoMultiparametroSeleccionado,
                options: _equiposMultiOptions,
                isDarkMode: isDarkMode,
                onChanged: (val) => setState(() => _equipoMultiparametroSeleccionado = val),
              ),
              if (_equipoMultiparametroSeleccionado != null) ...[
                CustomParametroInputRow(label: 'Temperatura [°C]', hintText: 'Ingrese Temperatura', isDarkMode: isDarkMode, controller: _tempController, parameterKey: 'temperatura', selectedEstacion: _estacionSeleccionada?.name ?? '', hasHistory: _hasHistory, minAllowed: _parameterRanges['temperatura']?['min'], maxAllowed: _parameterRanges['temperatura']?['max'], onPulseTap: () => _navigateToChart('temperatura', _tempController)),
                CustomParametroInputRow(label: 'pH [u.pH]', hintText: 'Ingrese pH', isDarkMode: isDarkMode, controller: _phController, parameterKey: 'ph', selectedEstacion: _estacionSeleccionada?.name ?? '', hasHistory: _hasHistory, minAllowed: _parameterRanges['ph']?['min'], maxAllowed: _parameterRanges['ph']?['max'], onPulseTap: () => _navigateToChart('ph', _phController)),
                CustomParametroInputRow(label: 'Conductividad [µS/cm]', hintText: 'Ingrese conductividad', isDarkMode: isDarkMode, controller: _condController, parameterKey: 'conductividad', selectedEstacion: _estacionSeleccionada?.name ?? '', hasHistory: _hasHistory, minAllowed: _parameterRanges['conductividad']?['min'], maxAllowed: _parameterRanges['conductividad']?['max'], onPulseTap: () => _navigateToChart('conductividad', _condController)),
                CustomParametroInputRow(label: 'Oxigeno Disuelto [mg/l]', hintText: 'Ingrese oxigeno disuelto', isDarkMode: isDarkMode, controller: _oxigenoController, parameterKey: 'oxigeno', selectedEstacion: _estacionSeleccionada?.name ?? '', hasHistory: _hasHistory, minAllowed: _parameterRanges['oxigeno']?['min'], maxAllowed: _parameterRanges['oxigeno']?['max'], onPulseTap: () => _navigateToChart('oxigeno', _oxigenoController)),
                _buildEquipmentPhotoFullPreview(
                  title: 'EVIDENCIA MULTIPARÁMETRO',
                  path: _fotoMultiparametroPath,
                  isProcessing: _isProcessingMulti,
                  onTomarFoto: _tomarFotoMultiparametro,
                  onClear: () => setState(() => _fotoMultiparametroPath = null),
                  onVerificar: () => _sharePhoto(_fotoMultiparametroPath!),
                  isDarkMode: isDarkMode,
                ),
              ],
              const SizedBox(height: 16),
            ]),

            // --- SECCIÓN 3: TURBIEDAD ---
            _buildSectionTile('Turbiedad', isDarkMode, _isTurbiedadComplete, [
              SearchableDropdown(
                label: 'Turbidimetro',
                hintText: 'Seleccione equipo',
                searchHintText: 'Buscar equipo...',
                selectedValue: _turbidimetroSeleccionado,
                options: _turbidimetrosOptions,
                isDarkMode: isDarkMode,
                onChanged: (val) => setState(() => _turbidimetroSeleccionado = val),
              ),
              if (_turbidimetroSeleccionado != null) ...[
                CustomParametroInputRow(
                  label: 'Turbiedad [NTU]',
                  hintText: 'Ingrese turbiedad',
                  isDarkMode: isDarkMode,
                  controller: _turbiedadController,
                  parameterKey: 'turbiedad',
                  selectedEstacion: _estacionSeleccionada?.name ?? '',
                  hasHistory: _hasHistory,
                  minAllowed: _parameterRanges['turbiedad']?['min'],
                  maxAllowed: _parameterRanges['turbiedad']?['max'],
                  showPulseIcon: false, // 🚨 Hide the chart icon
                  bypassValidation: true, // 🚨 CRITICAL: Force green check for valid numbers
                  onPulseTap: () => _navigateToChart('turbiedad', _turbiedadController),
                ),
                _buildEquipmentPhotoFullPreview(
                  title: 'EVIDENCIA TURBIEDAD',
                  path: _fotoTurbiedadPath,
                  isProcessing: _isProcessingTurb,
                  onTomarFoto: _tomarFotoTurbiedad,
                  onClear: () => setState(() => _fotoTurbiedadPath = null),
                  onVerificar: () => _sharePhoto(_fotoTurbiedadPath!),
                  isDarkMode: isDarkMode,
                ),
              ],
              const SizedBox(height: 16),
            ]),
            
            // --- SECCIÓN 4: MUESTREO ---
            _buildSectionTile('Muestreo', isDarkMode, _isMuestreoComplete, [
              SearchableDropdown(
                label: 'Método de Muestreo',
                hintText: 'Seleccione método de muestreo',
                searchHintText: 'Buscar método...',
                selectedValue: _metodoSeleccionado?.metodo,
                options: _metodos.map((m) => m.metodo).toList(),
                isDarkMode: isDarkMode,
                onChanged: (val) {
                  setState(() => _metodoSeleccionado = _metodos.firstWhere((m) => m.metodo == val));
                },
              ),
              CustomFormRow(
                label: 'Muestreo Hidroquímico', 
                value: _muestreoHidroquimico == null ? '[Si Aplica]' : (_muestreoHidroquimico! ? 'SI' : 'NO'), 
                isValid: _muestreoHidroquimico != null,
                isDarkMode: isDarkMode,
                onTap: () async {
                  final result = await _mostrarDialogoSiNo('Muestreo Hidroquímico', _muestreoHidroquimico);
                  if (mounted && result != null) setState(() => _muestreoHidroquimico = result);
                }
              ),
              CustomFormRow(
                label: 'Muestreo Isotópico', 
                value: _muestreoIsotopico == null ? '[Si Aplica]' : (_muestreoIsotopico! ? 'SI' : 'NO'), 
                isValid: _muestreoIsotopico != null,
                isDarkMode: isDarkMode,
                onTap: () async {
                  final result = await _mostrarDialogoSiNo('Muestreo Isotópico', _muestreoIsotopico);
                  if (mounted && result != null) setState(() => _muestreoIsotopico = result);
                }
              ),
              // REACTIVE Código Laboratorio
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _codLabController,
                builder: (context, value, child) {
                  final bool hasText = value.text.trim().isNotEmpty;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(
                          hasText ? Icons.check_circle : Icons.cancel,
                          color: hasText ? Colors.green : Colors.grey,
                          size: 24,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _codLabController,
                            maxLines: 1,
                            style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
                            decoration: InputDecoration(
                              labelText: 'Código Laboratorio',
                              hintText: 'Ingrese código de laboratorio',
                              labelStyle: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 13),
                              hintStyle: TextStyle(color: isDarkMode ? Colors.grey[400] : Colors.grey[600], fontSize: 14),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const Divider(height: 1),
              const SizedBox(height: 16),
              // REACTIVE Descripción / Observación
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _obsController,
                builder: (context, value, child) {
                  final bool hasText = value.text.trim().isNotEmpty;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Icon(
                            hasText ? Icons.check_circle : Icons.chat_bubble_outline,
                            color: hasText ? Colors.green : Colors.grey,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _obsController,
                            maxLines: 2,
                            style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
                            decoration: InputDecoration(
                              labelText: 'Descripción / Observación',
                              hintText: 'Ingrese observación / descripción',
                              labelStyle: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 13),
                              hintStyle: TextStyle(color: isDarkMode ? Colors.grey[400] : Colors.grey[600], fontSize: 14),
                              border: InputBorder.none,
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
            ]),
            const SizedBox(height: 16),
          ],

          // --- 5. BOTÓN DE GUARDAR ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
            child: OutlinedButton.icon(
              onPressed: _isSaving ? null : _guardarMonitoreo,
              icon: _isSaving 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined, color: Colors.blueAccent),
              label: Text(_isSaving ? 'GUARDANDO...' : 'GUARDAR', style: const TextStyle(color: Colors.blueAccent, fontSize: 16, letterSpacing: 1.2, fontWeight: FontWeight.w500)),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.blueAccent, width: 1.5), 
                padding: const EdgeInsets.symmetric(vertical: 16.0), 
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
              ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    ),
  );
}

  // --- MÉTODOS Y HELPERS ---

  Widget _buildFormularioDatosMonitoreo(bool isDarkMode) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor, 
      child: Column(
        children: [
          SearchableDropdown(
            label: 'Programa',
            hintText: 'Seleccione programa',
            searchHintText: 'Buscar programa...',
            selectedValue: _programaSeleccionado?.name,
            options: _programas.map((p) => p.name).toList(),
            isDarkMode: isDarkMode,
            onChanged: _onProgramaChanged,
          ),

          SearchableDropdown(
            label: 'Punto de Control',
            hintText: 'Seleccione estación',
            searchHintText: 'Buscar estación...',
            selectedValue: _estacionSeleccionada?.name,
            options: _estaciones.map((s) => s.name).toList(),
            isDarkMode: isDarkMode,
            onChanged: _onStationChanged,
          ),
          
          SearchableDropdown(
            label: 'Inspector',
            hintText: 'Seleccione inspector',
            searchHintText: 'Buscar inspector...',
            selectedValue: _inspectorSeleccionado,
            options: _inspectoresOptions,
            isDarkMode: isDarkMode,
            onChanged: (val) {
              setState(() => _inspectorSeleccionado = val);
              _saveAsDraft();
            },
          ),
          
          SearchableDropdown(
            label: 'Matriz de Aguas',
            hintText: 'Seleccione Tipo de Aguas',
            searchHintText: 'Buscar tipo de agua...',
            selectedValue: _matrizSeleccionada?.nombreMatriz,
            options: _matrices.map((m) => m.nombreMatriz).toList(),
            isDarkMode: isDarkMode,
            onChanged: (val) {
              setState(() => _matrizSeleccionada = _matrices.firstWhere((m) => m.nombreMatriz == val));
              _saveAsDraft();
            },
          ),
          
          CustomFormRow(
            label: 'Hora y Fecha de Muestreo', 
            value: _fechaYHoraMuestreo == null ? 'Seleccione Hora y Fecha' : _formatearFechaYHora(_fechaYHoraMuestreo!), 
            isValid: _fechaYHoraMuestreo != null, 
            showArrow: false,
            isDarkMode: isDarkMode,
            onTap: _seleccionarFechaYHora, 
          ),
          
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: CustomParametroInputRow(
              label: 'Profundidad de muestreo [m]', 
              hintText: 'Ingrese profundidad', 
              isDarkMode: isDarkMode, 
              controller: _profundidadController,
              parameterKey: 'profundidad',
              selectedEstacion: _estacionSeleccionada?.name ?? '',
              showLeadingIcon: true,
              showPulseIcon: false,
              isMandatory: true,
              hasHistory: _hasHistory,
              minAllowed: _parameterRanges['profundidad']?['min'],
              maxAllowed: _parameterRanges['profundidad']?['max'],
              bypassValidation: true, // 🚨 CRITICAL: Force green check for valid numbers
            ),
          ),
          
          CustomFormRow(
            label: 'Monitoreo Fallido',
            value: _isMonitoreoFallido ? 'SI' : 'NO',
            isValid: !_isMonitoreoFallido,
            customIcon: _isMonitoreoFallido ? Icons.error : Icons.check_circle,
            customIconColor: _isMonitoreoFallido ? const Color(0xFFFF4B61) : Colors.greenAccent,
            isDarkMode: isDarkMode,
            onTap: () async {
              final result = await _mostrarDialogoSiNo('Monitoreo Fallido', _isMonitoreoFallido);
              if (mounted && result != null) setState(() => _isMonitoreoFallido = result);
            },
          ),

          if (_isMonitoreoFallido)
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _obsController,
            builder: (context, value, child) {
              final bool hasText = value.text.trim().isNotEmpty;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Icon(
                        hasText ? Icons.check_circle : Icons.chat_bubble_outline,
                        color: hasText ? Colors.green : Colors.grey,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _obsController,
                        maxLines: 2,
                        style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
                        decoration: InputDecoration(
                          labelText: 'Descripción / Observación',
                          hintText: 'Ingrese observación / descripción',
                          labelStyle: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 13),
                          hintStyle: TextStyle(color: isDarkMode ? Colors.grey[400] : Colors.grey[600], fontSize: 14),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
            ),
          
          _buildPhotoPreview(isDarkMode),
          
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildPhotoPreview(bool isDarkMode) {
    if (_isProcessingImage) {
      return Container(
        height: 200,
        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.grey[900] : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(strokeWidth: 3, color: Colors.blueAccent),
            const SizedBox(height: 20),
            Text(
              "CALIBRANDO RESOLUCIÓN ORIGINAL...",
              style: TextStyle(
                color: Colors.blueAccent.withOpacity(0.8),
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "ELIMINANDO DESBORDAMIENTOS",
              style: TextStyle(
                color: Colors.grey.withOpacity(0.6),
                fontSize: 9,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      );
    }

    if (_imagePath == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _pickImage(ImageSource.camera),
            icon: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
            label: const Text("CAPTURAR RESPALDO FOTOGRÁFICO", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "EVIDENCIA CAPTURADA",
              style: TextStyle(color: Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1),
            ),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 4 / 3,
              child: Stack(
                alignment: Alignment.topRight,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12.0),
                    child: Image.file(
                      File(_imagePath!),
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: GestureDetector(
                      onTap: _removeImage,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: () => _pickImage(ImageSource.camera),
                    icon: const Icon(Icons.refresh, color: Colors.blueAccent, size: 16),
                    label: const Text("RECAPTURAR", style: TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 16),
                  TextButton.icon(
                    onPressed: () => _sharePhoto(_imagePath!),
                    icon: const Icon(Icons.share, color: Colors.green, size: 16),
                    label: const Text("VERIFICAR", style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
  }

  Future<Position?> _getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Los servicios de ubicación están desactivados.')),
        );
      }
      return null;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permisos de ubicación denegados.')),
          );
        }
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permisos de ubicación denegados permanentemente.')),
        );
      }
      return null;
    }

    return await Geolocator.getCurrentPosition();
  }

  Future<void> _pickImage(ImageSource source, {String target = 'general'}) async {
    if (source != ImageSource.camera) return;

    try {
      final XFile? pickerImage = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );

      if (pickerImage != null) {
        Position? position = await _getCurrentLocation();
        if (position != null) {
          await _processImageWithStamp(File(pickerImage.path), position, target: target);
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Se requiere GPS para estampar la fotografía.')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al capturar foto: $e')),
        );
      }
    }
  }

  Future<void> _tomarFotoMultiparametro() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      Position? position = await _getCurrentLocation();
      if (position != null) {
        await _processImageWithStamp(File(image.path), position, target: 'multi');
      } else {
        setState(() => _fotoMultiparametroPath = image.path);
      }
    }
  }

  Future<void> _tomarFotoTurbiedad() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      Position? position = await _getCurrentLocation();
      if (position != null) {
        await _processImageWithStamp(File(image.path), position, target: 'turb');
      } else {
        setState(() => _fotoTurbiedadPath = image.path);
      }
    }
  }

  Future<void> _processImageWithStamp(File imageFile, Position position, {String target = 'general'}) async {
    if (target == 'general') setState(() => _isProcessingImage = true);
    else if (target == 'multi') setState(() => _isProcessingMulti = true);
    else if (target == 'turb') setState(() => _isProcessingTurb = true);

    try {
      final String timestamp = _formatearFechaYHora(DateTime.now());
      final String lat = position.latitude.toStringAsFixed(6);
      final String lon = position.longitude.toStringAsFixed(6);
      final String estacion = (_estacionSeleccionada?.name ?? "PUNTO DE CONTROL NO ESPECIFICADO").toUpperCase();

      final Uint8List mainBytes = await imageFile.readAsBytes();
      final ui.Codec codec = await ui.instantiateImageCodec(mainBytes);
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      final double imgWidth = frameInfo.image.width.toDouble();
      final double imgHeight = frameInfo.image.height.toDouble();

      final ByteData data = await rootBundle.load('assets/gp-blanco-centrado.png');
      final Uint8List logoBytes = data.buffer.asUint8List();

      final double dynamicFontSize = imgWidth * 0.02;
      final double bannerHeight = imgHeight * 0.12;
      final double logoSize = imgWidth * 0.20;
      final double margin = imgWidth * 0.04;

      final stampWidget = Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: imgWidth,
          height: imgHeight,
          child: Stack(
            children: [
              Image.memory(
                mainBytes,
                width: imgWidth,
                height: imgHeight,
                fit: BoxFit.cover,
              ),
              Positioned(
                top: margin,
                left: margin,
                child: SizedBox(
                  width: logoSize,
                  height: logoSize,
                  child: Image.memory(
                    logoBytes,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: bannerHeight,
                  width: imgWidth,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.85),
                      ],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        estacion,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: dynamicFontSize * 1.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          shadows: const [Shadow(blurRadius: 10, color: Colors.black)],
                          decoration: TextDecoration.none,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: bannerHeight * 0.08),
                      Text(
                        "Lat: $lat | Long: $lon",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: dynamicFontSize,
                          fontWeight: FontWeight.w500,
                          shadows: const [Shadow(blurRadius: 5, color: Colors.black)],
                          decoration: TextDecoration.none,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: bannerHeight * 0.04),
                      Text(
                        timestamp,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: dynamicFontSize * 0.8,
                          fontWeight: FontWeight.w400,
                          decoration: TextDecoration.none,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );

      final Uint8List stampedBytes = await _screenshotController.captureFromWidget(
        stampWidget,
        delay: const Duration(milliseconds: 500),
        pixelRatio: 1.0, 
        targetSize: Size(imgWidth, imgHeight),
      );

      final directory = await getApplicationDocumentsDirectory();
      final String fileName = 'EVIDENCIA_TECNICA_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final String filePath = p.join(directory.path, fileName);
      
      final File processedFile = File(filePath);
      await processedFile.writeAsBytes(stampedBytes);

      setState(() {
        if (target == 'general') _imagePath = filePath;
        else if (target == 'multi') _fotoMultiparametroPath = filePath;
        else if (target == 'turb') _fotoTurbiedadPath = filePath;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessingImage = false;
          _isProcessingMulti = false;
          _isProcessingTurb = false;
        });
      }
    }
  }

  void _removeImage() {
    setState(() => _imagePath = null);
  }

  Future<void> _sharePhoto(String path) async {
    try {
      final XFile file = XFile(path);
      await Share.shareXFiles([file], text: 'EVIDENCIA MONITOREO - ${_estacionSeleccionada?.name ?? "PTO"}');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Widget _buildEquipmentPhotoFullPreview({
    required String title,
    required String? path,
    required bool isProcessing,
    required VoidCallback onTomarFoto,
    required VoidCallback onClear,
    required VoidCallback onVerificar,
    required bool isDarkMode,
  }) {
    if (isProcessing) {
      return Container(
        height: 200,
        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.grey[900] : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(strokeWidth: 3, color: Colors.blueAccent),
            const SizedBox(height: 20),
            const Text(
              "CALIBRANDO RESOLUCIÓN ORIGINAL...",
              style: TextStyle(
                color: Colors.blueAccent,
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "ELIMINANDO DESBORDAMIENTOS",
              style: TextStyle(
                color: Colors.grey.withOpacity(0.6),
                fontSize: 9,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      );
    }

    if (path == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: onTomarFoto,
            icon: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
            label: const Text("CAPTURAR RESPALDO FOTOGRÁFICO", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              padding: const EdgeInsets.symmetric(vertical: 14),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(color: Colors.blueAccent, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.1),
            ),
            const SizedBox(height: 12),
            AspectRatio(
              aspectRatio: 4 / 3,
              child: Stack(
                alignment: Alignment.topRight,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12.0),
                    child: Image.file(
                      File(path),
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: GestureDetector(
                      onTap: onClear,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, color: Colors.white, size: 18),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: onTomarFoto,
                    icon: const Icon(Icons.refresh, color: Colors.blueAccent, size: 16),
                    label: const Text("RECAPTURAR", style: TextStyle(color: Colors.blueAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 16),
                  TextButton.icon(
                    onPressed: onVerificar,
                    icon: const Icon(Icons.share, color: Colors.green, size: 16),
                    label: const Text("VERIFICAR", style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
  }

  void _showPickImageOptions() {
    _pickImage(ImageSource.camera);
  }

  Widget _buildSectionTile(String title, bool isDarkMode, bool isComplete, List<Widget> children, {IconData leadingIcon = Icons.assignment_outlined}) {
    return ExpansionTile(
      initiallyExpanded: true,
      iconColor: Colors.blueAccent,
      collapsedIconColor: Colors.blueAccent,
      leading: SizedBox(
        width: 48, 
        child: Align(
          alignment: Alignment.centerLeft, 
          child: Icon(leadingIcon, size: 28, color: Colors.blueAccent)
        ),
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          if (isComplete) ...[
            const SizedBox(width: 8),
            const Icon(Icons.check_circle, color: Colors.green, size: 20),
          ],
        ],
      ),
      children: [
        Container(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Column(children: children),
        )
      ],
    );
  }

  Future<void> _seleccionarFechaYHora() async {
    final DateTime? fecha = await showDatePicker(
      context: context, initialDate: _fechaYHoraMuestreo ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100)
    );
    if (!mounted || fecha == null) return;

    final TimeOfDay? hora = await showTimePicker(
      context: context, initialTime: _fechaYHoraMuestreo != null ? TimeOfDay.fromDateTime(_fechaYHoraMuestreo!) : TimeOfDay.now()
    );
    if (!mounted || hora == null) return;

    setState(() => _fechaYHoraMuestreo = DateTime(fecha.year, fecha.month, fecha.day, hora.hour, hora.minute));
  }

  String _formatearFechaYHora(DateTime f) => '${f.day.toString().padLeft(2,'0')}/${f.month.toString().padLeft(2,'0')}/${f.year} ${f.hour.toString().padLeft(2,'0')}:${f.minute.toString().padLeft(2,'0')}';

  Future<bool?> _mostrarDialogoSiNo(String titulo, bool? valorActual) async {
    bool? tempValue = valorActual;
    return await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(titulo),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<bool>(title: const Text('NO'), value: false, groupValue: tempValue, onChanged: (v) => setStateDialog(() => tempValue = v)),
              RadioListTile<bool>(title: const Text('SI'), value: true, groupValue: tempValue, onChanged: (v) => setStateDialog(() => tempValue = v)),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR', style: TextStyle(color: Colors.blueAccent))),
            TextButton(onPressed: () => Navigator.pop(context, tempValue), child: const Text('OK', style: TextStyle(color: Colors.blueAccent))),
          ],
        ),
      ),
    );
  }
}

// ===================================
// TOP-LEVEL HELPER WIDGETS
// ===================================

class SearchableDropdown extends StatefulWidget {
  final String label;
  final String hintText;
  final String? searchHintText;
  final String? selectedValue;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final bool isDarkMode;
  final IconData? customIcon;
  final Color? customIconColor;
  final bool showArrow;

  const SearchableDropdown({
    super.key,
    required this.label,
    required this.hintText,
    this.searchHintText,
    required this.selectedValue,
    required this.options,
    required this.onChanged,
    required this.isDarkMode,
    this.customIcon,
    this.customIconColor,
    this.showArrow = true,
  });

  @override
  State<SearchableDropdown> createState() => _SearchableDropdownState();
}

class _SearchableDropdownState extends State<SearchableDropdown> {
  bool _isExpanded = false;
  final TextEditingController _searchController = TextEditingController();
  late List<String> _filteredOptions;

  @override
  void initState() {
    super.initState();
    _filteredOptions = widget.options;
    _searchController.addListener(() {
      setState(() => _filteredOptions = widget.options.where((o) => o.toLowerCase().contains(_searchController.text.toLowerCase())).toList());
    });
  }
  
  @override
  void didUpdateWidget(SearchableDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.options != widget.options) {
      _filteredOptions = widget.options;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CustomFormRow(
          label: widget.label,
          value: widget.selectedValue ?? widget.hintText,
          isValid: widget.selectedValue != null,
          isDarkMode: widget.isDarkMode,
          customIcon: widget.customIcon,
          customIconColor: widget.customIconColor,
          showArrow: widget.showArrow,
          onTap: () {
            setState(() {
              _isExpanded = !_isExpanded;
              if (!_isExpanded) _searchController.clear();
            });
          }
        ),
        if (_isExpanded)
          Container(
            color: widget.isDarkMode ? Colors.grey.shade900 : const Color(0xFFF5F5F5),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 8.0),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: widget.searchHintText ?? 'Buscar...',
                      hintStyle: TextStyle(color: widget.isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600),
                      prefixIcon: Icon(Icons.search, size: 20, color: widget.isDarkMode ? Colors.white70 : Colors.grey.shade800),
                      isDense: true, contentPadding: const EdgeInsets.symmetric(vertical: 8.0),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0), borderSide: BorderSide(color: widget.isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8.0), borderSide: BorderSide(color: widget.isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300)),
                    ),
                    style: TextStyle(fontSize: 14, color: widget.isDarkMode ? Colors.white : Colors.grey.shade800),
                  ),
                ),
                SizedBox(
                  height: _filteredOptions.length > 3 ? 160 : (_filteredOptions.length * 40.0), 
                  child: ListView.builder(
                    padding: EdgeInsets.zero, itemExtent: 40.0, itemCount: _filteredOptions.length,
                    itemBuilder: (context, index) {
                      final opcion = _filteredOptions[index];
                      final isSelected = widget.selectedValue == opcion;
                      return InkWell(
                        onTap: () {
                          widget.onChanged(opcion);
                          setState(() { _isExpanded = false; _searchController.clear(); });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0), alignment: Alignment.centerLeft,
                          color: isSelected ? Colors.blueAccent.withValues(alpha: 0.15) : Colors.transparent,
                          child: Text(opcion, style: TextStyle(fontSize: 14, color: isSelected ? Colors.blueAccent : (widget.isDarkMode ? Colors.white : Colors.grey.shade800), fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class CustomFormRow extends StatelessWidget {
  final String label, value;
  final bool isValid, isDarkMode, showArrow;
  final IconData? customIcon;
  final Color? customIconColor;
  final VoidCallback? onTap;

  const CustomFormRow({super.key, required this.label, required this.value, required this.isValid, required this.isDarkMode, this.showArrow = true, this.customIcon, this.customIconColor, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorGris = isDarkMode ? Colors.grey.shade400 : Colors.black54;
    return ListTile(
      leading: SizedBox(
        width: 32,
        child: Icon(
          customIcon ?? (isValid ? Icons.check_circle : Icons.cancel), 
          color: customIconColor ?? (isValid ? Colors.greenAccent : (isDarkMode ? Colors.grey.shade700 : Colors.grey.shade400)), 
          size: 22
        ),
      ),
      title: Text(label, style: const TextStyle(color: Colors.blueAccent, fontSize: 12)),
      subtitle: Text(value, style: TextStyle(fontSize: 16, color: (isValid || customIcon != null) ? Theme.of(context).colorScheme.onSurface : colorGris)),
      trailing: showArrow ? Icon(Icons.arrow_drop_down, color: colorGris) : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 0.0), dense: true,
      onTap: onTap ?? () => debugPrint('Tapped on $label'),
    );
  }
}

class CustomParametroInputRow extends StatefulWidget {
  final String label;
  final String hintText;
  final bool isDarkMode;
  final TextEditingController controller;
  final bool showPulseIcon;
  final bool showLeadingIcon;
  final bool isMandatory;
  final double? minAllowed;
  final double? maxAllowed;
  final bool hasHistory;
  final VoidCallback? onPulseTap; // Added for state persistence before navigation

  final String parameterKey; // e.g., 'nivel', 'ph', 'temperatura'
  final String selectedEstacion;
  final bool bypassValidation; // 🚨 NEW

  const CustomParametroInputRow({
    super.key,
    required this.label,
    required this.hintText,
    required this.isDarkMode,
    required this.controller,
    required this.parameterKey,
    required this.selectedEstacion,
    this.showPulseIcon = true,
    this.showLeadingIcon = true,
    this.isMandatory = true,
    this.minAllowed,
    this.maxAllowed,
    this.hasHistory = false,
    this.onPulseTap,
    this.bypassValidation = false, // Default to false to keep standard behavior
  });

  @override
  State<CustomParametroInputRow> createState() => _CustomParametroInputRowState();
}

class _CustomParametroInputRowState extends State<CustomParametroInputRow> {
  bool _isValidated = false;
  bool _isOutOfRange = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_validate);
    _validate();
  }

  @override
  void didUpdateWidget(CustomParametroInputRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.minAllowed != widget.minAllowed || 
        oldWidget.maxAllowed != widget.maxAllowed || 
        oldWidget.hasHistory != widget.hasHistory) {
      _validate();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_validate);
    super.dispose();
  }

  void _validate() {
    final String text = widget.controller.text;
    final double? val = double.tryParse(text);

    // 1. Empty or invalid number -> Grey state
    if (text.isEmpty || val == null) {
      setState(() {
        _isValidated = false;
        _isOutOfRange = false;
      });
      return;
    }

    // 🚨 2. BYPASS LOGIC: If flagged, any valid number gets a green check immediately.
    if (widget.bypassValidation) {
      setState(() {
        _isValidated = true;
        _isOutOfRange = false;
      });
      return;
    }

    // 3. STRICT RULE: If NO history exists, it is an ANOMALY by default (Red)
    if (!widget.hasHistory || widget.minAllowed == null || widget.maxAllowed == null) {
      setState(() {
        _isValidated = false; // NO Green Check
        _isOutOfRange = true; // Force Red State
      });
      return;
    }

    // 4. 3-Sigma Rule: Check bounds
    bool isOut = val < widget.minAllowed! || val > widget.maxAllowed!;
    
    setState(() {
      _isValidated = !isOut;
      _isOutOfRange = isOut;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Icono Indicador
          if (widget.showLeadingIcon)
            Icon(
              _isValidated ? Icons.check_circle : (_isOutOfRange ? Icons.error : Icons.cancel), 
              color: _isValidated ? Colors.greenAccent : (_isOutOfRange ? Colors.redAccent : (widget.isDarkMode ? Colors.grey.shade700 : Colors.grey.shade400)), 
              size: 24
            ),
          
          const SizedBox(width: 16),
          
          // Input Field (Exact UI Match)
          Expanded(
            child: TextField(
              controller: widget.controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (val) => widget.onPulseTap != null ? null : setState(() {}),
              style: TextStyle(color: widget.isDarkMode ? Colors.white : Colors.black),
              decoration: InputDecoration(
                labelText: widget.label, // Floating label inside the field
                hintText: widget.hintText,
                labelStyle: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 13),
                hintStyle: TextStyle(color: widget.isDarkMode ? Colors.grey[400] : Colors.grey[600], fontSize: 14),
                border: InputBorder.none,
                isDense: true,
                errorText: _isOutOfRange 
                    ? (!widget.hasHistory || widget.minAllowed == null 
                        ? 'Anómalo: Sin historial' 
                        : 'Anómalo: Fuera de rango') 
                    : null,
                errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          
          // Icono de Pulso (Gráfico)
          if (widget.showPulseIcon)
            GestureDetector(
              onTap: widget.onPulseTap,
              child: Container(
                margin: const EdgeInsets.only(left: 8.0),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.blueAccent, width: 1.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.monitor_heart_outlined, 
                  color: Colors.blueAccent, 
                  size: 20
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class CustomTextInputRow extends StatelessWidget {
  final String label, hintText;
  final bool isDarkMode;
  final int? maxLines;
  final TextEditingController controller;
  final bool isMandatory;
  final bool showLeadingIcon;

  const CustomTextInputRow({
    super.key, 
    required this.label, 
    required this.hintText, 
    required this.isDarkMode, 
    this.maxLines = 1, 
    required this.controller,
    this.isMandatory = true,
    this.showLeadingIcon = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 0.0),
      dense: true,
      leading: SizedBox(
        width: 32,
        child: showLeadingIcon 
            ? ListenableBuilder(
                listenable: controller,
                builder: (context, _) {
                  final bool isCompleted = isMandatory && controller.text.isNotEmpty;
                  return Icon(
                    isCompleted ? Icons.check_circle : Icons.cancel, 
                    color: isCompleted ? Colors.greenAccent : (isDarkMode ? Colors.grey.shade700 : Colors.grey.shade400), 
                    size: 22
                  );
                },
              )
            : null,
      ),
      title: Text(label, style: const TextStyle(color: Colors.blueAccent, fontSize: 12)),
      subtitle: TextField(
        controller: controller,
        keyboardType: maxLines == null ? TextInputType.multiline : TextInputType.text, maxLines: maxLines, 
        style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface),
        decoration: InputDecoration(hintText: hintText, hintStyle: TextStyle(color: isDarkMode ? Colors.grey.shade400 : Colors.black54, fontSize: 16), border: InputBorder.none, isDense: true, contentPadding: const EdgeInsets.only(top: 4.0)),
      ),
    );
  }
}