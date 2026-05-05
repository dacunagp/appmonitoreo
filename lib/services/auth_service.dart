import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:bcrypt/bcrypt.dart';
import '../database/database_helper.dart';
import '../models/models.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;
  AuthService._internal();

  final _storage = const FlutterSecureStorage();
  final DatabaseHelper _dbHelper = DatabaseHelper();

  static const String _tokenKey = 'auth_token';
  static const String _userIdKey = 'user_id';
  static const String _userNameKey = 'user_name';

  Future<Map<String, dynamic>> loginLocal(String email, String password) async {
    try {
      debugPrint('🔐 [AUTH] Intentando login local para: $email');
      final usuarios = await _dbHelper.getUsuarios();
      debugPrint('👥 [AUTH] Usuarios cargados en memoria: ${usuarios.length}');
      
      // Find user by email
      final user = usuarios.where((u) => u.email?.toLowerCase() == email.toLowerCase()).firstOrNull;

      if (user == null) {
        debugPrint('❌ [AUTH] Usuario no encontrado para el email: $email');
        return {'success': false, 'message': 'Usuario no encontrado'};
      }

      debugPrint('✅ [AUTH] Usuario encontrado: ${user.nombre} ${user.apellido}');
      debugPrint('🔑 [AUTH] Hash/Password en DB: ${user.password != null ? 'Presente' : 'NULO'}');

      bool isValid = false;
      if (user.password != null) {
        if (user.password!.startsWith('\$')) {
          debugPrint('⚙️ [AUTH] Detectado hash Bcrypt. Validando...');
          try {
            isValid = BCrypt.checkpw(password, user.password!);
          } catch (e) {
            debugPrint('🚨 [AUTH] Error en validación Bcrypt: $e');
            isValid = false;
          }
        } else {
          debugPrint('⚙️ [AUTH] Detectado texto plano. Comparando...');
          isValid = user.password == password;
        }
      }

      debugPrint('🏁 [AUTH] Resultado de validación: ${isValid ? 'EXITOSA' : 'FALLIDA'}');

      if (!isValid) {
        return {'success': false, 'message': 'Contraseña incorrecta'};
      }
      
      await _storage.write(key: _userIdKey, value: user.idUsuario.toString());
      await _storage.write(key: _userNameKey, value: '${user.nombre} ${user.apellido}');
      await _storage.write(key: _tokenKey, value: 'local_session_${user.idUsuario}');
      
      return {'success': true};
    } catch (e) {
      debugPrint('❌ [AUTH] Error inesperado: $e');
      return {'success': false, 'message': 'Error: ${e.toString().replaceFirst('Exception: ', '')}'};
    }
  }

  Future<void> logout() async {
    await _storage.deleteAll();
  }

  Future<String?> getToken() async {
    return await _storage.read(key: _tokenKey);
  }

  Future<int?> getUserId() async {
    final idStr = await _storage.read(key: _userIdKey);
    return idStr != null ? int.tryParse(idStr) : null;
  }

  Future<String?> getUserName() async {
    return await _storage.read(key: _userNameKey);
  }

  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null;
  }

  Future<bool> verifyPassword(String password) async {
    final userId = await getUserId();
    if (userId == null) return false;
    
    final usuarios = await _dbHelper.getUsuarios();
    final user = usuarios.where((u) => u.idUsuario == userId).firstOrNull;
    
    if (user == null || user.password == null) return false;
    
    if (user.password!.startsWith('\$')) {
      try {
        return BCrypt.checkpw(password, user.password!);
      } catch (e) {
        return false;
      }
    } else {
      return user.password == password;
    }
  }
}
