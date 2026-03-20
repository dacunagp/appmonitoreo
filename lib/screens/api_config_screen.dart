import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../database/database_helper.dart';
import '../widgets/app_drawer.dart';

class ApiConfigScreen extends StatefulWidget {
  const ApiConfigScreen({super.key});

  @override
  State<ApiConfigScreen> createState() => _ApiConfigScreenState();
}

class _ApiConfigScreenState extends State<ApiConfigScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Configuración API'),
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'Servidores', icon: Icon(Icons.dns, size: 24)),
              Tab(text: 'Endpoints', icon: Icon(Icons.api, size: 24)),
              Tab(text: 'Seguridad', icon: Icon(Icons.security, size: 24)),
            ],
          ),
        ),
        drawer: const AppDrawer(currentRoute: '/api_config'),
        body: const TabBarView(
          children: [
            UrlAccessTab(),
            EndpointsTab(),
            SecurityTab(),
          ],
        ),
      ),
    );
  }
}

class UrlAccessTab extends StatefulWidget {
  const UrlAccessTab({super.key});

  @override
  State<UrlAccessTab> createState() => _UrlAccessTabState();
}

class _UrlAccessTabState extends State<UrlAccessTab> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Map<String, dynamic>> _urls = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final data = await _dbHelper.getUrlAccess();
    setState(() {
      _urls = data;
      _isLoading = false;
    });
  }

  Future<void> _testConnection(String url) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Probando conexión...'), duration: Duration(seconds: 1)),
    );

    final stopwatch = Stopwatch()..start();
    try {
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      stopwatch.stop();

      final status = response.statusCode;
      final time = stopwatch.elapsedMilliseconds;
      final bool isReachable = status >= 200 && status < 500;

      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(isReachable ? '✅ Conexión Exitosa' : '⚠️ Error de Servidor'),
            content: Text('Código HTTP: $status\nTiempo de respuesta: ${time}ms'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
        );
      }
    } catch (e) {
      stopwatch.stop();
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('❌ Conexión Fallida'),
            content: Text('No se pudo contactar al servidor.\nError: $e'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
        );
      }
    }
  }

  void _showFormDialog({Map<String, dynamic>? item}) {
    final bool isEdit = item != null;
    final cUrl = TextEditingController(text: isEdit ? item['url'] : '');
    final cUser = TextEditingController(text: isEdit ? item['usuario'] : '');
    final cPass = TextEditingController(text: isEdit ? item['contrasenia'] : '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${isEdit ? 'Editar' : 'Agregar'} Servidor'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: cUrl, decoration: const InputDecoration(labelText: 'URL Base')),
              TextField(controller: cUser, decoration: const InputDecoration(labelText: 'Usuario')),
              TextField(controller: cPass, decoration: const InputDecoration(labelText: 'Contraseña'), obscureText: true),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
          ElevatedButton(
            onPressed: () async {
              final val = {
                'url': cUrl.text.trim(),
                'usuario': cUser.text.trim(),
                'contrasenia': cPass.text.trim(),
                'is_active': isEdit ? item['is_active'] : 0,
              };
              if (isEdit) val['id'] = item['id'];

              isEdit ? await _dbHelper.updateUrlAccess(val) : await _dbHelper.addUrlAccess(val);
              if (mounted) Navigator.pop(context);
              _loadData();
            },
            child: const Text('GUARDAR'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Scaffold(
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 12),
        itemCount: _urls.length,
        itemBuilder: (context, index) {
          final item = _urls[index];
          final bool isActive = item['is_active'] == 1;

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            elevation: isActive ? 6 : 2,
            shadowColor: isActive ? theme.primaryColor.withOpacity(0.4) : null,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
              side: isActive ? BorderSide(color: theme.primaryColor, width: 2) : BorderSide.none,
            ),
            child: ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              leading: Radio<int>(
                value: item['id'],
                fillColor: MaterialStateProperty.resolveWith<Color>((states) {
                  if (states.contains(MaterialState.selected)) {
                    return theme.colorScheme.primary;
                  }
                  return theme.colorScheme.onSurface.withOpacity(0.6);
                }),
                groupValue: _urls.firstWhere((u) => u['is_active'] == 1, orElse: () => {'id': -1})['id'],
                onChanged: (val) async {
                  if (val != null) {
                    await _dbHelper.setActiveUrl(val);
                    _loadData();
                  }
                },
              ),
                title: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item['url'], 
                            style: TextStyle(
                              fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                              fontSize: 14,
                              // Elige el color primario del tema para resaltar servidores activos
                              color: isActive ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.person, size: 12, color: isDarkMode ? Colors.white70 : Colors.grey[600]),
                              const SizedBox(width: 4),
                              Text(
                                item['usuario'], 
                                style: TextStyle(
                                  fontSize: 12, 
                                  color: isDarkMode ? Colors.white70 : Colors.grey[700]
                                )
                              ),
                              const SizedBox(width: 8),
                              if (isActive) 
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: theme.primaryColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    'ACTIVO', 
                                    style: TextStyle(
                                      fontSize: 10, 
                                      fontWeight: FontWeight.bold, 
                                      color: isDarkMode ? Colors.lightBlueAccent : Colors.blue.shade700
                                    )
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.network_ping, color: Colors.blueAccent),
                          onPressed: () => _testConnection(item['url']),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.orangeAccent),
                          onPressed: () => _showFormDialog(item: item),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.redAccent),
                          onPressed: () async {
                            final result = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Eliminar Servidor'),
                                content: const Text('¿Está seguro de que desea eliminar este servidor?'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('NO')),
                                  TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('SÍ', style: TextStyle(color: Colors.red))),
                                ],
                              ),
                            );
                            if (result == true) {
                              await _dbHelper.deleteUrlAccess(item['id']);
                              _loadData();
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showFormDialog(),
        label: const Text('Agregar Servidor', style: TextStyle(color: Colors.white)),
        icon: const Icon(Icons.add, color: Colors.white),
        backgroundColor: theme.primaryColor,
      ),
    );
  }
}

class EndpointsTab extends StatefulWidget {
  const EndpointsTab({super.key});

  @override
  State<EndpointsTab> createState() => _EndpointsTabState();
}

class _EndpointsTabState extends State<EndpointsTab> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Map<String, dynamic>> _endpoints = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final data = await _dbHelper.getEndpoints();
    setState(() {
      _endpoints = data;
      _isLoading = false;
    });
  }

  void _showFormDialog({Map<String, dynamic>? item}) {
    final bool isEdit = item != null;
    final cName = TextEditingController(text: isEdit ? item['nombre'] : '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${isEdit ? 'Editar' : 'Agregar'} Endpoint'),
        content: TextField(controller: cName, decoration: const InputDecoration(labelText: 'Nombre del Endpoint')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
          ElevatedButton(
            onPressed: () async {
              if (cName.text.trim().isEmpty) return;
              isEdit 
                ? await _dbHelper.updateEndpoint(item['id'], cName.text.trim()) 
                : await _dbHelper.addEndpoint(cName.text.trim());
              if (mounted) Navigator.pop(context);
              _loadData();
            },
            child: const Text('GUARDAR'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      body: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 10),
        itemCount: _endpoints.length,
        itemBuilder: (context, index) {
          final item = _endpoints[index];
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.blueAccent,
                child: Icon(Icons.link, color: Colors.white, size: 20),
              ),
              title: Text(
                item['nombre'], 
                style: const TextStyle(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),
                    onPressed: () => _showFormDialog(item: item),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () async {
                      await _dbHelper.deleteEndpoint(item['id']);
                      _loadData();
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showFormDialog(),
        mini: true,
        backgroundColor: Colors.blueAccent,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

class SecurityTab extends StatefulWidget {
  const SecurityTab({super.key});

  @override
  State<SecurityTab> createState() => _SecurityTabState();
}

class _SecurityTabState extends State<SecurityTab> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  String _currentPin = '';
  bool _isLoading = true;
  bool _isObscured = true;

  @override
  void initState() {
    super.initState();
    _loadPin();
  }

  Future<void> _loadPin() async {
    setState(() => _isLoading = true);
    final pin = await _dbHelper.getPin();
    setState(() {
      _currentPin = pin ?? '4567';
      _isLoading = false;
    });
  }

  void _showUpdatePinDialog() {
    final cCurrent = TextEditingController();
    final cNew = TextEditingController();
    final cConfirm = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cambiar PIN de Seguridad'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: cCurrent,
                decoration: const InputDecoration(labelText: 'PIN Actual'),
                keyboardType: TextInputType.number,
                obscureText: true,
              ),
              TextField(
                controller: cNew,
                decoration: const InputDecoration(labelText: 'Nuevo PIN (4 dígitos)'),
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 4,
              ),
              TextField(
                controller: cConfirm,
                decoration: const InputDecoration(labelText: 'Confirmar Nuevo PIN'),
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 4,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCELAR')),
          ElevatedButton(
            onPressed: () async {
              if (cCurrent.text != _currentPin) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN actual incorrecto'), backgroundColor: Colors.red));
                return;
              }
              if (cNew.text.length != 4 || cNew.text != cConfirm.text) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Los PIN nuevos no coinciden o no tienen 4 dígitos'), backgroundColor: Colors.red));
                return;
              }

              await _dbHelper.updatePin(cNew.text);
              if (mounted) Navigator.pop(context);
              _loadPin();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN actualizado correctamente')));
              }
            },
            child: const Text('ACTUALIZAR'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  const Icon(Icons.security, size: 64, color: Colors.blue),
                  const SizedBox(height: 16),
                  const Text(
                    'Gestión de Seguridad',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Este PIN es necesario para acceder a la configuración de la API y proteger la integridad de la sincronización.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    color: Theme.of(context).brightness == Brightness.dark ? Colors.white10 : Colors.grey[100],
                    child: ListTile(
                      title: const Text('PIN Actual', style: TextStyle(fontWeight: FontWeight.bold)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _isObscured ? '****' : _currentPin,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2),
                          ),
                          IconButton(
                            icon: Icon(_isObscured ? Icons.visibility : Icons.visibility_off),
                            onPressed: () => setState(() => _isObscured = !_isObscured),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _showUpdatePinDialog,
                      icon: const Icon(Icons.edit, color: Colors.white),
                      label: const Text('CAMBIAR PIN', style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
