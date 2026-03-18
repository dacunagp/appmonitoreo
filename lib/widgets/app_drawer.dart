import 'package:flutter/material.dart';

class AppDrawer extends StatelessWidget {
  final String currentRoute;

  const AppDrawer({super.key, required this.currentRoute});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Drawer(
      backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFFBFBFB),
      child: Column(
        children: [
          // Header compacto
          const SizedBox(height: 50),
          Center(
            child: Text(
              'Opciones',
              style: TextStyle(
                color: isDarkMode ? Colors.white : const Color(0xFF212121),
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 15),
          Divider(
            color: isDarkMode ? Colors.white24 : Colors.grey[300],
            thickness: 1,
            indent: 20,
            endIndent: 20,
          ),

          // Items del menú
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildMenuItem(
                  context,
                  title: 'Monitoreos',
                  icon: Icons.engineering,
                  targetRoute: '/monitoreos',
                  isDarkMode: isDarkMode,
                ),
                _buildMenuItem(
                  context,
                  title: 'Registrar Monitoreo',
                  icon: Icons.add_circle_outline,
                  targetRoute: '/registrar_monitoreo',
                  isDarkMode: isDarkMode,
                ),
                _buildMenuItem(
                  context,
                  title: 'Gráficos',
                  icon: Icons.show_chart,
                  targetRoute: '/graficos',
                  isDarkMode: isDarkMode,
                ),
                _buildMenuItem(
                  context,
                  title: 'Enviar datos a Servidor',
                  icon: Icons.cloud_upload_outlined,
                  targetRoute: '/enviar_datos',
                  isDarkMode: isDarkMode,
                ),
                _buildMenuItem(
                  context,
                  title: 'ConectorWeb',
                  icon: Icons.cloud_download_outlined,
                  targetRoute: '/conector_web',
                  isDarkMode: isDarkMode,
                ),
                _buildMenuItem(
                  context,
                  title: 'Historial',
                  icon: Icons.folder_outlined,
                  targetRoute: '/historial',
                  isDarkMode: isDarkMode,
                ),
                _buildMenuItem(
                  context,
                  title: 'Info',
                  icon: Icons.info_outline,
                  targetRoute: '/info',
                  isDarkMode: isDarkMode,
                ),
                _buildMenuItem(
                  context,
                  title: 'Usuarios',
                  icon: Icons.person_outline,
                  targetRoute: '/usuarios',
                  isDarkMode: isDarkMode,
                ),
                _buildMenuItem(
                  context,
                  title: 'Estaciones',
                  icon: Icons.location_on_outlined,
                  targetRoute: '/estaciones',
                  isDarkMode: isDarkMode,
                ),
                _buildMenuItem(
                  context,
                  title: 'Campañas',
                  icon: Icons.layers_outlined,
                  targetRoute: '/campanas',
                  isDarkMode: isDarkMode,
                ),
                Divider(
                  color: isDarkMode ? Colors.white24 : Colors.grey[300],
                  indent: 20,
                  endIndent: 20,
                ),
                _buildMenuItem(
                  context,
                  title: 'Administración',
                  icon: Icons.storage_outlined,
                  targetRoute: '/administracion',
                  isDarkMode: isDarkMode,
                ),
                _buildMenuItem(
                  context,
                  title: 'Exportar BD',
                  icon: Icons.save_alt,
                  targetRoute: '/exportar_bd',
                  isDarkMode: isDarkMode,
                ),
                _buildMenuItem(
                  context,
                  title: 'Settings',
                  icon: Icons.settings_outlined,
                  targetRoute: '/settings',
                  isDarkMode: isDarkMode,
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
    required bool isDarkMode,
  }) {
    final bool isSelected = currentRoute == targetRoute;
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected
            ? (isDarkMode ? const Color(0xFF1E293B) : theme.primaryColor)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        boxShadow: isSelected && !isDarkMode
            ? [
                BoxShadow(
                  color: theme.primaryColor.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                )
              ]
            : null,
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: isSelected
              ? Colors.white
              : (isDarkMode ? Colors.white70 : const Color(0xFF757575)),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isSelected
                ? Colors.white
                : (isDarkMode ? Colors.white70 : const Color(0xFF212121)),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 15,
          ),
        ),
        onTap: () {
          Navigator.pop(context);
          if (currentRoute != targetRoute) {
            Navigator.pushReplacementNamed(context, targetRoute);
          }
        },
      ),
    );
  }
}
