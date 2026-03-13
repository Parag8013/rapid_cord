import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the authenticated user's session for the current app process.
///
/// Populated by [AuthScreen] on login or by [_AppRoot] when restoring a
/// saved session from SharedPreferences.
class UserProvider extends ChangeNotifier {
  String _username = '';
  String _jwtToken = '';

  /// The numeric database ID encoded as the JWT `sub` claim.
  String _userId = '';

  String get username => _username;
  String get jwtToken => _jwtToken;
  String get userId => _userId;
  bool get isAuthenticated => _jwtToken.isNotEmpty;

  /// Set all three session fields at once (preferred after login/restore).
  void setSession({
    required String username,
    required String jwtToken,
    required String userId,
  }) {
    _username = username.trim();
    _jwtToken = jwtToken;
    _userId = userId;
    notifyListeners();
  }

  /// Convenience setter kept for legacy call-sites that only know the username.
  void setUsername(String name) {
    _username = name.trim();
    notifyListeners();
  }

  /// Clear all session data and wipe the SharedPreferences store.
  Future<void> logout() async {
    _username = '';
    _jwtToken = '';
    _userId = '';
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt_token');
    await prefs.remove('username');
    await prefs.remove('user_id');
  }
}
