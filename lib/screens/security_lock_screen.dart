import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../database/database_helper.dart';

class SecurityLockScreen extends StatefulWidget {
  const SecurityLockScreen({super.key});

  @override
  State<SecurityLockScreen> createState() => _SecurityLockScreenState();
}

class _SecurityLockScreenState extends State<SecurityLockScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final List<TextEditingController> _controllers = List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _focusNodes = List.generate(4, (_) => FocusNode());
  bool _isError = false;

  @override
  void dispose() {
    for (var c in _controllers) {
      c.dispose();
    }
    for (var f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _onChanged(String value, int index) {
    if (value.isNotEmpty) {
      if (index < 3) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _validatePin();
      }
    } else {
      if (index > 0) {
        _focusNodes[index - 1].requestFocus();
      }
    }
  }

  Future<void> _validatePin() async {
    final enteredPin = _controllers.map((c) => c.text).join();
    final storedPin = await _dbHelper.getPin();

    if (enteredPin == storedPin) {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/api_config');
      }
    } else {
      setState(() {
        _isError = true;
      });
      // Clear after a short delay
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          setState(() {
            _isError = false;
            for (var c in _controllers) {
              c.clear();
            }
            _focusNodes[0].requestFocus();
          });
        }
      });
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
          // Force navigation back to the main screen instead of exiting
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/monitoreos',
            (route) => false,
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Seguridad'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/monitoreos',
                (route) => false,
              );
            },
          ),
          elevation: 0,
          backgroundColor: Colors.transparent,
          foregroundColor: isDarkMode ? Colors.white : Colors.black,
        ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline,
                size: 100,
                color: _isError ? Colors.red : theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Ingresa tu clave',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: _isError ? Colors.red : null,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Para acceder a la configuración de la API, ingresa el PIN de seguridad.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 40),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(4, (index) {
                  return SizedBox(
                    width: 60,
                    child: TextField(
                      controller: _controllers[index],
                      focusNode: _focusNodes[index],
                      autofocus: index == 0,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      obscureText: true,
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      maxLength: 1,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        counterText: '',
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: _isError ? Colors.red : theme.colorScheme.outline,
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(
                            color: _isError ? Colors.red : theme.primaryColor,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onChanged: (val) => _onChanged(val, index),
                    ),
                  );
                }),
              ),
              if (_isError) ...[
                const SizedBox(height: 20),
                const Text(
                  'PIN incorrecto. Inténtalo de nuevo.',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
}
