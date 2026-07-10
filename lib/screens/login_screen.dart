import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/session_provider.dart';
import '../providers/app_mode_provider.dart';
import '../core/services/session_persistence_service.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _hostController = TextEditingController(text: '192.168.1.1');
  final _portController = TextEditingController(text: '5000');
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _useHttps = false;
  bool _use2FA = false;
  bool _requiresOtp = false;
  bool _authTypeChecked = false;
  bool _saveCredentials = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  String? _authTypeCheckedUsername;
  final _otpController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final creds = await SessionPersistenceService.restoreCredentials();
      if (creds != null && mounted) {
        setState(() {
          _hostController.text = creds.host;
          _portController.text = creds.port.toString();
          _useHttps = creds.useHttps;
          _usernameController.text = creds.username;
          _passwordController.text = creds.password;
          _saveCredentials = true;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final host = _hostController.text.trim();
      final port = int.parse(_portController.text.trim());
      final username = _usernameController.text.trim();
      final password = _passwordController.text;

      if (!_authTypeChecked || _authTypeCheckedUsername != username) {
        await _checkAuthType(host, port, _useHttps, username);
        if (!mounted) return;
        if (_errorMessage != null) return;
      }

      if (_requiresOtp && _otpController.text.trim().isEmpty) {
        setState(() {
          _use2FA = true;
          _errorMessage = 'Two-factor authentication is required. Enter your code below.';
        });
        return;
      }

      final session = await AuthService.login(
        host: host,
        port: port,
        useHttps: _useHttps,
        username: username,
        password: password,
        otpCode: _use2FA ? _otpController.text.trim() : null,
      );

      if (!mounted) return;

      if (_saveCredentials) {
        await SessionPersistenceService.saveCredentials(SavedCredentials(
          host: host,
          port: port,
          useHttps: _useHttps,
          username: username,
          password: password,
        ));
      } else {
        await SessionPersistenceService.clearSavedCredentials();
      }

      await ref.read(sessionProvider.notifier).setSession(session);
      ref.read(appModeProvider.notifier).state = AppMode.nas;
      if (mounted) context.go('/home');
    } on ApiException catch (e) {
      // 403 = OTP required, 405 = OTP code required — auto-reveal the field
      if (e.code == 403 || e.code == 405) {
        setState(() {
          _use2FA = true;
          _errorMessage = 'Two-factor authentication is required. Enter your code below.';
        });
      } else {
        setState(() => _errorMessage = e.message);
      }
    } catch (_) {
      setState(() => _errorMessage =
          'Could not reach NAS. Check the address and port.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _resetAuthTypeState() {
    if (_authTypeChecked || _requiresOtp || _use2FA) {
      setState(() {
        _authTypeChecked = false;
        _requiresOtp = false;
        _use2FA = false;
        _authTypeCheckedUsername = null;
      });
    }
  }

  Future<void> _checkAuthType(
    String host,
    int port,
    bool useHttps,
    String username,
  ) async {
    try {
      final authTypes = await AuthService.authTypes(
        host: host,
        port: port,
        useHttps: useHttps,
        username: username,
      );

      if (!mounted) return;
      setState(() {
        _authTypeChecked = true;
        _authTypeCheckedUsername = username;
        _requiresOtp = authTypes.contains('otp');
        if (_requiresOtp) {
          _use2FA = true;
        }
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = e.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage =
          'Could not reach NAS. Check the address and port.');
    }
  }

  void _continueOffline() {
    ref.read(appModeProvider.notifier).state = AppMode.local;
    SessionPersistenceService.saveMode('local');
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLogo(context, cs),
                const SizedBox(height: 16),
                _buildCard(context, cs),
                const SizedBox(height: 10),
                _buildOfflineButton(context, cs),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo(BuildContext context, ColorScheme cs) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: cs.primary.withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(Icons.note_alt_rounded,
              color: cs.onPrimaryContainer, size: 22),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Synology Notes Enhanced',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Connect to your NAS',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCard(BuildContext context, ColorScheme cs) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Sign In',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: _hostController,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'NAS Address',
                        hintText: '192.168.1.1',
                        prefixIcon: Icon(Icons.dns_rounded, size: 18),
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                      onChanged: (_) => _resetAuthTypeState(),
                      textInputAction: TextInputAction.next,
                      keyboardType: TextInputType.url,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _portController,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Port',
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      onChanged: (_) => _resetAuthTypeState(),
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        if (n == null || n < 1 || n > 65535) return 'Invalid';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              SwitchListTile.adaptive(
                value: _useHttps,
                onChanged: (v) => setState(() {
                  _resetAuthTypeState();
                  _useHttps = v;
                  if (v && _portController.text == '5000') {
                    _portController.text = '5001';
                  } else if (!v && _portController.text == '5001') {
                    _portController.text = '5000';
                  }
                }),
                title: const Text('Use HTTPS', style: TextStyle(fontSize: 13)),
                contentPadding: EdgeInsets.zero,
                dense: true,
                visualDensity: VisualDensity.compact,
              ),
              TextFormField(
                controller: _usernameController,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Username',
                  prefixIcon: Icon(Icons.person_rounded, size: 18),
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                textInputAction: TextInputAction.next,
                onChanged: (_) => _resetAuthTypeState(),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_rounded, size: 18),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                      size: 18,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                textInputAction:
                    _use2FA ? TextInputAction.next : TextInputAction.done,
                onFieldSubmitted: (_) {
                  if (!_use2FA) _login();
                },
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Required' : null,
              ),
              SwitchListTile.adaptive(
                value: _saveCredentials,
                onChanged: (v) => setState(() => _saveCredentials = v),
                title: const Text('Save credentials',
                    style: TextStyle(fontSize: 13)),
                contentPadding: EdgeInsets.zero,
                dense: true,
                visualDensity: VisualDensity.compact,
              ),
              if (!_requiresOtp) ...[
                SwitchListTile.adaptive(
                  value: _use2FA,
                  onChanged: (v) => setState(() {
                    _use2FA = v;
                    if (!v) _otpController.clear();
                  }),
                  title: const Text('Two-Factor Authentication',
                      style: TextStyle(fontSize: 13)),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  visualDensity: VisualDensity.compact,
                ),
              ],
              if (_use2FA) ...[
                TextFormField(
                  controller: _otpController,
                  style: const TextStyle(fontSize: 13, letterSpacing: 4),
                  decoration: const InputDecoration(
                    labelText: 'Authenticator Code',
                    hintText: '000000',
                    prefixIcon: Icon(Icons.shield_rounded, size: 18),
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _login(),
                  validator: (v) =>
                      (_use2FA && (v == null || v.trim().isEmpty))
                          ? 'Required'
                          : null,
                ),
                const SizedBox(height: 4),
              ],
              if (_errorMessage != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: cs.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: cs.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          color: cs.onErrorContainer, size: 16),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                              color: cs.onErrorContainer, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                height: 40,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  child: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Connect', style: TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOfflineButton(BuildContext context, ColorScheme cs) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Divider(color: cs.outlineVariant)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(
                'or',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
            ),
            Expanded(child: Divider(color: cs.outlineVariant)),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 40,
          child: OutlinedButton.icon(
            onPressed: _continueOffline,
            icon: const Icon(Icons.phone_android_rounded, size: 16),
            label: const Text('Continue Offline',
                style: TextStyle(fontSize: 13)),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Notes will be stored locally on this device',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
