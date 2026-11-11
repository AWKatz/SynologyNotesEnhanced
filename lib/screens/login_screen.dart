import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/session_provider.dart';
import '../providers/app_mode_provider.dart';
import '../core/api/nas_address.dart';
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
  final _altController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _useHttps = false;
  // The remote/fallback address field stays hidden unless switched on.
  bool _useRemoteAddress = false;
  bool _use2FA = false;
  bool _requiresOtp = false;
  bool _authTypeChecked = false;
  bool _saveCredentials = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  String? _authTypeCheckedUsername;
  String? _deviceId;
  final _otpController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Shown when a background re-login couldn't keep the session alive.
    _errorMessage = ref.read(sessionProvider.notifier).takeExpiryMessage();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final creds = await SessionPersistenceService.restoreCredentials();
      _deviceId = await SessionPersistenceService.restoreDeviceId();
      if (creds != null && mounted) {
        setState(() {
          _hostController.text = creds.host;
          _portController.text = creds.port.toString();
          _useHttps = creds.useHttps;
          _usernameController.text = creds.username;
          _passwordController.text = creds.password;
          _altController.text = creds.alternateBaseUrl ?? '';
          _useRemoteAddress = _altController.text.trim().isNotEmpty;
          _saveCredentials = true;
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _altController.dispose();
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
      final primary = _parsePrimaryAddress();
      if (primary == null) {
        setState(() => _errorMessage = 'Enter a valid NAS address.');
        return;
      }
      // Reflect what was pulled out of a pasted URL (scheme/port) in the
      // form, so what's shown is what's used and what gets saved.
      if (primary.host != _hostController.text.trim() ||
          primary.port.toString() != _portController.text.trim() ||
          primary.useHttps != _useHttps) {
        setState(() {
          _hostController.text = primary.host;
          _portController.text = primary.port.toString();
          _useHttps = primary.useHttps;
        });
      }
      final host = primary.host;
      final port = primary.port;
      final altBaseUrl = _parseAlternateBaseUrl(primary);
      final username = _usernameController.text.trim();
      final password = _passwordController.text;

      if (!_authTypeChecked || _authTypeCheckedUsername != username) {
        await _checkAuthType(host, port, _useHttps, username, altBaseUrl);
        if (!mounted) return;
        if (_errorMessage != null) return;
      }

      // With a trusted-device token DSM may accept the login without an OTP
      // code, so only insist on one up front when there's no token.
      if (_requiresOtp &&
          _otpController.text.trim().isEmpty &&
          _deviceId == null) {
        setState(() {
          _use2FA = true;
          _errorMessage = 'Two-factor authentication is required. Enter your code below.';
        });
        return;
      }

      final otp = _use2FA ? _otpController.text.trim() : '';
      final session = await AuthService.login(
        host: host,
        port: port,
        useHttps: _useHttps,
        username: username,
        password: password,
        otpCode: otp.isEmpty ? null : otp,
        alternateBaseUrl: altBaseUrl,
        deviceId: _deviceId,
        // Ask DSM to trust this device so background re-logins (after the
        // session expires or the phone changes networks) don't need a code.
        rememberDevice: otp.isNotEmpty,
      );

      if (!mounted) return;

      if (_saveCredentials) {
        await SessionPersistenceService.saveCredentials(SavedCredentials(
          host: host,
          port: port,
          useHttps: _useHttps,
          username: username,
          password: password,
          alternateBaseUrl: altBaseUrl,
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
        setState(() => _errorMessage = _describeError(e));
      }
    } catch (e) {
      debugPrint('Login failed with non-ApiException: $e');
      setState(() => _errorMessage =
          'Could not reach NAS. Check the address and port.\n($e)');
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

  NasAddress? _parsePrimaryAddress() => NasAddress.parse(
        _hostController.text,
        defaultHttps: _useHttps,
        defaultPort: int.tryParse(_portController.text.trim()) ?? 5000,
      );

  /// The optional remote/alternate address as a base URL, inheriting the
  /// primary's scheme and port unless it spells out its own.
  String? _parseAlternateBaseUrl(NasAddress primary) {
    if (!_useRemoteAddress || _altController.text.trim().isEmpty) return null;
    return NasAddress.parse(
      _altController.text,
      defaultHttps: primary.useHttps,
      defaultPort: primary.port,
    )?.baseUrl;
  }

  Future<void> _checkAuthType(
    String host,
    int port,
    bool useHttps,
    String username,
    String? alternateBaseUrl,
  ) async {
    try {
      final authTypes = await AuthService.authTypes(
        host: host,
        port: port,
        useHttps: useHttps,
        username: username,
        alternateBaseUrl: alternateBaseUrl,
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
      setState(() => _errorMessage = _describeError(e));
    } catch (e) {
      debugPrint('Auth type check failed with non-ApiException: $e');
      if (!mounted) return;
      setState(() => _errorMessage =
          'Could not reach NAS. Check the address and port.\n($e)');
    }
  }

  String _describeError(ApiException e) {
    if (e.code != -1) return e.message;
    return 'Could not reach the NAS. Away from home, use your DDNS name '
        '(or set it as the Remote Address) with HTTPS on port 5001.\n'
        '(${e.message})';
  }

  void _continueOffline() {
    ref.read(appModeProvider.notifier).state = AppMode.local;
    SessionPersistenceService.saveMode('local');
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mq = MediaQuery.of(context);
    // Large Dynamic Type sizes would otherwise push this dense form into
    // overlapping labels; still scales text up, just not without limit.
    return MediaQuery(
      data: mq.copyWith(
          textScaler: mq.textScaler.clamp(maxScaleFactor: 1.3)),
      child: Scaffold(
        backgroundColor: cs.surface,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 600;
              final hPad = compact ? 20.0 : 28.0;
              // SliverFillRemaining lets the column use the full screen
              // height (offline button pinned to the bottom) while still
              // scrolling when the keyboard takes space away.
              return CustomScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Spacer(),
                              _buildLogo(context, cs),
                              const SizedBox(height: 20),
                              _buildForm(context, cs),
                              const Spacer(flex: 2),
                              const SizedBox(height: 16),
                              _buildOfflineButton(context, cs),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
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
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            boxShadow: [
              BoxShadow(
                color: cs.primary.withValues(alpha: 0.25),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(11),
            child: Image.asset(
              'assets/icons/app_icon.png',
              width: 44,
              height: 44,
              fit: BoxFit.cover,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Synology Notes Enhanced',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Connect to your NAS',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static const _fieldTextStyle = TextStyle(fontSize: 15);

  InputDecoration _decoration(String label,
      {IconData? icon, String? hint, Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon == null ? null : Icon(icon, size: 20),
      suffixIcon: suffix,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
    );
  }

  Widget _buildForm(BuildContext context, ColorScheme cs) {
    const gap = SizedBox(height: 10);
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  controller: _hostController,
                  style: _fieldTextStyle,
                  decoration: _decoration('NAS Address',
                      icon: Icons.dns_rounded, hint: '192.168.1.1'),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    return _parsePrimaryAddress() == null
                        ? 'Invalid address'
                        : null;
                  },
                  onChanged: (_) => _resetAuthTypeState(),
                  textInputAction: TextInputAction.next,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  enableSuggestions: false,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 84,
                child: TextFormField(
                  controller: _portController,
                  style: _fieldTextStyle,
                  decoration: _decoration('Port'),
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
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _CompactToggle(
                  label: 'HTTPS',
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
                ),
              ),
              Expanded(
                child: _CompactToggle(
                  label: 'Remote address',
                  value: _useRemoteAddress,
                  onChanged: (v) => setState(() => _useRemoteAddress = v),
                ),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: !_useRemoteAddress
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 10),
                    child: TextFormField(
                      controller: _altController,
                      style: _fieldTextStyle,
                      decoration: _decoration('Remote Address',
                          icon: Icons.public_rounded,
                          hint: 'mynas.synology.me'),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return null;
                        final primary = _parsePrimaryAddress();
                        if (primary == null) return null; // flagged above
                        return _parseAlternateBaseUrl(primary) == null
                            ? 'Invalid address'
                            : null;
                      },
                      textInputAction: TextInputAction.next,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      enableSuggestions: false,
                    ),
                  ),
          ),
          if (!_useRemoteAddress) const SizedBox(height: 6),
          TextFormField(
            controller: _usernameController,
            style: _fieldTextStyle,
            decoration: _decoration('Username', icon: Icons.person_rounded),
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.none,
            textInputAction: TextInputAction.next,
            onChanged: (_) => _resetAuthTypeState(),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          gap,
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            style: _fieldTextStyle,
            decoration: _decoration(
              'Password',
              icon: Icons.lock_rounded,
              suffix: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_rounded,
                  size: 20,
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
            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: _CompactToggle(
                  label: 'Save login',
                  value: _saveCredentials,
                  onChanged: (v) => setState(() => _saveCredentials = v),
                ),
              ),
              Expanded(
                // When the account is known to require 2FA the code field is
                // always shown, so the switch would be meaningless.
                child: _requiresOtp
                    ? const SizedBox.shrink()
                    : _CompactToggle(
                        label: 'Two-factor',
                        value: _use2FA,
                        onChanged: (v) => setState(() {
                          _use2FA = v;
                          if (!v) _otpController.clear();
                        }),
                      ),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: !_use2FA
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: TextFormField(
                      controller: _otpController,
                      style: _fieldTextStyle.copyWith(letterSpacing: 4),
                      decoration: _decoration('Authenticator Code',
                          icon: Icons.shield_rounded, hint: '000000'),
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _login(),
                      validator: (v) =>
                          (_use2FA && (v == null || v.trim().isEmpty))
                              ? 'Required'
                              : null,
                    ),
                  ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: cs.errorContainer,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cs.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(Icons.error_outline,
                        color: cs.onErrorContainer, size: 16),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style:
                          TextStyle(color: cs.onErrorContainer, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _login,
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Connect', style: TextStyle(fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineButton(BuildContext context, ColorScheme cs) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 44,
          child: OutlinedButton.icon(
            onPressed: _continueOffline,
            icon: const Icon(Icons.phone_android_rounded, size: 18),
            label: const Text('Continue Offline',
                style: TextStyle(fontSize: 14)),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Notes will be stored locally on this device',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// A switch with a short label, sized to sit two-per-row. Replaces
/// full-width SwitchListTiles, which took a whole row each and left the form
/// too tall for a phone screen.
class _CompactToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _CompactToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      toggled: value,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                height: 28,
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: Switch.adaptive(value: value, onChanged: onChanged),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: cs.onSurface),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
