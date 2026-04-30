import 'dart:io';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter/services.dart'; // For rootBundle if needed, though not here

import 'theme/app_theme.dart';
import 'theme/theme_provider.dart';
import 'providers/graph_provider.dart';
import 'database/database_helper.dart';
import 'screens/monitoreos_screen.dart';
import 'screens/registrar_monitoreo_screen.dart';
import 'screens/graficos_screen.dart';
import 'screens/enviar_datos_screen.dart';
import 'screens/conector_web_screen.dart';
import 'screens/historial_screen.dart';
import 'screens/info_screen.dart';
import 'screens/usuarios_screen.dart';
import 'screens/estaciones_screen.dart';
import 'screens/campanas_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/administracion_screen.dart';
import 'screens/api_config_screen.dart';
import 'screens/security_lock_screen.dart';
import 'screens/notificaciones_screen.dart';
import 'services/sync_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    try {
      if (task == "sync-monitoreos-task" || task == "autoSyncTask") {
        await SyncService().performAutoSync();
      }
      return Future.value(true);
    } catch (e) {
      debugPrint('🚨 Workmanager task failed: $e');
      return Future.value(false);
    }
  });
}

Future<String?> _encodeImage(String? path) async {
  if (path == null || path.isEmpty) return null;
  final file = File(path);
  if (!file.existsSync()) return null;
  try {
    // 🚨 COMPRESS BEFORE ENCODING TO BASE64 (Background task)
    final Uint8List? compressedBytes = await FlutterImageCompress.compressWithFile(
      path,
      minWidth: 800,
      minHeight: 800,
      quality: 70,
    );
    if (compressedBytes != null) {
      return base64Encode(compressedBytes);
    } else {
      return base64Encode(file.readAsBytesSync());
    }
  } catch (e) {
    debugPrint('Error en sync background comprimiendo: $e');
    return base64Encode(file.readAsBytesSync());
  }
}

Future<void> _guardarNotificacionLocal(OSNotification notification) async {
  final String titulo = notification.title ?? 'Sin título';
  final String mensaje = notification.body ?? '';
  final Map<String, dynamic>? additionalData = notification.additionalData;
  
  String payloadJson = '';
  if (additionalData != null && additionalData.isNotEmpty) {
    payloadJson = jsonEncode(additionalData);
  }
  
  try {
    await DatabaseHelper().insertarNotificacion({
      'titulo': titulo,
      'mensaje': mensaje,
      'payload': payloadJson,
      'fecha': DateTime.now().toIso8601String(),
    });
    debugPrint('✅ [OneSignal] Notificación guardada en BD local desde ${notification.title}.');
  } catch (e) {
    debugPrint('🚨 [OneSignal] Error al guardar notificación: $e');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // OneSignal
  OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
  OneSignal.initialize("8123fc88-aea9-4d85-9a36-8be4248fd004");
  OneSignal.Notifications.requestPermission(true);

  OneSignal.Notifications.addForegroundWillDisplayListener((event) async {
    debugPrint('🔔 [OneSignal] Notificación recibida en primer plano: ${event.notification.title}');
    await _guardarNotificacionLocal(event.notification);
    event.notification.display();
  });

  OneSignal.Notifications.addClickListener((event) async {
    debugPrint('👆 [OneSignal] Notificación tocada: ${event.notification.title}');
    await _guardarNotificacionLocal(event.notification);
  });
  
  Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: true,
  );

  Workmanager().registerPeriodicTask(
    "1",
    "sync-monitoreos-task",
    frequency: const Duration(minutes: 15),
    constraints: Constraints(
      networkType: NetworkType.connected,
    ),
  );

  // Connectivity listener for foreground auto-sync
  Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
    if (results.any((result) => result != ConnectivityResult.none)) {
      debugPrint('🌐 [Connectivity] Device online, triggering sync...');
      SyncService().performAutoSync();
    }
  });

  await dotenv.load(fileName: ".env");

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => GraphProvider()),
      ],
      child: const MonitoreoApp(),
    ),
  );
}

class MonitoreoApp extends StatelessWidget {
  const MonitoreoApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      title: 'Monitoreo App',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeProvider.themeMode,
      initialRoute: '/monitoreos',
      routes: {
        '/monitoreos': (context) => const MonitoreosScreen(),
        '/registrar_monitoreo': (context) => const RegistrarMonitoreoScreen(),
        '/graficos': (context) => const GraficosScreen(),
        '/enviar_datos': (context) => const EnviarDatosScreen(),
        '/conector_web': (context) => const ConectorWebScreen(),
        '/historial': (context) => const HistorialScreen(),
        '/info': (context) => const InfoScreen(),
        '/usuarios': (context) => const UsuariosScreen(),
        '/estaciones': (context) => const EstacionesScreen(),
        '/campanas': (context) => const CampanasScreen(),
        '/settings': (context) => const SettingsScreen(),
        '/administracion': (context) => const AdministracionScreen(),
        '/api_config': (context) => const ApiConfigScreen(),
        '/security_lock': (context) => const SecurityLockScreen(),
        '/notificaciones': (context) => const NotificacionesScreen(),
      },
    );
  }
}
