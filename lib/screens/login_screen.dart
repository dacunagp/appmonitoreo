import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../database/database_helper.dart';
import '../models/models.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  final _apiService = ApiService();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  
  bool _isLoading = false;
  bool _isSyncing = false;
  bool _obscurePassword = true;
  String _appVersion = '1.6.10'; // Fallback default version

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeIn,
    );
    _animationController.forward();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = packageInfo.version;
        });
      }
    } catch (e) {
      // Keep fallback version
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, ingresa correo y contraseña')),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final result = await _authService.loginLocal(email, password);

      if (result['success'] == true && mounted) {
        Navigator.pushReplacementNamed(context, '/monitoreos');
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Error al iniciar sesión.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSync() async {
    setState(() => _isSyncing = true);
    try {
      await _apiService.fetchAllData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Datos maestros sincronizados con éxito')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al sincronizar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDarkMode 
              ? [
                  const Color(0xFF1B5E20).withOpacity(0.4),
                  const Color(0xFF0D47A1).withOpacity(0.4),
                  const Color(0xFF121212),
                ]
              : [
                  const Color(0xFF2EAF5F).withOpacity(0.8),
                  const Color(0xFF0084CA).withOpacity(0.8),
                  Colors.white,
                ],
            stops: isDarkMode ? null : const [0.0, 0.5, 1.0],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo
                  Hero(
                    tag: 'logo',
                    child: Container(
                      height: 120,
                      width: 120,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 20,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/gp_logo_icon.png',
                          fit: BoxFit.cover,
                          errorBuilder: (c, e, s) => const Icon(Icons.water_drop, size: 60, color: Colors.blue),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  Text(
                    'Iniciar Sesión',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Ingresa tus credenciales para continuar',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 48),
                  
                  // Login Form
                  Card(
                    elevation: 8,
                    shadowColor: Colors.black12,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Correo Electrónico',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              labelText: 'Contraseña',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _handleLogin,
                              child: _isLoading 
                                ? const CircularProgressIndicator(color: Colors.white) 
                                : const Text('INGRESAR', style: TextStyle(fontSize: 16)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Sync Button
                  OutlinedButton.icon(
                    onPressed: _isSyncing ? null : _handleSync,
                    icon: _isSyncing 
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync),
                    label: Text(
                      _isSyncing ? 'SINCRONIZANDO...' : 'SINCRONIZAR USUARIOS',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: isDarkMode ? Colors.white.withOpacity(0.05) : Colors.white,
                      side: BorderSide(color: isDarkMode ? Colors.white30 : const Color(0xFF0084CA)),
                      foregroundColor: isDarkMode ? Colors.white : const Color(0xFF0084CA),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      elevation: isDarkMode ? 0 : 2,
                    ),
                  ),
                  
                  const SizedBox(height: 40),
                  Text(
                    'v$_appVersion - GP Consultores',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isDarkMode ? Colors.white54 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
