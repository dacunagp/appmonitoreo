import 'dart:typed_data';
import 'dart:convert';
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
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'chart_analysis_screen.dart';

class RegistrarMonitoreoScreen extends StatefulWidget {
  final int? registroId;
  final bool isReadOnly;
  final int? initialProgramId; // Phase 121
  final int? initialStationId; // Phase 121

  const RegistrarMonitoreoScreen({
    super.key, 
    this.registroId, 
    this.isReadOnly = false,
    this.initialProgramId,
    this.initialStationId,
  });

  @override
  State<RegistrarMonitoreoScreen> createState() => _RegistrarMonitoreoScreenState();
}

// Fase 111: Supporting multiple instances of the same parameter
class ParametroInstancia {
  final Parametro parametro;
  final TextEditingController controller;
  final String uniqueId;

  ParametroInstancia({
    required this.parametro,
    required this.controller,
    required this.uniqueId,
  });
}

class _RegistrarMonitoreoScreenState extends State<RegistrarMonitoreoScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  
  // --- 0. CONSTANTES DE DISEÑO (Phase 102) ---
  static const Set<String> _fixedKeys = {'profundidad', 'nivel'};

  // --- 1. VARIABLES DE ESTADO ---
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isMonitoreoFallido = false;
  int? _currentRegistroId;
  Timer? _debounce;
  bool _isProcessingImage = false;
  bool _isProcessingMulti = false;
  bool _isProcessingTurb = false;
  bool _isProcessingCaudal = false;
  bool _isProcessingNivelFreatico = false;
  bool _isProcessingMuestreo = false;
  DateTime? _fechaYHoraMuestreo; 
  String? _imagePath;
  String? _fotoMultiparametroPath;
  String? _fotoTurbiedadPath;
  // Phase 115: New photographic backup paths
  String? _fotoCaudalPath;
  String? _fotoNivelFreaticoPath;
  String? _fotoMuestreoPath;
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
  final TextEditingController _codLabController = TextEditingController();
  final TextEditingController _obsController = TextEditingController();
  
  // DYNAMIC PARAMETER MANAGEMENT (Phase 94)
  final Map<String, TextEditingController> _paramControllers = {};
  Map<String, List<Parametro>> _categorizedParams = {};
  Set<String> _activeParameterKeys = {};
  
  // DYNAMIC PARAMETERS (Phase 103/111/114 Manual Builder)
  List<Parametro> _availableExtraParams = []; // Catalog for manual addition
  List<ParametroInstancia> _selectedAdicionalesInstancias = []; // Phase 114
  List<ParametroInstancia> _selectedMultiInstancias = [];      // Phase 114
  Parametro? _parametroAdicionalSeleccionado;
  Parametro? _parametroMultiDummySeleccionado;
  
  // LEVEL VARIABLES
  String? _equipoNivelSeleccionado;
  String? _tipoNivelPozoSeleccionado;
  DateTime? _fechaYHoraNivel;

  // Phase 115: CAUDAL VARIABLES
  int? _selectedEquipoCaudalId;
  List<EquipoDetalle> _equiposCaudal = [];
  final TextEditingController _caudalController = TextEditingController();
  DateTime? _fechaHoraCaudal;

  // Phase 117: DYNAMIC UNITS FOR VIP FIELDS
  String _unitProfundidad = 'm';
  String _unitNivel = 'm';
  String _unitCaudal = 'L/s';

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
    
    // Phase 114: Check that core parameters exist in _selectedMultiInstancias and are filled
    final coreKeys = ['ph', 'temperatura', 'conductividad', 'oxigeno'];
    for (var key in coreKeys) {
      final hasEntry = _selectedMultiInstancias.any((inst) => 
        inst.parametro.claveInterna == key && inst.controller.text.isNotEmpty);
      if (!hasEntry) return false;
    }
    
    return _fotoMultiparametroPath != null;
  }

  bool get _isTurbiedadComplete {
    if (_turbidimetroSeleccionado == null) return false;
    return (_paramControllers['turbiedad']?.text.isNotEmpty ?? false) && 
           _fotoTurbiedadPath != null;
  }

  bool get _isNivelComplete {
    return _equipoNivelSeleccionado != null && 
           _tipoNivelPozoSeleccionado != null && 
           (_paramControllers['nivel']?.text.isNotEmpty ?? false) && 
           _fechaYHoraNivel != null;
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
    _codLabController.addListener(_onFieldChanged);
    _obsController.addListener(_onFieldChanged);
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
        'turbiedad': double.tryParse(_paramControllers['turbiedad']?.text ?? ''),
        'profundidad': double.tryParse(_paramControllers['profundidad']?.text ?? ''),
        'nivel': double.tryParse(_paramControllers['nivel']?.text ?? ''),
        // Phase 115: Caudal & new photo columns
        'equipo_caudal': _selectedEquipoCaudalId,
        'nivel_caudal': double.tryParse(_caudalController.text.replaceAll(',', '.')),
        'fecha_hora_caudal': _fechaHoraCaudal?.toIso8601String().replaceAll('T', ' ').split('.').first,
        'foto_caudal': _fotoCaudalPath,
        'foto_nivel_freatico': _fotoNivelFreaticoPath,
        'foto_muestreo': _fotoMuestreoPath,
        'is_draft': isDraft ? 1 : 0,
      };

      // CRITICAL FIX: Remove 'id' if null so SQLite auto-increments properly
      if (header['id'] == null) {
        header.remove('id');
      }
      // 2. Build JSON Document (Phase 114 - Dual JSON Serialization)
      final List<Map<String, dynamic>> multiList = [];
      final List<Map<String, dynamic>> adicionalesList = [];

      // A. Process Multiparametros
      for (var inst in _selectedMultiInstancias) {
        if (inst.controller.text.trim().isNotEmpty) {
          multiList.add({
            inst.parametro.claveInterna: double.tryParse(inst.controller.text) ?? inst.controller.text.trim()
          });
        }
      }

      // B. Process Parámetros Adicionales
      for (var inst in _selectedAdicionalesInstancias) {
        if (inst.controller.text.trim().isNotEmpty) {
          adicionalesList.add({
            inst.parametro.claveInterna: double.tryParse(inst.controller.text) ?? inst.controller.text.trim()
          });
        }
      }

      header['multiparametros_json'] = jsonEncode(multiList);
      header['detalles_json'] = jsonEncode(adicionalesList);

      // Legacy support: We send empty list to transaction for local captures 
      // as we are pivoting to Document Pattern.
      List<Map<String, dynamic>> detalles = [];
      

      
      // Cleanup: _selectedAdicionales logic is mostly superseeded by category-based UI
      // but we keep it for backward compat if the user manually added something unconventional.


      // 3. Save via Transaction
      final id = await _dbHelper.saveMonitoreoTransaction(header, detalles);
      
      if (_currentRegistroId == null) {
        setState(() => _currentRegistroId = id);
      }
    } catch (e) {
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
    _codLabController.dispose();
    _obsController.dispose();
    _caudalController.dispose();
    
    for (var controller in _paramControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadDropdownData() async {
    setState(() => _isLoading = true);
    try {
      // 1. Fetch Catalogs (Awaited sequentially)
      final programas = await _dbHelper.getPrograms();
      final matrices = await _dbHelper.getMatrices();
      final metodos = await _dbHelper.getMetodos();
      final usuarios = await _dbHelper.getUsuarios();
      
      final multiData = await _dbHelper.getEquiposByType('Pozómetro');
      var turbiData = await _dbHelper.getEquiposByType('Turbidímetro');
      if (turbiData.isEmpty) {
        turbiData = await _dbHelper.getEquiposByType('Turbidimetro');
      }
      // Phase 115: Fetch Molinete equipment for Caudal section
      var caudalData = await _dbHelper.getEquiposByType('Molinete');

      // 2. Fetch Parameters (Catalog and Active)
      final allParams = await _dbHelper.getParametros();
      final activeParams = await _dbHelper.getActiveParametros();
      
      // Phase 117: Extract units for VIP parameters to avoid hardcoding labels
      try {
        final pProf = allParams.firstWhere((p) => p.claveInterna.toLowerCase() == 'profundidad');
        _unitProfundidad = pProf.unidad;
      } catch (_) {}
      try {
        final pNivel = allParams.firstWhere((p) => p.claveInterna.toLowerCase() == 'nivel');
        _unitNivel = pNivel.unidad;
      } catch (_) {}
      try {
        final pCaudal = allParams.firstWhere((p) => p.claveInterna.toLowerCase() == 'caudal');
        _unitCaudal = pCaudal.unidad;
      } catch (_) {}
      
      // 3. Initialize ALL Controllers FIRST
      final Set<String> activeKeys = activeParams.map((p) => p.claveInterna).toSet();
      final Map<String, List<Parametro>> categorized = {};
      
      for (var p in activeParams) {
        final cat = _getUbicacionParametro(p);
        if (!categorized.containsKey(cat)) {
          categorized[cat] = [];
        }
        categorized[cat]!.add(p);
        
        // Ensure controller exists and has listener pre-instantiated
        if (!_paramControllers.containsKey(p.claveInterna)) {
          final controller = TextEditingController();
          controller.addListener(_onFieldChanged);
          _paramControllers[p.claveInterna] = controller;
        }
      }

      final vipKeysList = ['profundidad', 'nivel', 'turbiedad'];
      final availableExtras = activeParams.where((p) {
        return !vipKeysList.contains(p.claveInterna.toLowerCase());
      }).toList();

      // Apply initial catalogs to state (needed for lookup in _loadExistingData if it uses current state)
      setState(() {
        _programas = programas;
        _matrices = matrices;
        _metodos = metodos;
        _inspectoresOptions = usuarios.map((u) => '${u.nombre} ${u.apellido}').toList();
        _equiposMulti = multiData;
        _equiposMultiOptions = multiData.map((e) => e.codigo.toString()).toList();
        _turbidimetros = turbiData;
        _turbidimetrosOptions = turbiData.map((e) => e.codigo.toString()).toList();
        _equiposCaudal = caudalData; // Phase 115
        _activeParameterKeys = activeKeys;
        _categorizedParams = categorized;
        _availableExtraParams = availableExtras;

        // --- Phase 114: Auto-Populate Base Multiparameters ---
        if (widget.registroId == null && _selectedMultiInstancias.isEmpty) {
          final baseKeys = ['ph', 'temperatura', 'conductividad', 'oxigeno'];
          for (var key in baseKeys) {
            // Check if the base parameter is active before auto-populating
            if (activeKeys.contains(key)) {
              try {
                final p = allParams.firstWhere((param) => param.claveInterna == key);
                final controller = TextEditingController();
                controller.addListener(_onFieldChanged);
                
                _selectedMultiInstancias.add(ParametroInstancia(
                  parametro: p, 
                  controller: controller, 
                  uniqueId: '${key}_initial_${DateTime.now().millisecondsSinceEpoch}'
                ));
              } catch (_) {}
            }
          }
        }
      });

      // --- Phase 121: Handle Pre-selection from Constructor ---
      if (widget.registroId == null) {
        if (widget.initialProgramId != null) {
          try {
            final p = _programas.firstWhere((prog) => prog.id == widget.initialProgramId);
            await _onProgramaChanged(p.name);
            
            if (widget.initialStationId != null && _estaciones.isNotEmpty) {
              try {
                final s = _estaciones.firstWhere((stat) => stat.id == widget.initialStationId);
                await _onStationChanged(s.name);
              } catch (e) {
                debugPrint('⚠️ Error pre-selecting station: $e');
              }
            }
          } catch (e) {
            debugPrint('⚠️ Error pre-selecting program: $e');
          }
        }
      }

      // 4. If Edit Mode, Load Draft Data (Inject text into the controllers we just created)
      if (widget.registroId != null) {
        await _loadExistingData(widget.registroId!);
      }

      // 5. Finalize Loading
      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('🚨 ERROR EN INITIALIZATION: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadExistingData(int id) async {
    final data = await _dbHelper.getRegistroMonitoreoById(id);
    if (data == null) return;

    final allParams = await _dbHelper.getParametros();

    // 1. Fetch Inspector (Synchronous/Awaited for Phase 99)
    String? inspectorName;
    if (data['usuario_id'] != null) {
      try {
        final usuarios = await _dbHelper.getUsuarios();
        final u = usuarios.firstWhere((user) => user.idUsuario == data['usuario_id']);
        inspectorName = '${u.nombre} ${u.apellido}';
      } catch (_) {}
    }

    // 2. Load Details (Phase 114 - Dual JSON Deserialization)
    final List<ParametroInstancia> multiToLoad = [];
    final List<ParametroInstancia> adicionalesToLoad = [];
    final Map<String, String> legacyValues = {};

    // A. Parse Multiparametros JSON (New Format)
    if (data['multiparametros_json'] != null) {
      try {
        final List<dynamic> list = jsonDecode(data['multiparametros_json']);
        for (var entry in list) {
          if (entry is Map<String, dynamic>) {
            entry.forEach((key, val) {
              try {
                final p = allParams.firstWhere((param) => param.claveInterna == key);
                final controller = TextEditingController(text: val.toString());
                controller.addListener(_onFieldChanged);
                multiToLoad.add(ParametroInstancia(
                  parametro: p,
                  controller: controller,
                  uniqueId: '${key}_${DateTime.now().microsecondsSinceEpoch}_${multiToLoad.length}',
                ));
              } catch (_) {}
            });
          }
        }
      } catch (e) {
        debugPrint('🚨 Error decoding multiparametros_json: $e');
      }
    }

    // B. Parse Detalles JSON (New Format)
    if (data['detalles_json'] != null) {
      try {
        final dynamic rawDoc = jsonDecode(data['detalles_json']);
        if (rawDoc is List) {
          // Phase 111/114 format
          for (var entry in rawDoc) {
            if (entry is Map<String, dynamic>) {
              entry.forEach((key, val) {
                try {
                  final p = allParams.firstWhere((param) => param.claveInterna == key);
                  final controller = TextEditingController(text: val.toString());
                  controller.addListener(_onFieldChanged);
                  adicionalesToLoad.add(ParametroInstancia(
                    parametro: p,
                    controller: controller,
                    uniqueId: '${key}_${DateTime.now().microsecondsSinceEpoch}_${adicionalesToLoad.length}',
                  ));
                } catch (_) {}
              });
            }
          }
        } else if (rawDoc is Map<String, dynamic>) {
          // Old legacy categorized format (Phase 111)
          rawDoc.forEach((cat, content) {
            if (content is List) {
              for (var entry in content) {
                if (entry is Map<String, dynamic>) {
                  entry.forEach((key, val) {
                    try {
                      final p = allParams.firstWhere((param) => param.claveInterna == key);
                      final controller = TextEditingController(text: val.toString());
                      controller.addListener(_onFieldChanged);
                      
                      final effectiveCat = _getUbicacionParametro(p);
                      if (effectiveCat == 'Multiparámetro') {
                        multiToLoad.add(ParametroInstancia(parametro: p, controller: controller, uniqueId: '${key}_migrated'));
                      } else {
                        adicionalesToLoad.add(ParametroInstancia(parametro: p, controller: controller, uniqueId: '${key}_migrated'));
                      }
                    } catch (_) {}
                  });
                }
              }
            }
          });
        }
      } catch (e) {
        debugPrint('🚨 Error decoding detalles_json: $e');
      }
    }

    // C. Backward Compatibility: Fixed Columns & Legacy SQL
    // If no JSON data was successfully loaded into the lists, try to recover from fixed columns/SQL
    if (multiToLoad.isEmpty) {
      final coreKeys = ['ph', 'temperatura', 'conductividad', 'oxigeno'];
      for (var key in coreKeys) {
        final val = data[key];
        if (val != null && val.toString().isNotEmpty) {
          try {
            final p = allParams.firstWhere((param) => param.claveInterna == key);
            final controller = TextEditingController(text: val.toString());
            controller.addListener(_onFieldChanged);
            multiToLoad.add(ParametroInstancia(parametro: p, controller: controller, uniqueId: '${key}_recovered'));
          } catch (_) {}
        }
      }
    }

    if (adicionalesToLoad.isEmpty) {
      // Recover from legacy SQL monitoreo_detalles
      final savedExtras = await _dbHelper.getDetallesLocalesPorMonitoreo(id);
      for (var row in savedExtras) {
        final key = row['parametro']?.toString();
        final val = row['valor']?.toString();
        if (key != null && val != null && val.isNotEmpty) {
          try {
            final p = allParams.firstWhere((param) => param.claveInterna == key);
            final controller = TextEditingController(text: val);
            controller.addListener(_onFieldChanged);
            adicionalesToLoad.add(ParametroInstancia(parametro: p, controller: controller, uniqueId: '${key}_recovered_sql'));
          } catch (_) {}
        }
      }
    }

    // 3. SINGLE ATOMIC State Update for Data Injection
    setState(() {
      // Basic Fields
      _isMonitoreoFallido = data['monitoreo_fallido'] == 1;
      if (data['fecha_hora'] != null) {
        _fechaYHoraMuestreo = DateTime.parse(data['fecha_hora']);
      }
      _obsController.text = data['observacion'] ?? '';
      _codLabController.text = data['cod_laboratorio'] ?? '';
      _muestreoHidroquimico = data['hidroquimico'] == 1;
      _muestreoIsotopico = data['isotopico'] == 2; // Fixed legacy typo if any
      _muestreoIsotopico = data['isotopico'] == 1;
      _inspectorSeleccionado = inspectorName;

      // Dropdowns
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

      // VIP Hardcoded Parameters Still Mapped to Controllers for Chart/Validation logic
      _paramControllers['turbiedad']?.text = data['turbiedad']?.toString() ?? '';
      _paramControllers['profundidad']?.text = data['profundidad']?.toString() ?? '';
      _paramControllers['nivel']?.text = data['nivel']?.toString() ?? '';
      
      _estacionLatitud = data['latitud'];
      _estacionLongitud = data['longitud'];
      _imagePath = data['foto_path'];
      _fotoMultiparametroPath = data['foto_multiparametro'];
      _fotoTurbiedadPath = data['foto_turbiedad'];

      // Phase 115: Restore Caudal & new photo fields
      _selectedEquipoCaudalId = data['equipo_caudal'];
      _caudalController.text = data['nivel_caudal']?.toString() ?? '';
      if (data['fecha_hora_caudal'] != null) {
        _fechaHoraCaudal = DateTime.parse(data['fecha_hora_caudal']);
      }
      _fotoCaudalPath = data['foto_caudal'];
      _fotoNivelFreaticoPath = data['foto_nivel_freatico'];
      _fotoMuestreoPath = data['foto_muestreo'];

      // Dynamic Lists (Phase 114)
      _selectedAdicionalesInstancias = adicionalesToLoad;
      _selectedMultiInstancias = multiToLoad;
    });

    // Special case: Fetch stations and ranges AFTER state is set for basic lookups
    if (_programaSeleccionado != null) {
      final stations = await _dbHelper.getStationsByProgram(_programaSeleccionado!.id);
      setState(() {
        _estaciones = stations;
        try {
          _estacionSeleccionada = _estaciones.firstWhere((s) => s.id == data['estacion_id']);
        } catch (_) {}
      });

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

  // Phase 122: Conditional State Reset when Water Matrix changes
  void _onMatrizChanged(String val) {
    final newMatriz = _matrices.firstWhere((m) => m.nombreMatriz == val);
    final bool wasSubterranea =
        _matrizSeleccionada?.nombreMatriz.toLowerCase().contains('subterránea') ?? false;
    final bool isNowSubterranea =
        newMatriz.nombreMatriz.toLowerCase().contains('subterránea');
    final bool wasSuperficial =
        _matrizSeleccionada?.nombreMatriz == 'Aguas Superficiales';
    final bool isNowSuperficial = newMatriz.nombreMatriz == 'Aguas Superficiales';

    setState(() {
      _matrizSeleccionada = newMatriz;

      // Clear Nivel Freático fields when switching away from Aguas Subterráneas
      if (wasSubterranea && !isNowSubterranea) {
        _equipoNivelSeleccionado = null;
        _tipoNivelPozoSeleccionado = null;
        _fechaYHoraNivel = null;
        _paramControllers['nivel']?.clear();
        _fotoNivelFreaticoPath = null;
      }

      // Clear Caudal fields when switching away from Aguas Superficiales
      if (wasSuperficial && !isNowSuperficial) {
        _selectedEquipoCaudalId = null;
        _caudalController.clear();
        _fechaHoraCaudal = null;
        _fotoCaudalPath = null;
      }
    });

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

    // 2. Validate the station
    if (_estacionSeleccionada == null) {
      _showError('Por favor, selecciona un Punto de Control arriba primero.');
      return;
    }

    // 3. Force save draft before leaving
    await _saveAsDraft();

    // 4. Proceed to Navigation
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChartAnalysisScreen(
          estacion: _estacionSeleccionada!.name,
          parametro: parameterKey,
          currentInputValue: double.tryParse(controller.text),
          onValueUpdated: widget.isReadOnly ? null : (double newValue) {
            // 🚨 UPDATE CONTROLLER & TRIGGER DRAFT SAVE
            setState(() {
              controller.text = newValue.toStringAsFixed(2);
            });
            _saveAsDraft();
          },
        ),
      ),
    ).then((_) {
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

  // Phase 124: Helper — true if ANY photo slot is still being watermarked.
  bool get _isProcessingAnyImage =>
      _isProcessingImage ||
      _isProcessingMulti ||
      _isProcessingTurb ||
      _isProcessingCaudal ||
      _isProcessingNivelFreatico ||
      _isProcessingMuestreo;

  Future<void> _guardarMonitoreo() async {
    // Phase 124: Block save while any watermark job is still running.
    if (_isProcessingAnyImage) {
      _showError('⏳ Espere a que la fotografía termine de procesarse antes de guardar.');
      return;
    }

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
        if (!widget.isReadOnly) {
          await _saveAsDraft();
        }
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
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'admin_params') {
                // Force save draft before leaving
                await _saveAsDraft();
                if (!mounted) return;
                // Pass the tab index for 'Parámetros' (index 4)
                Navigator.pushNamed(context, '/administracion', arguments: {'initialTab': 4}); 
              }
            },
            itemBuilder: (BuildContext context) {
              return [
                const PopupMenuItem<String>(
                  value: 'admin_params',
                  child: Row(
                    children: [
                      Icon(Icons.settings_input_component, color: Colors.blueAccent),
                      SizedBox(width: 8),
                      Text('Administrar Parámetros'),
                    ],
                  ),
                ),
              ];
            },
          ),
        ],
      ),
      drawer: const AppDrawer(currentRoute: '/registrar_monitoreo'),
      body: ListView(
        children: [
          if (widget.isReadOnly)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              color: isDarkMode ? Colors.amber.withAlpha(50) : const Color(0xFFFFF9C4), // Soft yellow
              child: Row(
                children: [
                  Icon(Icons.lock_outline, color: isDarkMode ? Colors.amber : Colors.orange[800], size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Este registro ya fue enviado al servidor y no puede ser modificado.',
                      style: TextStyle(
                        color: isDarkMode ? Colors.amber[200] : Colors.orange[900],
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // --- SECCIÓN 1: DATOS DE MONITOREO ---
          if (_isMonitoreoFallido) ...[
            Container(
              color: const Color(0xFFFF4B61), 
              child: ListTile(
                leading: const Icon(Icons.assignment_outlined, size: 28, color: Colors.white),
                title: const Text('Datos de Monitoreo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.white)),
              ),
            ),
            IgnorePointer(ignoring: widget.isReadOnly, child: _buildFormularioDatosMonitoreo(isDarkMode)),
          ] else
            _buildSectionTile(
              'Datos de Monitoreo',
              isDarkMode,
              _isDatosMonitoreoComplete,
              [IgnorePointer(ignoring: widget.isReadOnly, child: _buildFormularioDatosMonitoreo(isDarkMode))],
            ),

          // --- SECCIÓN 1.5: NIVEL FREÁTICO (Condicional) ---
          if ((_matrizSeleccionada?.nombreMatriz.toLowerCase().contains('subterránea') ?? false) && !_isMonitoreoFallido)
            _buildSectionTile(
              'Nivel Freático',
              isDarkMode,
              _isNivelComplete,
              [
                IgnorePointer(ignoring: widget.isReadOnly, child: SearchableDropdown(
                  label: 'Equipo Nivel',
                  hintText: 'Seleccione equipo de nivel',
                  searchHintText: 'Buscar equipo...',
                  selectedValue: _equipoNivelSeleccionado,
                  options: _equiposMultiOptions,
                  isDarkMode: isDarkMode,
                  onChanged: (val) => setState(() => _equipoNivelSeleccionado = val),
                )),
                IgnorePointer(ignoring: widget.isReadOnly, child: SearchableDropdown(
                  label: 'Tipo / Nivel Pozo',
                  hintText: 'Seleccione tipo de pozo',
                  searchHintText: 'Buscar tipo...',
                  selectedValue: _tipoNivelPozoSeleccionado,
                  options: const ['Pozo Monitoreo', 'Pozo Producción', 'Cisterna', 'Otro'],
                  isDarkMode: isDarkMode,
                  onChanged: (val) => setState(() => _tipoNivelPozoSeleccionado = val),
                )),
                IgnorePointer(ignoring: widget.isReadOnly, child: CustomParametroInputRow(
                  isReadOnly: widget.isReadOnly,
                  label: 'Nivel Freático [$_unitNivel]',
                  hintText: 'Ingrese nivel',
                  isDarkMode: isDarkMode,
                  controller: _paramControllers['nivel']!,
                  parameterKey: 'nivel',
                  selectedEstacion: _estacionSeleccionada?.name ?? '',
                  showLeadingIcon: true,
                  hasHistory: _hasHistory,
                  minAllowed: _parameterRanges['nivel']?['min'],
                  maxAllowed: _parameterRanges['nivel']?['max'],
                  onChanged: _onFieldChanged,
                  onPulseTap: () => _navigateToChart('nivel', _paramControllers['nivel']!),
                )),
                // DYNAMIC: Removing previous loop from Section 2 (Fixed/Quemado logic)
                IgnorePointer(ignoring: widget.isReadOnly, child: CustomFormRow(
                  label: 'Hora Medición - Nivel',
                  value: _fechaYHoraNivel == null ? 'Seleccione Hora y Fecha' : _formatearFechaYHora(_fechaYHoraNivel!),
                  isValid: _fechaYHoraNivel != null,
                  showArrow: false,
                  isDarkMode: isDarkMode,
                  onTap: () async {
                    final now = DateTime.now();
                    final today = DateTime(now.year, now.month, now.day);
                    final initial = _fechaYHoraNivel ?? now;
                    // Safe logic: Today or the existing past date if it's a draft
                    final safeFirstDate = initial.isBefore(today) ? initial : today;

                    final DateTime? fecha = await showDatePicker(
                      context: context, 
                      initialDate: initial, 
                      firstDate: safeFirstDate, 
                      lastDate: DateTime(2100)
                    );
                    if (!mounted || fecha == null) return;
                    final TimeOfDay? hora = await showTimePicker(
                      context: context, initialTime: _fechaYHoraNivel != null ? TimeOfDay.fromDateTime(_fechaYHoraNivel!) : TimeOfDay.now()
                    );
                    if (!mounted || hora == null) return;
                    setState(() => _fechaYHoraNivel = DateTime(fecha.year, fecha.month, fecha.day, hora.hour, hora.minute));
                  },
                )),
                // Phase 115: Photo backup for Nivel Freático
                IgnorePointer(
                  ignoring: widget.isReadOnly,
                  child: _buildEquipmentPhotoFullPreview(
                    title: 'EVIDENCIA NIVEL FREÁTICO',
                    path: _fotoNivelFreaticoPath,
                    isProcessing: _isProcessingNivelFreatico,
                    onTomarFoto: _tomarFotoNivelFreatico,
                    onClear: () => setState(() => _fotoNivelFreaticoPath = null),
                    onVerificar: () => _sharePhoto(_fotoNivelFreaticoPath!),
                    isDarkMode: isDarkMode,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              leadingIcon: Icons.water_drop,
            ),

          // --- SECCIÓN 1.6: CAUDAL (Condicional: solo Aguas Superficiales) ---
          if ((_matrizSeleccionada?.nombreMatriz == 'Aguas Superficiales') && !_isMonitoreoFallido)
            _buildSectionTile(
              'Caudal',
              isDarkMode,
              _selectedEquipoCaudalId != null && _caudalController.text.isNotEmpty && _fechaHoraCaudal != null,
              [
                // Equipo Caudal (Molinete)
                IgnorePointer(
                  ignoring: widget.isReadOnly,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                    child: DropdownButtonFormField<int>(
                      value: _selectedEquipoCaudalId,
                      decoration: InputDecoration(
                        labelText: 'Equipo Caudal (Molinete)',
                        labelStyle: const TextStyle(color: Colors.blueAccent, fontSize: 13),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: _equiposCaudal.map((e) => DropdownMenuItem<int>(
                        value: e.id,
                        child: Text(e.codigo, style: const TextStyle(fontSize: 14)),
                      )).toList(),
                      onChanged: widget.isReadOnly ? null : (val) {
                        setState(() => _selectedEquipoCaudalId = val);
                        _saveAsDraft();
                      },
                      hint: const Text('Seleccione equipo Molinete'),
                    ),
                  ),
                ),
                // Nivel Caudal [L/s]
                IgnorePointer(
                  ignoring: widget.isReadOnly,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(
                          _caudalController.text.isNotEmpty ? Icons.check_circle : Icons.cancel,
                          color: _caudalController.text.isNotEmpty
                              ? Colors.greenAccent
                              : (isDarkMode ? Colors.grey.shade700 : Colors.grey.shade400),
                          size: 24,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextField(
                            controller: _caudalController,
                            readOnly: widget.isReadOnly,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                            onChanged: (_) {
                              setState(() {});
                              _onFieldChanged();
                            },
                            style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
                            decoration: InputDecoration(
                              labelText: 'Nivel Caudal [$_unitCaudal]',
                              hintText: 'Ingrese caudal',
                              labelStyle: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 13),
                              hintStyle: TextStyle(color: isDarkMode ? Colors.grey[400] : Colors.grey[600], fontSize: 14),
                              border: InputBorder.none,
                              isDense: true,
                              suffixIcon: (!widget.isReadOnly && _caudalController.text.isNotEmpty)
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 18, color: Colors.grey),
                                      onPressed: () {
                                        _caudalController.clear();
                                        setState(() {});
                                        _onFieldChanged();
                                      },
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Fecha/Hora Caudal
                IgnorePointer(
                  ignoring: widget.isReadOnly,
                  child: CustomFormRow(
                    label: 'Fecha/Hora - Caudal',
                    value: _fechaHoraCaudal == null
                        ? 'Seleccione Fecha y Hora'
                        : _formatearFechaYHora(_fechaHoraCaudal!),
                    isValid: _fechaHoraCaudal != null,
                    showArrow: false,
                    isDarkMode: isDarkMode,
                    onTap: () async {
                      final now = DateTime.now();
                      final today = DateTime(now.year, now.month, now.day);
                      final initial = _fechaHoraCaudal ?? now;
                      final safeFirstDate = initial.isBefore(today) ? initial : today;
                      final DateTime? fecha = await showDatePicker(
                        context: context,
                        initialDate: initial,
                        firstDate: safeFirstDate,
                        lastDate: DateTime(2100),
                      );
                      if (!mounted || fecha == null) return;
                      final TimeOfDay? hora = await showTimePicker(
                        context: context,
                        initialTime: _fechaHoraCaudal != null
                            ? TimeOfDay.fromDateTime(_fechaHoraCaudal!)
                            : TimeOfDay.now(),
                      );
                      if (!mounted || hora == null) return;
                      setState(() => _fechaHoraCaudal = DateTime(
                        fecha.year, fecha.month, fecha.day, hora.hour, hora.minute,
                      ));
                      _saveAsDraft();
                    },
                  ),
                ),
                // Photo backup for Caudal
                IgnorePointer(
                  ignoring: widget.isReadOnly,
                  child: _buildEquipmentPhotoFullPreview(
                    title: 'EVIDENCIA CAUDAL',
                    path: _fotoCaudalPath,
                    isProcessing: _isProcessingCaudal,
                    onTomarFoto: _tomarFotoCaudal,
                    onClear: () => setState(() => _fotoCaudalPath = null),
                    onVerificar: () => _sharePhoto(_fotoCaudalPath!),
                    isDarkMode: isDarkMode,
                  ),
                ),
                const SizedBox(height: 16),
              ],
              leadingIcon: Icons.water,
            ),

          // --- SECCIONES INFERIORES (Se ocultan si falla el monitoreo) ---
          if (!_isMonitoreoFallido) ...[
            
            // --- SECCIÓN 2: MULTIPARÁMETRO ---
            _buildSectionTile('Multiparámetro', isDarkMode, _isMultiparametroComplete, [
              IgnorePointer(ignoring: widget.isReadOnly, child: SearchableDropdown(
                label: 'Equipo Multiparametro',
                hintText: 'Seleccione equipo',
                searchHintText: 'Buscar equipo...',
                selectedValue: _equipoMultiparametroSeleccionado,
                options: _equiposMultiOptions,
                isDarkMode: isDarkMode,
                onChanged: (val) => setState(() => _equipoMultiparametroSeleccionado = val),
              )),
              if (_equipoMultiparametroSeleccionado != null) ...[
                // Phase 114: Rendering Dynamic Multiparametro Instances
                ..._selectedMultiInstancias.map((inst) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: CustomParametroInputRow(
                          isReadOnly: widget.isReadOnly,
                          label: '${inst.parametro.nombreParametro} [${inst.parametro.unidad}]',
                          hintText: 'Ingrese valor',
                          isDarkMode: isDarkMode,
                          controller: inst.controller,
                          parameterKey: inst.uniqueId,
                          selectedEstacion: _estacionSeleccionada?.name ?? '',
                          hasHistory: _hasHistory,
                          minAllowed: _parameterRanges[inst.parametro.claveInterna]?['min'],
                          maxAllowed: _parameterRanges[inst.parametro.claveInterna]?['max'],
                          onChanged: _onFieldChanged,
                          onPulseTap: () => _navigateToChart(inst.parametro.claveInterna, inst.controller),
                        ),
                      ),
                      if (!widget.isReadOnly)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          onPressed: () => _removeInstancia(inst),
                        ),
                    ],
                  ),
                )).toList(),
                
                if (!widget.isReadOnly) ...[
                  const Divider(height: 32),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<Parametro>(
                            value: _parametroMultiDummySeleccionado,
                            decoration: InputDecoration(
                              labelText: 'Añadir Multiparámetro Extra',
                              labelStyle: const TextStyle(color: Colors.blueAccent, fontSize: 13),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            items: _availableExtraParams
                              .where((p) {
                                final key = p.claveInterna.toLowerCase();
                                return key != 'profundidad' && key != 'nivel' && key != 'turbiedad';
                              })
                              .map((p) => DropdownMenuItem(
                                value: p,
                                child: Text('${p.nombreParametro} [${p.unidad}]', style: const TextStyle(fontSize: 14)),
                              )).toList(),
                            onChanged: (val) => setState(() => _parametroMultiDummySeleccionado = val),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _parametroMultiDummySeleccionado == null ? null : () {
                            setState(() {
                              final controller = TextEditingController();
                              controller.addListener(_onFieldChanged);
                              _selectedMultiInstancias.add(ParametroInstancia(
                                parametro: _parametroMultiDummySeleccionado!, 
                                controller: controller, 
                                uniqueId: '${_parametroMultiDummySeleccionado!.claveInterna}_${DateTime.now().millisecondsSinceEpoch}'
                              ));
                              _parametroMultiDummySeleccionado = null;
                            });
                            _saveAsDraft();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Icon(Icons.add, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                IgnorePointer(ignoring: widget.isReadOnly, child: _buildEquipmentPhotoFullPreview(
                  title: 'EVIDENCIA MULTIPARÁMETRO',
                  path: _fotoMultiparametroPath,
                  isProcessing: _isProcessingMulti,
                  onTomarFoto: _tomarFotoMultiparametro,
                  onClear: () => setState(() => _fotoMultiparametroPath = null),
                  onVerificar: () => _sharePhoto(_fotoMultiparametroPath!),
                  isDarkMode: isDarkMode,
                )),
                const SizedBox(height: 16),
              ],
            ]),
            const SizedBox(height: 16),

            // --- SECCIÓN 4: PARÁMETROS ADICIONALES (Manual Builder Phase 103) ---
            _buildSectionTile('Parámetros Adicionales', isDarkMode, true, [
              ..._selectedAdicionalesInstancias.map((inst) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  children: [
                    Expanded(
                      child: CustomParametroInputRow(
                        isReadOnly: widget.isReadOnly,
                        label: '${inst.parametro.nombreParametro} [${inst.parametro.unidad}]',
                        hintText: 'Ingrese valor',
                        isDarkMode: isDarkMode,
                        controller: inst.controller,
                        parameterKey: inst.uniqueId,
                        selectedEstacion: _estacionSeleccionada?.name ?? '',
                        hasHistory: _hasHistory,
                        minAllowed: _parameterRanges[inst.parametro.claveInterna]?['min'],
                        maxAllowed: _parameterRanges[inst.parametro.claveInterna]?['max'],
                        onChanged: _onFieldChanged,
                        onPulseTap: () => _navigateToChart(inst.parametro.claveInterna, inst.controller),
                      ),
                    ),
                    if (!widget.isReadOnly)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: () => _removeInstancia(inst),
                      ),
                  ],
                ),
              )).toList(),

              if (!widget.isReadOnly) ...[
                const Divider(height: 32),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<Parametro>(
                          value: _parametroAdicionalSeleccionado,
                          decoration: InputDecoration(
                            labelText: 'Seleccionar Parámetro',
                            labelStyle: const TextStyle(color: Colors.blueAccent, fontSize: 13),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          items: _availableExtraParams
                            .where((p) {
                              final key = p.claveInterna.toLowerCase();
                              // Exclude core VIP parameters as per requirement
                              return key != 'profundidad' && key != 'nivel' && key != 'turbiedad';
                            })
                            .map((p) => DropdownMenuItem(
                              value: p,
                              child: Text('${p.nombreParametro} [${p.unidad}]', style: const TextStyle(fontSize: 14)),
                            )).toList(),
                          onChanged: (val) => setState(() => _parametroAdicionalSeleccionado = val),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // AGREGAR BUTTON
                      ElevatedButton(
                        onPressed: _parametroAdicionalSeleccionado == null ? null : () {
                          final p = _parametroAdicionalSeleccionado!;
                          
                          // Fase 111: Generate unique instance
                          final controller = TextEditingController();
                          controller.addListener(_onFieldChanged);
                          
                          final instanceId = '${p.claveInterna}_${DateTime.now().millisecondsSinceEpoch}';
                          
                          setState(() {
                            _selectedAdicionalesInstancias.add(ParametroInstancia(
                              parametro: p,
                              controller: controller,
                              uniqueId: instanceId,
                            ));
                            _parametroAdicionalSeleccionado = null; 
                          });
                          _saveAsDraft();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Icon(Icons.add, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ],
            leadingIcon: Icons.add_chart,
          ),

            // --- SECCIÓN 5: TURBIEDAD ---
            _buildSectionTile('Turbiedad', isDarkMode, _isTurbiedadComplete, [
                IgnorePointer(ignoring: widget.isReadOnly, child: SearchableDropdown(
                  label: 'Turbidimetro',
                  hintText: 'Seleccione equipo',
                  searchHintText: 'Buscar equipo...',
                  selectedValue: _turbidimetroSeleccionado,
                  options: _turbidimetrosOptions,
                  isDarkMode: isDarkMode,
                  onChanged: (val) => setState(() => _turbidimetroSeleccionado = val),
                )),
                if (_turbidimetroSeleccionado != null) ...[
                  // Dynamic: For Turbiedad section, we use the loop (Dynamic logic as per user orientation)
                  ...(_categorizedParams['Turbiedad'] ?? [])
                      .where((p) => !_fixedKeys.contains(p.claveInterna))
                      .map((p) => Visibility(
                    visible: _activeParameterKeys.contains(p.claveInterna),
                    child: CustomParametroInputRow(
                      isReadOnly: widget.isReadOnly,
                      label: '${p.nombreParametro} [${p.unidad}]',
                      hintText: 'Ingrese ${p.nombreParametro}',
                      isDarkMode: isDarkMode,
                      controller: _paramControllers[p.claveInterna]!,
                      parameterKey: p.claveInterna,
                      selectedEstacion: _estacionSeleccionada?.name ?? '',
                      hasHistory: _hasHistory,
                      minAllowed: _parameterRanges[p.claveInterna]?['min'],
                      maxAllowed: _parameterRanges[p.claveInterna]?['max'],
                      bypassValidation: true,
                      onChanged: _onFieldChanged,
                      onPulseTap: () => _navigateToChart(p.claveInterna, _paramControllers[p.claveInterna]!),
                    ),
                  )).toList(),
                  IgnorePointer(ignoring: widget.isReadOnly, child: _buildEquipmentPhotoFullPreview(
                    title: 'EVIDENCIA TURBIEDAD',
                    path: _fotoTurbiedadPath,
                    isProcessing: _isProcessingTurb,
                    onTomarFoto: _tomarFotoTurbiedad,
                    onClear: () => setState(() => _fotoTurbiedadPath = null),
                    onVerificar: () => _sharePhoto(_fotoTurbiedadPath!),
                    isDarkMode: isDarkMode,
                  )),
                ],
                const SizedBox(height: 16),
              ],
            ),
            
            // --- SECCIÓN 4: MUESTREO ---
            _buildSectionTile('Muestreo', isDarkMode, _isMuestreoComplete, [
              IgnorePointer(ignoring: widget.isReadOnly, child: SearchableDropdown(
                label: 'Método de Muestreo',
                hintText: 'Seleccione método de muestreo',
                searchHintText: 'Buscar método...',
                selectedValue: _metodoSeleccionado?.metodo,
                options: _metodos.map((m) => m.metodo).toList(),
                isDarkMode: isDarkMode,
                onChanged: (val) {
                  setState(() => _metodoSeleccionado = _metodos.firstWhere((m) => m.metodo == val));
                },
              )),
              IgnorePointer(ignoring: widget.isReadOnly, child: CustomFormRow(
                label: 'Muestreo Hidroquímico', 
                value: _muestreoHidroquimico == null ? '[Si Aplica]' : (_muestreoHidroquimico! ? 'SI' : 'NO'), 
                isValid: _muestreoHidroquimico != null,
                isDarkMode: isDarkMode,
                onTap: () async {
                  final result = await _mostrarDialogoSiNo('Muestreo Hidroquímico', _muestreoHidroquimico);
                  if (mounted && result != null) setState(() => _muestreoHidroquimico = result);
                }
              )),
              IgnorePointer(ignoring: widget.isReadOnly, child: CustomFormRow(
                label: 'Muestreo Isotópico', 
                value: _muestreoIsotopico == null ? '[Si Aplica]' : (_muestreoIsotopico! ? 'SI' : 'NO'), 
                isValid: _muestreoIsotopico != null,
                isDarkMode: isDarkMode,
                onTap: () async {
                  final result = await _mostrarDialogoSiNo('Muestreo Isotópico', _muestreoIsotopico);
                  if (mounted && result != null) setState(() => _muestreoIsotopico = result);
                }
              )),
              // REACTIVE Código Laboratorio
              IgnorePointer(ignoring: widget.isReadOnly, child: ValueListenableBuilder<TextEditingValue>(
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
              )),
              const Divider(height: 1),
              const SizedBox(height: 16),
              // REACTIVE Descripción / Observación
              IgnorePointer(ignoring: widget.isReadOnly, child: ValueListenableBuilder<TextEditingValue>(
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
              )),
              // Phase 115: Photo backup for Muestreo (below Descripción)
              IgnorePointer(
                ignoring: widget.isReadOnly,
                child: _buildEquipmentPhotoFullPreview(
                  title: 'EVIDENCIA MUESTREO',
                  path: _fotoMuestreoPath,
                  isProcessing: _isProcessingMuestreo,
                  onTomarFoto: _tomarFotoMuestreo,
                  onClear: () => setState(() => _fotoMuestreoPath = null),
                  onVerificar: () => _sharePhoto(_fotoMuestreoPath!),
                  isDarkMode: isDarkMode,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
          const SizedBox(height: 16),
        ],

          // --- 5. BOTÓN DE GUARDAR ---
          if (!widget.isReadOnly)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
              child: OutlinedButton.icon(
                // Phase 124: Also disable while any photo watermark is in progress.
                onPressed: (_isSaving || _isProcessingAnyImage) ? null : _guardarMonitoreo,
                icon: _isSaving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : _isProcessingAnyImage
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange))
                        : const Icon(Icons.save_outlined, color: Colors.blueAccent),
                label: Text(
                  _isSaving ? 'GUARDANDO...' : _isProcessingAnyImage ? 'PROCESANDO FOTO...' : 'GUARDAR',
                  style: const TextStyle(color: Colors.blueAccent, fontSize: 16, letterSpacing: 1.2, fontWeight: FontWeight.w500),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.blueAccent, width: 1.5), 
                  padding: const EdgeInsets.symmetric(vertical: 16.0), 
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.0)),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back, color: Colors.grey),
                label: const Text('VOLVER', style: TextStyle(color: Colors.grey, fontSize: 16, letterSpacing: 1.2, fontWeight: FontWeight.w500)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.grey, width: 1.5), 
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
            onChanged: _onMatrizChanged,
          ),
          
          CustomFormRow(
            label: 'Hora y Fecha de Muestreo', 
            value: _fechaYHoraMuestreo == null ? 'Seleccione Hora y Fecha' : _formatearFechaYHora(_fechaYHoraMuestreo!), 
            isValid: _fechaYHoraMuestreo != null, 
            showArrow: false,
            isDarkMode: isDarkMode,
            onTap: _seleccionarFechaYHora, 
          ),
          
          if (_activeParameterKeys.contains('profundidad'))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: CustomParametroInputRow(
                isReadOnly: widget.isReadOnly,
                label: 'Profundidad de muestreo [$_unitProfundidad]', 
                hintText: 'Ingrese profundidad', 
                isDarkMode: isDarkMode, 
                controller: _paramControllers['profundidad']!,
                parameterKey: 'profundidad',
                selectedEstacion: _estacionSeleccionada?.name ?? '',
                showLeadingIcon: true,
                showPulseIcon: false,
                isMandatory: true,
                hasHistory: _hasHistory,
                minAllowed: _parameterRanges['profundidad']?['min'],
                maxAllowed: _parameterRanges['profundidad']?['max'],
                bypassValidation: true, 
              ),
            ),
          
          // DYNAMIC: Removing previous loop from Section 1 (Fixed/Quemado logic)
          
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
          
          IgnorePointer(ignoring: widget.isReadOnly, child: _buildPhotoPreview(isDarkMode)),
          
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
              const SnackBar(content: Text('⚠️ Se guardará la foto sin estampa (GPS no disponible)')),
            );
          }
          await _savePhotoWithoutStamp(File(pickerImage.path), target);
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
        await _savePhotoWithoutStamp(File(image.path), 'multi');
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
        await _savePhotoWithoutStamp(File(image.path), 'turb');
      }
    }
  }

  // Phase 115: New photo capture methods
  Future<void> _tomarFotoCaudal() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      Position? position = await _getCurrentLocation();
      if (position != null) {
        await _processImageWithStamp(File(image.path), position, target: 'caudal');
      } else {
        await _savePhotoWithoutStamp(File(image.path), 'caudal');
      }
    }
  }

  Future<void> _tomarFotoNivelFreatico() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      Position? position = await _getCurrentLocation();
      if (position != null) {
        await _processImageWithStamp(File(image.path), position, target: 'nivel_freatico');
      } else {
        await _savePhotoWithoutStamp(File(image.path), 'nivel_freatico');
      }
    }
  }

  Future<void> _tomarFotoMuestreo() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      Position? position = await _getCurrentLocation();
      if (position != null) {
        await _processImageWithStamp(File(image.path), position, target: 'muestreo');
      } else {
        await _savePhotoWithoutStamp(File(image.path), 'muestreo');
      }
    }
  }

  Future<void> _processImageWithStamp(File imageFile, Position position, {String target = 'general'}) async {
    if (target == 'general') setState(() => _isProcessingImage = true);
    else if (target == 'multi') setState(() => _isProcessingMulti = true);
    else if (target == 'turb') setState(() => _isProcessingTurb = true);
    else if (target == 'caudal') setState(() => _isProcessingCaudal = true);
    else if (target == 'nivel_freatico') setState(() => _isProcessingNivelFreatico = true);
    else if (target == 'muestreo') setState(() => _isProcessingMuestreo = true);

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
      
      // 🚨 COMPRESS IMAGE BEFORE SAVING TO DISK
      final Uint8List? compressedBytes = await FlutterImageCompress.compressWithList(
        stampedBytes,
        minWidth: 800,
        minHeight: 800,
        quality: 70,
      );

      final File processedFile = File(filePath);
      if (compressedBytes != null) {
        await processedFile.writeAsBytes(compressedBytes);
        debugPrint('✅ Imagen comprimida guardada: ${(compressedBytes.length / 1024).toStringAsFixed(2)} KB');
      } else {
        await processedFile.writeAsBytes(stampedBytes);
        debugPrint('⚠️ Falló compresión, guardando original: ${(stampedBytes.length / 1024).toStringAsFixed(2)} KB');
      }

      setState(() {
        if (target == 'general') _imagePath = filePath;
        else if (target == 'multi') _fotoMultiparametroPath = filePath;
        else if (target == 'turb') _fotoTurbiedadPath = filePath;
        else if (target == 'caudal') _fotoCaudalPath = filePath;
        else if (target == 'nivel_freatico') _fotoNivelFreaticoPath = filePath;
        else if (target == 'muestreo') _fotoMuestreoPath = filePath;
      });
      // 🚨 PERSISTENCE FIX: Trigger draft save immediately after photo processing
      await _saveAsDraft();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al procesar foto: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          if (target == 'general') _isProcessingImage = false;
          else if (target == 'multi') _isProcessingMulti = false;
          else if (target == 'turb') _isProcessingTurb = false;
          else if (target == 'caudal') _isProcessingCaudal = false;
          else if (target == 'nivel_freatico') _isProcessingNivelFreatico = false;
          else if (target == 'muestreo') _isProcessingMuestreo = false;
        });
      }
    }
  }

  Future<void> _savePhotoWithoutStamp(File tempFile, String target) async {
    // Phase 124: Set only the correct processing flag for this target.
    if (target == 'general') setState(() => _isProcessingImage = true);
    else if (target == 'multi') setState(() => _isProcessingMulti = true);
    else if (target == 'turb') setState(() => _isProcessingTurb = true);
    else if (target == 'caudal') setState(() => _isProcessingCaudal = true);
    else if (target == 'nivel_freatico') setState(() => _isProcessingNivelFreatico = true);
    else if (target == 'muestreo') setState(() => _isProcessingMuestreo = true);

    try {
      final directory = await getApplicationDocumentsDirectory();
      final String fileName = 'EVIDENCIA_RAW_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final String filePath = p.join(directory.path, fileName);
      
      // Read bytes from temp file
      final Uint8List bytes = await tempFile.readAsBytes();

      // Compress even without stamp for consistency
      final Uint8List? compressedBytes = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 800,
        minHeight: 800,
        quality: 70,
      );

      final File processedFile = File(filePath);
      if (compressedBytes != null) {
        await processedFile.writeAsBytes(compressedBytes);
        debugPrint('✅ Imagen RAW comprimida guardada: ${(compressedBytes.length / 1024).toStringAsFixed(2)} KB');
      } else {
        await tempFile.copy(filePath);
        debugPrint('⚠️ Falló compresión RAW, copiando original');
      }

      setState(() {
        if (target == 'general') _imagePath = filePath;
        else if (target == 'multi') _fotoMultiparametroPath = filePath;
        else if (target == 'turb') _fotoTurbiedadPath = filePath;
        else if (target == 'caudal') _fotoCaudalPath = filePath;
        else if (target == 'nivel_freatico') _fotoNivelFreaticoPath = filePath;
        else if (target == 'muestreo') _fotoMuestreoPath = filePath;
      });
      
      // 🚨 PERSISTENCE FIX: Trigger draft save
      await _saveAsDraft();
    } catch (e) {
      debugPrint('Error saving photo without stamp: $e');
    } finally {
      // Phase 124: Reset ONLY the flag for this specific target, never touch others.
      if (mounted) {
        setState(() {
          if (target == 'general') _isProcessingImage = false;
          else if (target == 'multi') _isProcessingMulti = false;
          else if (target == 'turb') _isProcessingTurb = false;
          else if (target == 'caudal') _isProcessingCaudal = false;
          else if (target == 'nivel_freatico') _isProcessingNivelFreatico = false;
          else if (target == 'muestreo') _isProcessingMuestreo = false;
        });
      }
    }
  }

  Future<void> _removeImage() async {
    setState(() => _imagePath = null);
  }

  // --- COMPRESSION UTILITY ---
  Future<Uint8List?> _compressImage(String targetPath) async {
    try {
      final result = await FlutterImageCompress.compressWithFile(
        targetPath,
        minWidth: 800,
        minHeight: 800,
        quality: 70,
      );
      return result;
    } catch (e) {
      debugPrint('Error comprimiendo archivo: $e');
      return null;
    }
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
    required Future<void> Function() onTomarFoto,
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
            onPressed: () async {
              await onTomarFoto();
            },
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
                    onPressed: () async {
                      await onTomarFoto();
                    },
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

  // Phase 124: Must be async and await _pickImage so the caller can await it too.
  Future<void> _showPickImageOptions() async {
    await _pickImage(ImageSource.camera);
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
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final initial = _fechaYHoraMuestreo ?? now;
    // Prevent crash if an old draft is loaded with a past date
    final safeFirstDate = initial.isBefore(today) ? initial : today;

    final DateTime? fecha = await showDatePicker(
      context: context, 
      initialDate: initial, 
      firstDate: safeFirstDate, 
      lastDate: DateTime(2100)
    );
    if (!mounted || fecha == null) return;

    final TimeOfDay? hora = await showTimePicker(
      context: context, 
      initialTime: _fechaYHoraMuestreo != null ? TimeOfDay.fromDateTime(_fechaYHoraMuestreo!) : TimeOfDay.now()
    );
    if (!mounted || hora == null) return;

    setState(() => _fechaYHoraMuestreo = DateTime(fecha.year, fecha.month, fecha.day, hora.hour, hora.minute));
  }

  String _formatearFechaYHora(DateTime f) => '${f.day.toString().padLeft(2,'0')}/${f.month.toString().padLeft(2,'0')}/${f.year} ${f.hour.toString().padLeft(2,'0')}:${f.minute.toString().padLeft(2,'0')}';
  
  // --- ORIENTATION LOGIC (Phase 102.1) ---
  String _getUbicacionParametro(Parametro p) {
    // 1. Priority: Key Matching as per user orientation screenshot
    final key = p.claveInterna.toLowerCase();
    
    if (key.contains('ph') || key.contains('temperatura') || key.contains('conductividad') || key.contains('oxigeno') || key.contains('oxígeno')) {
      return 'Multiparámetro';
    } 
    if (key.contains('turbiedad')) {
      return 'Turbiedad';
    }
    if (key.contains('nivel')) {
      return 'Nivel Freático';
    }
    if (key.contains('profundidad')) {
      return 'Datos de Monitoreo';
    }
    
    // 2. Fallback: Database Category
    return p.categoria ?? 'Parámetros Adicionales';
  }

  // --- DYNAMIC PARAMETER LOGIC (Phase 75/94/111/114) ---
  void _removeInstancia(ParametroInstancia inst) {
    setState(() {
      _selectedAdicionalesInstancias.removeWhere((i) => i.uniqueId == inst.uniqueId);
      _selectedMultiInstancias.removeWhere((i) => i.uniqueId == inst.uniqueId);
    });
    _saveAsDraft();
  }


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
  final VoidCallback? onChanged; // 🚨 NEW: For draft saving triggers

  final String parameterKey; // e.g., 'nivel', 'ph', 'temperatura'
  final String selectedEstacion;
  final bool bypassValidation; // 🚨 NEW
  final bool isReadOnly;

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
    this.onChanged,
    this.bypassValidation = false, // Default to false to keep standard behavior
    this.isReadOnly = false,
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
    // Phase 106: Strict Cosmetic Override for "Sin Historial"
    final bool isSinHistorial = _isOutOfRange && (!widget.hasHistory || widget.minAllowed == null);
    final Color anomalyColor = isSinHistorial ? Colors.orange.shade800 : Colors.redAccent;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Icono Indicador
          if (widget.showLeadingIcon)
            Icon(
              _isValidated 
                  ? Icons.check_circle 
                  : (isSinHistorial 
                      ? Icons.warning_amber_rounded 
                      : (_isOutOfRange ? Icons.error : Icons.cancel)), 
              color: _isValidated 
                  ? Colors.greenAccent 
                  : (_isOutOfRange 
                      ? anomalyColor 
                      : (widget.isDarkMode ? Colors.grey.shade700 : Colors.grey.shade400)), 
              size: 24
            ),
          
          const SizedBox(width: 16),
          
          // Input Field (Exact UI Match)
          Expanded(
            child: TextField(
              readOnly: widget.isReadOnly,
              controller: widget.controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
              ],
              onChanged: (val) {
                setState(() {});
                widget.onChanged?.call();
              },
              style: TextStyle(color: widget.isDarkMode ? Colors.white : Colors.black),
              decoration: InputDecoration(
                labelText: widget.label, // Floating label inside the field
                hintText: widget.hintText,
                labelStyle: const TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.bold, fontSize: 13),
                hintStyle: TextStyle(color: widget.isDarkMode ? Colors.grey[400] : Colors.grey[600], fontSize: 14),
                border: InputBorder.none,
                isDense: true,
                suffixIcon: (!widget.isReadOnly && widget.controller.text.isNotEmpty)
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18, color: Colors.grey),
                        onPressed: () {
                          widget.controller.clear();
                          setState(() {});
                          widget.onChanged?.call();
                        },
                      )
                    : null,
                errorText: _isOutOfRange 
                    ? (!widget.hasHistory || widget.minAllowed == null 
                        ? 'Anómalo: Sin historial' 
                        : 'Anómalo: Fuera de rango') 
                    : null,
                errorStyle: TextStyle(
                  color: anomalyColor, 
                  fontSize: 10, 
                  fontWeight: FontWeight.bold
                ),
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
  final bool isReadOnly;

  const CustomTextInputRow({
    super.key, 
    required this.label, 
    required this.hintText, 
    required this.isDarkMode, 
    this.maxLines = 1, 
    required this.controller,
    this.isMandatory = true,
    this.showLeadingIcon = true,
    this.isReadOnly = false,
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
        readOnly: isReadOnly,
        controller: controller,
        keyboardType: maxLines == null ? TextInputType.multiline : TextInputType.text, maxLines: maxLines, 
        style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface),
        decoration: InputDecoration(hintText: hintText, hintStyle: TextStyle(color: isDarkMode ? Colors.grey.shade400 : Colors.black54, fontSize: 16), border: InputBorder.none, isDense: true, contentPadding: const EdgeInsets.only(top: 4.0)),
      ),
    );
  }
}