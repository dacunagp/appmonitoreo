import 'dart:io';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:share_plus/share_plus.dart';
import '../widgets/app_drawer.dart';

class ExportarBDScreen extends StatelessWidget {
  const ExportarBDScreen({super.key});

  Future<void> _exportarBaseDeDatos(BuildContext context) async {
    try {
      final String dbFolderPath = await getDatabasesPath();
      final String dbPath = join(dbFolderPath, 'collector.db');
      final File dbFile = File(dbPath);

      if (await dbFile.exists()) {
        await Share.shareXFiles(
          [XFile(dbPath)],
          text: 'Respaldo Base de Datos (collector.db)',
        );
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error: La base de datos no fue encontrada.'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al exportar: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Exportar Base de Datos'),
      ),
      drawer: const AppDrawer(currentRoute: '/exportar_bd'),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.storage_rounded,
                size: 100,
                color: isDarkMode ? Colors.white : theme.primaryColor,
              ),
              const SizedBox(height: 32),
              Text(
                'Copia de Seguridad Local',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Exporte una copia de seguridad local de la base de datos de la aplicación. Puede compartir este archivo por WhatsApp, Email u otros medios para respaldar sus datos.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDarkMode ? Colors.white70 : Colors.black54,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _exportarBaseDeDatos(context),
                  icon: const Icon(Icons.share_rounded),
                  label: const Text(
                    'COMPARTIR BASE DE DATOS',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    backgroundColor: theme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 2,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Archivo: collector.db',
                style: TextStyle(
                  fontSize: 12,
                  color: isDarkMode ? Colors.white38 : Colors.black26,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
