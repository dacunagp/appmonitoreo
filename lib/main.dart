import 'dart:io';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:workmanager/workmanager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

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
import 'screens/exportar_bd_screen.dart';
import 'screens/api_config_screen.dart';
import 'screens/security_lock_screen.dart';
import 'screens/notificaciones_screen.dart';

import 'package:onesignal_flutter/onesignal_flutter.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();

    final prefs = await SharedPreferences.getInstance();
    final bool autoSync = prefs.getBool('auto_sync') ?? false;
    if (!autoSync) return Future.value(true);

    final dbHelper = DatabaseHelper();
    final List<Map<String, dynamic>> pending = await dbHelper.getPendingToSendMonitoreos();
    
    if (pending.isEmpty) return Future.value(true);

    try {
      final config = await dbHelper.getActiveUrlConfig();
      if (config == null) return Future.value(false);

      final endpoints = await dbHelper.getEndpoints();
      String endpointPath = 'sync/monitoreos';
      try {
        final target = endpoints.firstWhere((e) => e['nombre'].toString().contains('sync'));
        endpointPath = target['nombre'];
      } catch (_) {}

      final Uri syncUrl = Uri.parse(config['url'] + endpointPath);
      final String token = prefs.getString('token') ?? '';
      
      List<Map<String, dynamic>> payloadList = [];
      for (var record in pending) {
        payloadList.add({
          "id": record['id'],
          "device_id": "BACKGROUND-AUTO",
          "programa_id": record['programa_id'],
          "estacion_id": record['estacion_id'],
          "fecha_hora": record['fecha_hora'],
          "monitoreo_fallido": record['monitoreo_fallido'],
          "observacion": record['observacion'],
          "matriz_id": record['matriz_id'],
          "equipo_multi_id": record['equipo_multi_id'],
          "turbidimetro_id": record['turbidimetro_id'],
          "metodo_id": record['metodo_id'],
          "hidroquimico": record['hidroquimico'],
          "isotopico": record['isotopico'],
          "cod_laboratorio": record['cod_laboratorio'],
          "usuario_id": record['usuario_id'],
          "is_draft": 0,
          "equipo_nivel_id": record['equipo_nivel_id'],
          "tipo_pozo": record['tipo_pozo'],
          "fecha_hora_nivel": record['fecha_hora_nivel'],
          "temperatura": record['temperatura'],
          "ph": record['ph'],
          "conductividad": record['conductividad'],
          "oxigeno": record['oxigeno'],
          "turbiedad": record['turbiedad'],
          "profundidad": record['profundidad'],
          "nivel": record['nivel'],
          "latitud": record['latitud'],
          "longitud": record['longitud'],
          "foto_path": _encodeImage(record['foto_path']),
          "foto_multiparametro": _encodeImage(record['foto_multiparametro']),
          "foto_turbiedad": _encodeImage(record['foto_turbiedad']),
        });
      }

      final payload = {"monitoreos": payloadList};
      
      Map<String, String> headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

      if (token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      } else {
        final auth = '${config['usuario']}:${config['contrasenia']}';
        headers['Authorization'] = 'Basic ${base64Encode(utf8.encode(auth))}';
      }

      final response = await http.post(
        syncUrl,
        headers: headers,
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final db = await dbHelper.database;
        for (var record in pending) {
          await db.update('monitoreos', {'is_draft': 2}, where: 'id = ?', whereArgs: [record['id']]);
        }
      }
      return Future.value(true);
    } catch (e) {
      debugPrint('🚨 Workmanager task failed: $e');
      return Future.value(false);
    }
  });
}

String? _encodeImage(String? path) {
  if (path == null || path.isEmpty) return null;
  final file = File(path);
  if (!file.existsSync()) return null;
  return base64Encode(file.readAsBytesSync());
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
    "autoSyncTask",
    frequency: const Duration(minutes: 15),
    constraints: Constraints(
      networkType: NetworkType.connected,
    ),
  );

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
        '/exportar_bd': (context) => const ExportarBDScreen(),
        '/api_config': (context) => const ApiConfigScreen(),
        '/security_lock': (context) => const SecurityLockScreen(),
        '/notificaciones': (context) => const NotificacionesScreen(),
      },
    );
  }
}
