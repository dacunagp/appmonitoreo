import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // <-- IMPORTANTE: Importamos el paquete

import 'theme/app_theme.dart';
import 'theme/theme_provider.dart';
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

void main() async {
  // 1. Aseguramos que Flutter esté listo antes de ejecutar código asíncrono
  WidgetsFlutterBinding.ensureInitialized();
  
  // 2. Cargamos las variables de entorno desde el archivo .env
  await dotenv.load(fileName: ".env");

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
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
      },
    );
  }
}