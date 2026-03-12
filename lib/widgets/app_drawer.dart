import 'package:flutter/material.dart';

class AppDrawer extends StatelessWidget {
  final String currentRoute;

  const AppDrawer({super.key, required this.currentRoute});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF1E1E1E), // Fondo oscuro
      child: Column(
        children: [
          // Header compacto
          const SizedBox(height: 50),
          const Center(
            child: Text(
              'Opciones',
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 15),
          const Divider(color: Colors.white24, thickness: 1),

          // Items del menú
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildMenuItem(
                  context,
                  title: 'Monitoreos',
                  icon: Icons.power_settings_new,
                  targetRoute: '/monitoreos',
                ),
                _buildMenuItem(
                  context,
                  title: 'Registrar Monitoreo',
                  icon: Icons.add_circle_outline,
                  targetRoute: '/registrar_monitoreo',
                ),
                _buildMenuItem(
                  context,
                  title: 'Gráficos',
                  icon: Icons.show_chart,
                  targetRoute: '/graficos',
                ),
                _buildMenuItem(
                  context,
                  title: 'Enviar datos a Servidor',
                  icon: Icons.cloud_upload_outlined,
                  targetRoute: '/enviar_datos',
                ),
                _buildMenuItem(
                  context,
                  title: 'ConectorWeb',
                  icon: Icons.cloud_download_outlined,
                  targetRoute: '/conector_web',
                ),
                _buildMenuItem(
                  context,
                  title: 'Historial',
                  icon: Icons.folder_outlined,
                  targetRoute: '/historial',
                ),
                _buildMenuItem(
                  context,
                  title: 'Info',
                  icon: Icons.info_outline,
                  targetRoute: '/info',
                ),
                _buildMenuItem(
                  context,
                  title: 'Usuarios',
                  icon: Icons.person_outline,
                  targetRoute: '/usuarios',
                ),
                _buildMenuItem(
                  context,
                  title: 'Estaciones',
                  icon: Icons.location_on_outlined,
                  targetRoute: '/estaciones',
                ),
                _buildMenuItem(
                  context,
                  title: 'Campañas',
                  icon: Icons.layers_outlined,
                  targetRoute: '/campanas',
                ),
                const Divider(color: Colors.white24),
                _buildMenuItem(
                  context,
                  title: 'Administración',
                  icon: Icons.storage_outlined,
                  targetRoute: '/administracion',
                ),
                _buildMenuItem(
                  context,
                  title: 'Settings',
                  icon: Icons.settings_outlined,
                  targetRoute: '/settings',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required String title,
    required IconData icon,
    required String targetRoute,
  }) {
    final bool isSelected = currentRoute == targetRoute;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFF1E293B) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: isSelected ? Colors.blueAccent : Colors.white70,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.blueAccent : Colors.white70,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 15,
          ),
        ),
        onTap: () {
          // 1. Cerrar el drawer primero
          Navigator.pop(context);
          // 2. Navegar solo si es una ruta distinta
          if (currentRoute != targetRoute) {
            Navigator.pushReplacementNamed(context, targetRoute);
          }
        },
      ),
    );
  }
}
