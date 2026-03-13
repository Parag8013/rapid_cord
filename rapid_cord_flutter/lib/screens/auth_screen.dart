import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/user_provider.dart';
import '../theme/app_colors.dart';

/// The base URL for the RapidCord HTTP API.
/// Update this to match your server's address.
const kServerHttpBase = 'http://80.225.229.226:8080';

/// Login / Register screen shown when no valid session token is found.
///
/// On successful login calls [onAuthenticated] with the numeric user ID
/// (from the JWT `sub` claim), the human-readable username, and the raw JWT.
class AuthScreen extends StatefulWidget {
  final void Function(String userId, String username, String jwtToken)
  onAuthenticated;

  const AuthScreen({super.key, required this.onAuthenticated});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isLogin = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Username and password are required.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final endpoint = _isLogin ? '/login' : '/register';
      final response = await http
          .post(
            Uri.parse('$kServerHttpBase$endpoint'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'username': username, 'password': password}),
          )
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (!_isLogin && response.statusCode == 201) {
        // Registration succeeded – switch to login mode and invite user to sign in.
        setState(() {
          _isLogin = true;
          _error = null;
          _loading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account created! Please sign in.'),
            backgroundColor: AppColors.online,
          ),
        );
        return;
      }

      if (_isLogin && response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final token = body['token'] as String;

        // Decode the JWT payload (no signature verification needed client-side;
        // the server validates on every WebSocket upgrade).
        final userId = _extractSubFromJwt(token);

        // Persist session so we skip the auth screen on next launch.
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('jwt_token', token);
        await prefs.setString('username', username);
        await prefs.setString('user_id', userId);

        if (!mounted) return;

        // Hydrate the UserProvider before calling back.
        context.read<UserProvider>().setSession(
          username: username,
          jwtToken: token,
          userId: userId,
        );
        widget.onAuthenticated(userId, username, token);
        return;
      }

      // Map HTTP error codes to user-friendly messages.
      final msg = switch (response.statusCode) {
        409 => 'Username already taken.',
        401 => 'Invalid username or password.',
        400 => 'Bad request — check your input.',
        _ => 'Server error (${response.statusCode}).',
      };
      setState(() {
        _error = msg;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not reach server. Is it running?\n$e';
          _loading = false;
        });
      }
    }
  }

  /// Decodes the middle (payload) section of a JWT and returns the `sub` claim.
  String _extractSubFromJwt(String token) {
    try {
      final parts = token.split('.');
      if (parts.length < 2) return '';
      // Base64Url may lack padding — add it back before decoding.
      final padded = parts[1].padRight(
        parts[1].length + (4 - parts[1].length % 4) % 4,
        '=',
      );
      final decoded = base64Url.decode(padded);
      final payload = jsonDecode(utf8.decode(decoded)) as Map<String, dynamic>;
      return (payload['sub'] as String?) ?? '';
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.serverBar,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Logo ──────────────────────────────────────────────────────
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.purple, AppColors.blurple],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.purple.withValues(alpha: 0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        'RC',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 24,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                Text(
                  _isLogin ? 'Welcome back' : 'Create an account',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 6),

                Text(
                  _isLogin
                      ? 'Sign in to continue to RapidCord.'
                      : 'Register to join your team on RapidCord.',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 32),

                // ── Username ──────────────────────────────────────────────────
                _Field(
                  controller: _usernameCtrl,
                  label: 'Username',
                  icon: Icons.person_outline_rounded,
                  onSubmitted: _isLogin ? null : (_) => _submit(),
                ),

                const SizedBox(height: 14),

                // ── Password ──────────────────────────────────────────────────
                _Field(
                  controller: _passwordCtrl,
                  label: 'Password',
                  icon: Icons.lock_outline_rounded,
                  obscure: true,
                  onSubmitted: (_) => _submit(),
                ),

                // ── Error message ─────────────────────────────────────────────
                if (_error != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.redAccent.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                // ── Submit button ─────────────────────────────────────────────
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.purple,
                    disabledBackgroundColor: AppColors.purple.withValues(
                      alpha: 0.4,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _isLogin ? 'Sign In' : 'Register',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),

                const SizedBox(height: 18),

                // ── Toggle register / login ────────────────────────────────────
                TextButton(
                  onPressed: _loading
                      ? null
                      : () => setState(() {
                          _isLogin = !_isLogin;
                          _error = null;
                        }),
                  child: Text(
                    _isLogin
                        ? "Don't have an account? Register"
                        : 'Already have an account? Sign In',
                    style: const TextStyle(
                      color: AppColors.purple,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared styled text field used within [AuthScreen].
class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscure;
  final void Function(String)? onSubmitted;

  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.obscure = false,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: AppColors.textPrimary),
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: AppColors.textMuted),
        prefixIcon: Icon(icon, color: AppColors.textMuted, size: 20),
        filled: true,
        fillColor: AppColors.sidebarBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.purple, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }
}
