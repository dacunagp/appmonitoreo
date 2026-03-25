import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import '../database/database_helper.dart';
import '../widgets/app_drawer.dart';

/// Pantalla que muestra el historial de notificaciones push recibidas.
class NotificacionesScreen extends StatefulWidget {
  const NotificacionesScreen({super.key});

  @override
  State<NotificacionesScreen> createState() => _NotificacionesScreenState();
}
class _NotificacionesScreenState extends State<NotificacionesScreen> {
  final DatabaseHelper _dbHelper = DatabaseHelper();
  List<Map<String, dynamic>> _notificaciones = [];
  bool _isLoading = true;
  StreamSubscription<List<Map<String, dynamic>>>? _sub;

  @override
  void initState() {
    super.initState();
    _cargarNotificaciones();
    
    // Escuchar el stream para reactividad (ej. cuando llega notificación en primer plano)
    _sub = _dbHelper.notificacionesStream.listen((data) {
      if (mounted) {
        setState(() {
          _notificaciones = data;
          _isLoading = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _cargarNotificaciones() async {
    final data = await _dbHelper.obtenerNotificaciones();
    if (mounted) {
      setState(() {
        _notificaciones = data;
        _isLoading = false;
      });
    }
  }

  Future<void> _eliminarNotificacion(int id) async {
    await _dbHelper.deleteNotificacion(id); // esto ya triggerea el stream
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Notificación eliminada'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _eliminarTodas() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar'),
        content: const Text('¿Eliminar todas las notificaciones?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirmar == true) {
      await _dbHelper.deleteAllNotificaciones(); // esto triggerea el stream
    }
  }

  /// Intenta parsear el JSON de payload y lo muestra como chips.
  Map<String, dynamic>? _parsePayload(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          Navigator.pushReplacementNamed(context, '/monitoreos');
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Notificaciones'),
          actions: [
            if (_notificaciones.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.delete_sweep),
                tooltip: 'Eliminar todas',
                onPressed: _eliminarTodas,
              ),
          ],
        ),
        drawer: const AppDrawer(currentRoute: '/notificaciones'),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _notificaciones.isEmpty
                ? _buildEmptyState(isDarkMode, theme)
                : RefreshIndicator(
                    onRefresh: _cargarNotificaciones,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: _notificaciones.length,
                      itemBuilder: (context, index) {
                        final notif = _notificaciones[index];
                        return _buildNotificationCard(notif, isDarkMode, theme);
                      },
                    ),
                  ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDarkMode, ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.notifications_off_outlined,
            size: 100,
            color: isDarkMode ? Colors.white38 : Colors.grey[400],
          ),
          const SizedBox(height: 24),
          Text(
            'Sin notificaciones',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: isDarkMode ? Colors.white70 : Colors.black54,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Las notificaciones push que recibas\naparecerán aquí.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDarkMode ? Colors.white38 : Colors.grey,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(
    Map<String, dynamic> notif,
    bool isDarkMode,
    ThemeData theme,
  ) {
    final payloadMap = _parsePayload(notif['payload'] as String?);
    final fecha = notif['fecha'] as String? ?? '';
    // Formato legible: "2026-03-25T11:40:54" → "25/03/2026 11:40"
    String fechaDisplay = fecha;
    try {
      final dt = DateTime.parse(fecha);
      fechaDisplay =
          '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {}

    return Dismissible(
      key: ValueKey(notif['id']),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: Colors.redAccent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => _eliminarNotificacion(notif['id'] as int),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        elevation: isDarkMode ? 0 : 2,
        color: isDarkMode ? const Color(0xFF2A2A2A) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isDarkMode
              ? const BorderSide(color: Colors.white12)
              : BorderSide.none,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Título ──
              Row(
                children: [
                  Icon(
                    Icons.notifications_active,
                    size: 20,
                    color: theme.primaryColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      notif['titulo'] as String? ?? 'Sin título',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // ── Mensaje ──
              Text(
                notif['mensaje'] as String? ?? '',
                style: TextStyle(
                  fontSize: 13.5,
                  color: isDarkMode ? Colors.white70 : Colors.black54,
                  height: 1.4,
                ),
              ),

              // ── Payload chips ──
              if (payloadMap != null && payloadMap.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: payloadMap.entries.map((e) {
                    return Chip(
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      label: Text(
                        '${e.key}: ${e.value}',
                        style: const TextStyle(fontSize: 11),
                      ),
                      backgroundColor: isDarkMode
                          ? const Color(0xFF1E293B)
                          : theme.primaryColor.withValues(alpha: 0.1),
                    );
                  }).toList(),
                ),
              ],

              // ── Fecha ──
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  fechaDisplay,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDarkMode ? Colors.white38 : Colors.grey,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
