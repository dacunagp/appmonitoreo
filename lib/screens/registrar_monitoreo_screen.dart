// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import '../widgets/app_drawer.dart';
import '../database/database_helper.dart';
import '../models/models.dart';

class RegistrarMonitoreoScreen extends StatefulWidget {
  const RegistrarMonitoreoScreen({super.key});

  @override
  State<RegistrarMonitoreoScreen> createState() => _RegistrarMonitoreoScreenState();
}

class _RegistrarMonitoreoScreenState extends State<RegistrarMonitoreoScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();

  // --- 1. VARIABLES DE ESTADO ---
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isMonitoreoFallido = false;
  DateTime? _fechaYHoraMuestreo; 

  // Listas para dropdowns
  List<Program> _programas = [];
  List<Station> _estaciones = [];
  List<Matriz> _matrices = [];
  List<Map<String, dynamic>> _equiposMulti = [];
  List<Map<String, dynamic>> _turbidimetros = [];
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

  bool? _muestreoHidroquimico; 
  bool? _muestreoIsotopico;

  @override
  void initState() {
    super.initState();
    _loadDropdownData();
  }

  @override
  void dispose() {
    _tempController.dispose();
    _phController.dispose();
    _condController.dispose();
    _oxigenoController.dispose();
    _turbiedadController.dispose();
    _codLabController.dispose();
    _obsController.dispose();
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
        _equiposMultiOptions = multiData.map((e) => e['codigo'].toString()).toList();
        
        _turbidimetros = turbiData;
        _turbidimetrosOptions = turbiData.map((e) => e['codigo'].toString()).toList();
        
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
      setState(() => _isLoading = false);
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
  }

  Future<void> _guardarMonitoreo() async {
    // 1. Validation
    if (_programaSeleccionado == null || _estacionSeleccionada == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Debe seleccionar Programa y Punto de Control')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      // Find Inspector ID
      int? inspectorId;
      if (_inspectorSeleccionado != null) {
        final usuarios = await _dbHelper.getUsuarios();
        try {
          final inspector = usuarios.firstWhere((u) => '${u.nombre} ${u.apellido}' == _inspectorSeleccionado);
          inspectorId = inspector.idUsuario;
        } catch (_) {}
      }

      // 2. Data Mapping & Conversion
      final registro = {
        'programa_id': _programaSeleccionado!.id,
        'estacion_id': _estacionSeleccionada!.id,
        'fecha_hora': _fechaYHoraMuestreo?.toIso8601String() ?? DateTime.now().toIso8601String(),
        'monitoreo_fallido': _isMonitoreoFallido ? 1 : 0,
        'observacion': _obsController.text,
        'matriz_id': _matrizSeleccionada?.idMatriz,
        'equipo_multi_id': _equiposMulti.firstWhere((e) => e['codigo'] == _equipoMultiparametroSeleccionado, orElse: () => {'id': null})['id'],
        'temp': double.tryParse(_tempController.text),
        'ph': double.tryParse(_phController.text),
        'conductividad': double.tryParse(_condController.text),
        'oxigeno': double.tryParse(_oxigenoController.text),
        'turbidimetro_id': _turbidimetros.firstWhere((e) => e['codigo'] == _turbidimetroSeleccionado, orElse: () => {'id': null})['id'],
        'turbiedad': double.tryParse(_turbiedadController.text),
        'metodo_id': _metodoSeleccionado?.idMetodo,
        'hidroquimico': _muestreoHidroquimico == true ? 1 : 0,
        'isotopico': _muestreoIsotopico == true ? 1 : 0,
        'cod_laboratorio': _codLabController.text,
        'usuario_id': inspectorId,
      };

      // 3. Insertion
      await _dbHelper.addRegistroMonitoreo(registro);

      // 4. Success
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Monitoreo guardado exitosamente'),
            backgroundColor: Colors.green,
          ),
        );
        // Redirigir a la lista de monitoreos en lugar de hacer pop
        Navigator.pushReplacementNamed(context, '/monitoreos');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error al guardar: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
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
              child: const ListTile(
                leading: Icon(Icons.assignment_outlined, size: 28, color: Colors.white),
                title: Text('Datos de Monitoreo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.white)),
              ),
            ),
            _buildFormularioDatosMonitoreo(isDarkMode),
          ] else
            _buildSectionTile('Datos de Monitoreo', isDarkMode, [_buildFormularioDatosMonitoreo(isDarkMode)]),

          // --- SECCIONES INFERIORES (Se ocultan si falla el monitoreo) ---
          if (!_isMonitoreoFallido) ...[
            
            // --- SECCIÓN 2: MULTIPARÁMETRO ---
            _buildSectionTile('Multiparámetro', isDarkMode, [
              SearchableDropdown(
                label: 'Equipo Multiparametro',
                hintText: 'Seleccione equipo',
                selectedValue: _equipoMultiparametroSeleccionado,
                options: _equiposMultiOptions,
                isDarkMode: isDarkMode,
                onChanged: (val) => setState(() => _equipoMultiparametroSeleccionado = val),
              ),
              if (_equipoMultiparametroSeleccionado != null) ...[
                CustomParametroInputRow(label: 'Temperatura [°C]', hintText: 'Ingrese Temperatura', isDarkMode: isDarkMode, controller: _tempController),
                CustomParametroInputRow(label: 'pH [u.pH]', hintText: 'Ingrese pH', isDarkMode: isDarkMode, controller: _phController),
                CustomParametroInputRow(label: 'Conductividad [µS/cm]', hintText: 'Ingrese conductividad', isDarkMode: isDarkMode, controller: _condController),
                CustomParametroInputRow(label: 'Oxigeno Disuelto [mg/l]', hintText: 'Ingrese oxigeno disuelto', isDarkMode: isDarkMode, controller: _oxigenoController),
              ],
              const SizedBox(height: 8),
            ]),

            // --- SECCIÓN 3: TURBIEDAD ---
            _buildSectionTile('Turbiedad', isDarkMode, [
              SearchableDropdown(
                label: 'Turbidimetro',
                hintText: 'Seleccione equipo',
                selectedValue: _turbidimetroSeleccionado,
                options: _turbidimetrosOptions,
                isDarkMode: isDarkMode,
                onChanged: (val) => setState(() => _turbidimetroSeleccionado = val),
              ),
              if (_turbidimetroSeleccionado != null)
                CustomParametroInputRow(label: 'Turbiedad [NTU]', hintText: 'Ingrese turbiedad', isDarkMode: isDarkMode, controller: _turbiedadController),
              const SizedBox(height: 8),
            ]),
            
            // --- SECCIÓN 4: MUESTREO ---
            _buildSectionTile('Muestreo', isDarkMode, [
              SearchableDropdown(
                label: 'Método de Muestreo',
                hintText: 'Seleccione método de muestreo',
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
              CustomTextInputRow(label: 'Código Laboratorio', hintText: 'Ingrese código de laboratorio', isDarkMode: isDarkMode, controller: _codLabController),
              CustomTextInputRow(label: 'Descripción / Observación', hintText: 'Ingrese observación / descripción', isDarkMode: isDarkMode, maxLines: null, controller: _obsController),
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
    );
  }

  // --- MÉTODOS Y HELPERS OPTIMIZADOS ---

  Widget _buildFormularioDatosMonitoreo(bool isDarkMode) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor, 
      child: Column(
        children: [
          SearchableDropdown(
            label: 'Programa',
            hintText: 'Seleccione programa',
            selectedValue: _programaSeleccionado?.name,
            options: _programas.map((p) => p.name).toList(),
            isDarkMode: isDarkMode,
            onChanged: _onProgramaChanged,
          ),

          SearchableDropdown(
            label: 'Punto de Control',
            hintText: 'Seleccione estación',
            selectedValue: _estacionSeleccionada?.name,
            options: _estaciones.map((s) => s.name).toList(),
            isDarkMode: isDarkMode,
            onChanged: (val) {
              setState(() => _estacionSeleccionada = _estaciones.firstWhere((s) => s.name == val));
            },
          ),
          
          SearchableDropdown(
            label: 'Inspector',
            hintText: 'Seleccione inspector',
            selectedValue: _inspectorSeleccionado,
            options: _inspectoresOptions,
            isDarkMode: isDarkMode,
            onChanged: (val) => setState(() => _inspectorSeleccionado = val),
          ),
          
          SearchableDropdown(
            label: 'Matriz de Aguas',
            hintText: 'Seleccione Tipo de Aguas',
            selectedValue: _matrizSeleccionada?.nombreMatriz,
            options: _matrices.map((m) => m.nombreMatriz).toList(),
            isDarkMode: isDarkMode,
            onChanged: (val) {
              setState(() => _matrizSeleccionada = _matrices.firstWhere((m) => m.nombreMatriz == val));
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
            CustomTextInputRow(label: 'Descripción / Observación', hintText: 'Ingrese observación / descripción', isDarkMode: isDarkMode, maxLines: null, controller: _obsController),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildSectionTile(String title, bool isDarkMode, List<Widget> children) {
    return ExpansionTile(
      initiallyExpanded: true,
      iconColor: Colors.blueAccent,
      collapsedIconColor: Colors.blueAccent,
      leading: const Icon(Icons.assignment_outlined, size: 28, color: Colors.blueAccent),
      title: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Theme.of(context).colorScheme.onSurface)),
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

// ============================================================================
// WIDGETS REUTILIZABLES (Adaptados para usar controladores)
// ============================================================================

class SearchableDropdown extends StatefulWidget {
  final String label;
  final String hintText;
  final String? selectedValue;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final bool isDarkMode;

  const SearchableDropdown({super.key, required this.label, required this.hintText, required this.selectedValue, required this.options, required this.onChanged, required this.isDarkMode});

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
                      hintText: 'Buscar...',
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
      leading: Icon(customIcon ?? (isValid ? Icons.check_circle : Icons.cancel), color: customIconColor ?? (isValid ? Colors.greenAccent : Colors.grey.withValues(alpha: 0.5)), size: 24),
      title: Text(label, style: const TextStyle(color: Colors.blueAccent, fontSize: 12)),
      subtitle: Text(value, style: TextStyle(fontSize: 16, color: (isValid || customIcon != null) ? Theme.of(context).colorScheme.onSurface : colorGris)),
      trailing: showArrow ? Icon(Icons.arrow_drop_down, color: colorGris) : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 0.0), dense: true,
      onTap: onTap ?? () => debugPrint('Tapped on $label'),
    );
  }
}

class CustomParametroInputRow extends StatelessWidget {
  final String label, hintText;
  final bool isDarkMode;
  final TextEditingController controller;

  const CustomParametroInputRow({super.key, required this.label, required this.hintText, required this.isDarkMode, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.chevron_right, color: Colors.blueAccent, size: 24),
      title: Text(label, style: const TextStyle(color: Colors.blueAccent, fontSize: 12)),
      subtitle: TextField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true), 
        style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface),
        decoration: InputDecoration(hintText: hintText, hintStyle: TextStyle(color: isDarkMode ? Colors.grey.shade400 : Colors.black54, fontSize: 16), border: InputBorder.none, isDense: true, contentPadding: const EdgeInsets.only(top: 4.0)),
      ),
      trailing: InkWell(
        onTap: () => debugPrint('Botón presionado: $label'),
        borderRadius: BorderRadius.circular(6.0),
        child: Container(
          decoration: BoxDecoration(border: Border.all(color: Colors.blueAccent, width: 1.5), borderRadius: BorderRadius.circular(6.0)),
          padding: const EdgeInsets.all(4.0),
          child: const Icon(Icons.monitor_heart_outlined, color: Colors.blueAccent, size: 20),
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 0.0), dense: true,
    );
  }
}

class CustomTextInputRow extends StatelessWidget {
  final String label, hintText;
  final bool isDarkMode;
  final int? maxLines;
  final TextEditingController controller;

  const CustomTextInputRow({super.key, required this.label, required this.hintText, required this.isDarkMode, this.maxLines = 1, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(Icons.cancel, color: Colors.grey.withValues(alpha: 0.5), size: 24),
      title: Text(label, style: const TextStyle(color: Colors.blueAccent, fontSize: 12)),
      subtitle: TextField(
        controller: controller,
        keyboardType: maxLines == null ? TextInputType.multiline : TextInputType.text, maxLines: maxLines, 
        style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurface),
        decoration: InputDecoration(hintText: hintText, hintStyle: TextStyle(color: isDarkMode ? Colors.grey.shade400 : Colors.black54, fontSize: 16), border: InputBorder.none, isDense: true, contentPadding: const EdgeInsets.only(top: 4.0)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 0.0), dense: true,
    );
  }
}