import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecurityUtils {
  static Future<bool> requirePin(BuildContext context) async {
    final TextEditingController pinController = TextEditingController();
    final prefs = await SharedPreferences.getInstance();
    
    // Check 'app_pin', then fallback to legacy 'deletion_pin', default to '1234'
    final String correctPin = prefs.getString('app_pin') ?? prefs.getString('deletion_pin') ?? '1234';

    final bool? result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.lock_person, color: Colors.orange),
            SizedBox(width: 10),
            Text('PIN de Seguridad', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Esta acción requiere autorización. Ingrese el PIN para continuar:'),
            const SizedBox(height: 16),
            TextField(
              controller: pinController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'PIN de Seguridad',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () {
              if (pinController.text == correctPin) {
                Navigator.pop(context, true);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('PIN incorrecto'), backgroundColor: Colors.red),
                );
              }
            },
            child: const Text('VERIFICAR'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  static Future<String?> showPinInputDialog(BuildContext context, {required String title}) async {
    final TextEditingController pinController = TextEditingController();
    return await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.lock_outline, color: Colors.blueAccent),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 16))),
          ],
        ),
        content: TextField(
          controller: pinController,
          keyboardType: TextInputType.number,
          maxLength: 4,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'PIN (4 dígitos)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () {
              if (pinController.text.length >= 4) {
                 Navigator.pop(context, pinController.text);
              } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Ingrese 4 dígitos numéricos'), backgroundColor: Colors.red),
                );
              }
            },
            child: const Text('ACEPTAR'),
          ),
        ],
      ),
    );
  }
}
