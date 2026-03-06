/*!
 * @file account.dart
 * @brief Account page with profile, security and connected app sections.
 * @param No external parameters.
 * @return Account management widgets in EaSync tile/block style.
 * @author Erick Radmann
 */

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pinput/pinput.dart';

import 'handler.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Account extends StatefulWidget {
  const Account({super.key});

  @override
  State<Account> createState() => _AccountState();
}

class _AccountState extends State<Account> {
  static const String _kOutsideTempCache = 'assistant.outside_temp_cache';
  static const String _kOutsideTempUpdatedAt =
      'assistant.outside_temp_updated_at';
  static const String _kAuthUid = 'account.auth.uid';
  static const String _kAuthName = 'account.auth.name';
  static const String _kAuthEmail = 'account.auth.email';
  static const String _kAuthPhoto = 'account.auth.photo';
  static const String _kAuthProvider = 'account.auth.provider';
  static const String _kFingerprintEnabled = 'account.security.fingerprint';

  final EaAppSettings _settings = EaAppSettings.instance;
  final ImagePicker _picker = ImagePicker();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  FirebaseAuth? get _authOrNull {
    if (Firebase.apps.isEmpty) return null;
    return FirebaseAuth.instance;
  }

  bool _isAuthenticated = false;
  String? _authName;
  String? _authEmail;
  String? _authPhoto;
  String? _authProvider;
  bool _fingerprintEnabled = false;
  bool _hasPassword = false;
  double _outsideTemp = 25.0;
  DateTime? _outsideUpdatedAt;

  @override
  void initState() {
    super.initState();
    _loadAccountState();
  }

  Future<void> _loadAccountState() async {
    final prefs = await SharedPreferences.getInstance();

    final cachedTemp = prefs.getDouble(_kOutsideTempCache);
    final updatedAtMs = prefs.getInt(_kOutsideTempUpdatedAt);

    if (cachedTemp != null) {
      _outsideTemp = cachedTemp;
    } else {
      _outsideTemp = _inferOutsideTemperature();
      await prefs.setDouble(_kOutsideTempCache, _outsideTemp);
      await prefs.setInt(
        _kOutsideTempUpdatedAt,
        DateTime.now().millisecondsSinceEpoch,
      );
    }

    if (updatedAtMs != null) {
      _outsideUpdatedAt = DateTime.fromMillisecondsSinceEpoch(updatedAtMs);
    }

    _authName = prefs.getString(_kAuthName);
    _authEmail = prefs.getString(_kAuthEmail);
    _authPhoto = prefs.getString(_kAuthPhoto);
    _authProvider = prefs.getString(_kAuthProvider);
    _isAuthenticated = (_authEmail?.trim().isNotEmpty ?? false);

    if (!_isAuthenticated) {
      final current = _authOrNull?.currentUser;
      if (current != null) {
        await _persistAuthFromFirebaseUser(current, provider: 'Firebase Auth');
      }
    }

    _fingerprintEnabled = prefs.getBool(_kFingerprintEnabled) ?? false;

    final savedPassword = await _secureStorage.read(key: 'account.password');
    _hasPassword = savedPassword != null && savedPassword.trim().isNotEmpty;

    if (!mounted) return;
    setState(() {});
  }

  double _inferOutsideTemperature() {
    try {
      final devices = Bridge.listDevices();
      final temps = <double>[];

      for (final d in devices) {
        if (!d.capabilities.contains(CoreCapability.CORE_CAP_TEMPERATURE)) {
          continue;
        }
        final state = Bridge.getState(d.uuid);
        if (state.temperature >= -15 && state.temperature <= 60) {
          temps.add(state.temperature);
        }
      }

      if (temps.isNotEmpty) {
        final avg = temps.reduce((a, b) => a + b) / temps.length;
        return (avg - 1.8).clamp(-10, 48);
      }
    } catch (_) {}

    return 25.0;
  }

  Future<void> _persistAuthFromFirebaseUser(
    User user, {
    String? provider,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAuthUid, user.uid);
    await prefs.setString(_kAuthName, user.displayName ?? 'EaSync User');
    await prefs.setString(_kAuthEmail, user.email ?? '');
    await prefs.setString(_kAuthPhoto, user.photoURL ?? '');
    await prefs.setString(_kAuthProvider, provider ?? 'Firebase Auth');

    _authName = user.displayName ?? 'EaSync User';
    _authEmail = user.email ?? '';
    _authPhoto = user.photoURL;
    _authProvider = provider ?? 'Firebase Auth';
    _isAuthenticated = true;
  }

  Future<void> _openSignIn() async {
    if (Firebase.apps.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Firebase is not configured yet on this build.'),
        ),
      );
      return;
    }

    final result = await Navigator.push<UserCredential?>(
      context,
      MaterialPageRoute(builder: (_) => const FirebaseSignInPage()),
    );

    final user = result?.user;
    if (user == null) return;

    await _persistAuthFromFirebaseUser(user, provider: 'Firebase Sign-in');
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openSignUp() async {
    if (Firebase.apps.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Firebase is not configured yet on this build.'),
        ),
      );
      return;
    }

    final result = await Navigator.push<UserCredential?>(
      context,
      MaterialPageRoute(builder: (_) => const FirebaseSignUpPage()),
    );

    final user = result?.user;
    if (user == null) return;

    await _persistAuthFromFirebaseUser(user, provider: 'Firebase Sign-up');
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _pickProfileImage() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
      );
      if (picked == null) return;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kAuthPhoto, picked.path);
      _authPhoto = picked.path;
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not pick image: $e')));
    }
  }

  Future<void> _signOut() async {
    try {
      await _authOrNull?.signOut();
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAuthUid);
    await prefs.remove(_kAuthName);
    await prefs.remove(_kAuthEmail);
    await prefs.remove(_kAuthPhoto);
    await prefs.remove(_kAuthProvider);

    _authName = null;
    _authEmail = null;
    _authPhoto = null;
    _authProvider = null;
    _isAuthenticated = false;
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final pad = _settings.compactMode ? 14.0 : 20.0;

    return RefreshIndicator(
      color: EaColor.fore,
      onRefresh: _loadAccountState,
      child: EaFadeSlideIn(
        begin: const Offset(0, 0.015),
        duration: _settings.animationsEnabled ? EaMotion.normal : Duration.zero,
        child: ListView(
          padding: EdgeInsets.fromLTRB(pad, 12, pad, 16),
          children: [
            _accountSummary(),
            const SizedBox(height: 10),
            _sectionTitle('Environment'),
            const SizedBox(height: 6),
            EaFadeSlideIn(
              child: _block(
                children: [
                  _AccountTile(
                    icon: Icons.thermostat_outlined,
                    title: 'Outside temperature',
                    subtitle:
                        '${_outsideTemp.toStringAsFixed(1)} °C${_outsideUpdatedAt == null ? '' : ' • ${_outsideUpdatedAt!.hour.toString().padLeft(2, '0')}:${_outsideUpdatedAt!.minute.toString().padLeft(2, '0')}'}',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const OutsideTemperaturePage(),
                        ),
                      ).then((_) => _loadAccountState());
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _sectionTitle('Profile'),
            const SizedBox(height: 6),
            EaFadeSlideIn(
              child: _block(
                children: [
                  _AccountTile(
                    icon: Icons.badge_outlined,
                    title: 'Personal info',
                    subtitle: 'Name, email and phone',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PersonalInfoPage(),
                        ),
                      ).then((_) => _loadAccountState());
                    },
                  ),
                  _AccountTile(
                    icon: Icons.apartment_outlined,
                    title: 'Address and location',
                    subtitle: 'Home and room context',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const AddressLocationPage(),
                        ),
                      ).then((_) => _loadAccountState());
                    },
                  ),
                  _AccountTile(
                    icon: Icons.language_outlined,
                    title: 'Language and region',
                    subtitle: 'Locale and formatting',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LanguageRegionPage(),
                        ),
                      ).then((_) => _loadAccountState());
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _sectionTitle('Security'),
            const SizedBox(height: 6),
            EaFadeSlideIn(
              child: _block(
                children: [
                  _AccountTile(
                    icon: Icons.lock_outline_rounded,
                    title: 'Password & passkeys',
                    subtitle: 'Credential management',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PasswordPasskeysPage(),
                        ),
                      ).then((_) => _loadAccountState());
                    },
                  ),
                  _AccountTile(
                    icon: Icons.shield_moon_outlined,
                    title: '2-step verification',
                    subtitle: 'Additional sign-in protection',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TwoStepVerificationPage(),
                        ),
                      );
                    },
                  ),
                  _AccountTile(
                    icon: Icons.devices_other_outlined,
                    title: 'Trusted devices',
                    subtitle: 'Current and recent sessions',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TrustedDevicesPage(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _sectionTitle('Subscription'),
            const SizedBox(height: 6),
            EaFadeSlideIn(
              child: _block(
                children: [
                  _AccountTile(
                    icon: Icons.workspace_premium_outlined,
                    title: 'EaSync Pro',
                    subtitle: 'Plan details and benefits',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SubscriptionPage(),
                        ),
                      );
                    },
                  ),
                  _AccountTile(
                    icon: Icons.receipt_long_outlined,
                    title: 'Billing history',
                    subtitle: 'Invoices and payment methods',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const BillingPage()),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _sectionTitle('Data controls'),
            const SizedBox(height: 6),
            EaFadeSlideIn(
              child: _block(
                children: [
                  _AccountTile(
                    icon: Icons.download_outlined,
                    title: 'Export account data',
                    subtitle: 'Portable backup package',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DataExportPage(),
                        ),
                      );
                    },
                  ),
                  _AccountTile(
                    icon: Icons.delete_forever_outlined,
                    title: 'Delete account',
                    subtitle: 'Permanent removal workflow',
                    danger: true,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DeleteAccountPage(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _accountSummary() {
    return Container(
      key: const ValueKey('account-summary'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EaAdaptiveColor.surface(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: EaAdaptiveColor.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isAuthenticated)
            Row(
              children: [
                _profileAvatar(),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _authName?.trim().isEmpty ?? true
                            ? 'Authenticated account'
                            : _authName!,
                        style: EaText.secondary.copyWith(
                          fontSize: 16,
                          color: EaAdaptiveColor.bodyText(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _authEmail ?? '',
                        style: EaText.small.copyWith(
                          color: EaAdaptiveColor.secondaryText(context),
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: _signOut,
                  icon: const Icon(Icons.logout, size: 16),
                  label: const Text('Sign out'),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You are not authenticated yet.',
                  style: EaText.secondary.copyWith(
                    color: EaAdaptiveColor.bodyText(context),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: EaColor.fore,
                          foregroundColor: EaColor.back,
                        ),
                        onPressed: _openSignIn,
                        icon: const Icon(Icons.login_rounded),
                        label: const Text('Sign-in'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: EaColor.textPrimary,
                          side: BorderSide(
                            color: EaAdaptiveColor.border(context),
                          ),
                          backgroundColor: EaColor.back,
                        ),
                        onPressed: _openSignUp,
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        label: const Text('Sign-up'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(
                Icons.verified_user_outlined,
                _isAuthenticated ? 'Authenticated' : 'Guest',
              ),
              _chip(
                Icons.security_outlined,
                _hasPassword ? 'Password set' : 'No password',
              ),
              _chip(
                Icons.fingerprint,
                _fingerprintEnabled ? 'Fingerprint on' : 'Fingerprint off',
              ),
              if (_authProvider != null)
                _chip(Icons.account_circle_outlined, _authProvider!),
            ],
          ),
        ],
      ),
    );
  }

  Widget _profileAvatar() {
    final path = (_authPhoto ?? '').trim();
    ImageProvider? provider;
    if (path.isNotEmpty) {
      if (path.startsWith('http')) {
        provider = NetworkImage(path);
      } else {
        provider = FileImage(File(path));
      }
    }

    return GestureDetector(
      onTap: _pickProfileImage,
      child: Stack(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: EaColor.fore.withValues(alpha: 0.18),
            backgroundImage: provider,
            child: provider == null
                ? const Icon(
                    Icons.person_outline_rounded,
                    color: EaColor.fore,
                    size: 20,
                  )
                : null,
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                color: EaColor.fore,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: EaAdaptiveColor.surface(context)),
              ),
              child: const Icon(Icons.edit, size: 9, color: EaColor.back),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: EaColor.fore.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: EaAdaptiveColor.border(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: EaColor.fore),
          const SizedBox(width: 6),
          Text(
            label,
            style: EaText.small.copyWith(
              color: EaAdaptiveColor.bodyText(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        title,
        style: EaText.secondary.copyWith(
          fontWeight: FontWeight.w700,
          color: EaAdaptiveColor.bodyText(context),
        ),
      ),
    );
  }

  Widget _block({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: EaAdaptiveColor.surface(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: EaAdaptiveColor.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [...children],
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool danger;
  final VoidCallback? onTap;

  const _AccountTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.danger = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        splashColor: Colors.transparent,
      ),
      child: ListTile(
        enableFeedback: false,
        leading: Icon(icon, color: danger ? Colors.redAccent : EaColor.fore),
        title: Text(
          title,
          style: EaText.secondary.copyWith(
            color: danger
                ? Colors.redAccent
                : EaAdaptiveColor.bodyText(context),
          ),
        ),
        subtitle: Text(
          subtitle,
          style: EaText.small.copyWith(
            color: EaAdaptiveColor.secondaryText(context),
          ),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: EaColor.textSecondary,
        ),
        onTap: onTap,
      ),
    );
  }
}

class FirebaseSignInPage extends StatefulWidget {
  const FirebaseSignInPage({super.key});

  @override
  State<FirebaseSignInPage> createState() => _FirebaseSignInPageState();
}

class _FirebaseSignInPageState extends State<FirebaseSignInPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (Firebase.apps.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Firebase is not configured for this platform yet.'),
        ),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final result = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
      if (!mounted) return;
      Navigator.pop(context, result);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message ?? 'Sign-in failed.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Sign-in failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign-in')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _authField(_email, 'Email', false),
          const SizedBox(height: 10),
          _authField(_password, 'Password', true),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _loading ? null : _submit,
            icon: _loading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login_rounded),
            label: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Widget _authField(TextEditingController c, String label, bool obscured) {
    return TextField(
      controller: c,
      obscureText: obscured,
      keyboardType: obscured ? TextInputType.text : TextInputType.emailAddress,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: EaAdaptiveColor.field(context),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class FirebaseSignUpPage extends StatefulWidget {
  const FirebaseSignUpPage({super.key});

  @override
  State<FirebaseSignUpPage> createState() => _FirebaseSignUpPageState();
}

class _FirebaseSignUpPageState extends State<FirebaseSignUpPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();
  final _pin = TextEditingController();

  bool _awaitingPin = false;
  bool _loading = false;
  String _expectedPin = '';

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _pin.dispose();
    super.dispose();
  }

  void _requestVerificationPin() {
    final generated = (100000 + Random().nextInt(899999)).toString();
    setState(() {
      _expectedPin = generated;
      _awaitingPin = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Demo verification code: $generated')),
    );
  }

  Future<void> _submitSignUp() async {
    if (Firebase.apps.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Firebase is not configured for this platform yet.'),
        ),
      );
      return;
    }

    if (_pin.text.trim() != _expectedPin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid verification PIN.')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final result = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
      await result.user?.updateDisplayName(_name.text.trim());
      if (!mounted) return;
      Navigator.pop(context, result);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message ?? 'Sign-up failed.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Sign-up failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign-up')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _authField(_name, 'Display name', false),
          const SizedBox(height: 10),
          _authField(_email, 'Email', false),
          const SizedBox(height: 10),
          _authField(_password, 'Password', true),
          const SizedBox(height: 12),
          if (!_awaitingPin)
            FilledButton.icon(
              onPressed: _requestVerificationPin,
              icon: const Icon(Icons.pin_outlined),
              label: const Text('Send verification PIN'),
            )
          else ...[
            Text(
              'Enter the 6-digit PIN to complete sign-up',
              style: EaText.small.copyWith(
                color: EaAdaptiveColor.secondaryText(context),
              ),
            ),
            const SizedBox(height: 10),
            Pinput(
              controller: _pin,
              length: 6,
              defaultPinTheme: PinTheme(
                width: 48,
                height: 50,
                textStyle: EaText.secondary.copyWith(
                  color: EaAdaptiveColor.bodyText(context),
                ),
                decoration: BoxDecoration(
                  color: EaAdaptiveColor.field(context),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: EaAdaptiveColor.border(context)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _loading ? null : _submitSignUp,
              icon: _loading
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: const Text('Create account'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _authField(TextEditingController c, String label, bool obscured) {
    return TextField(
      controller: c,
      obscureText: obscured,
      keyboardType: obscured ? TextInputType.text : TextInputType.emailAddress,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: EaAdaptiveColor.field(context),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class PersonalInfoPage extends StatefulWidget {
  const PersonalInfoPage({super.key});

  @override
  State<PersonalInfoPage> createState() => _PersonalInfoPageState();
}

class _PersonalInfoPageState extends State<PersonalInfoPage> {
  static const _kFullName = 'profile.full_name';
  static const _kLocation = 'profile.location';
  static const _kLanguage = 'profile.language';
  static const _kRegion = 'profile.region';

  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _languageController = TextEditingController();
  final _regionController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _languageController.dispose();
    _regionController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _nameController.text = prefs.getString(_kFullName) ?? '';
    _locationController.text = prefs.getString(_kLocation) ?? '';
    _languageController.text = prefs.getString(_kLanguage) ?? '';
    _regionController.text = prefs.getString(_kRegion) ?? '';
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kFullName, _nameController.text.trim());
    await prefs.setString(_kLocation, _locationController.text.trim());
    await prefs.setString(_kLanguage, _languageController.text.trim());
    await prefs.setString(_kRegion, _regionController.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Dados salvos localmente.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Personal info')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          EaFadeSlideIn(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: EaAdaptiveColor.surface(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: EaAdaptiveColor.border(context)),
              ),
              child: Column(
                children: [
                  _field(_nameController, 'Full name'),
                  _field(_locationController, 'Location'),
                  _field(_languageController, 'Language'),
                  _field(_regionController, 'Region'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save changes'),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController controller, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        style: EaText.secondary.copyWith(
          color: EaAdaptiveColor.bodyText(context),
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: EaText.small.copyWith(
            color: EaAdaptiveColor.secondaryText(context),
          ),
          filled: true,
          fillColor: EaAdaptiveColor.field(context),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: EaAdaptiveColor.border(context)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: EaAdaptiveColor.border(context)),
          ),
        ),
      ),
    );
  }
}

class OutsideTemperaturePage extends StatefulWidget {
  const OutsideTemperaturePage({super.key});

  @override
  State<OutsideTemperaturePage> createState() => _OutsideTemperaturePageState();
}

class _OutsideTemperaturePageState extends State<OutsideTemperaturePage> {
  static const String _kOutsideTempCache = 'assistant.outside_temp_cache';
  static const String _kOutsideTempUpdatedAt =
      'assistant.outside_temp_updated_at';

  double _outsideTemp = 25;
  DateTime? _updatedAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _outsideTemp = prefs.getDouble(_kOutsideTempCache) ?? 25;
    final ms = prefs.getInt(_kOutsideTempUpdatedAt);
    if (ms != null) _updatedAt = DateTime.fromMillisecondsSinceEpoch(ms);
    if (mounted) setState(() {});
  }

  Future<void> _refreshFromDevices() async {
    final prefs = await SharedPreferences.getInstance();

    try {
      final devices = Bridge.listDevices();
      final temps = <double>[];
      for (final d in devices) {
        if (d.capabilities.contains(CoreCapability.CORE_CAP_TEMPERATURE)) {
          final s = Bridge.getState(d.uuid);
          if (s.temperature >= -15 && s.temperature <= 60) {
            temps.add(s.temperature);
          }
        }
      }
      if (temps.isNotEmpty) {
        _outsideTemp = (temps.reduce((a, b) => a + b) / temps.length - 1.8)
            .clamp(-10, 48);
      }
    } catch (_) {}

    _updatedAt = DateTime.now();
    await prefs.setDouble(_kOutsideTempCache, _outsideTemp);
    await prefs.setInt(
      _kOutsideTempUpdatedAt,
      _updatedAt!.millisecondsSinceEpoch,
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Outside temperature')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          EaFadeSlideIn(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: EaAdaptiveColor.surface(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: EaAdaptiveColor.border(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_outsideTemp.toStringAsFixed(1)} °C',
                    style: EaText.primary.copyWith(
                      fontSize: 30,
                      color: EaAdaptiveColor.bodyText(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _updatedAt == null
                        ? 'Sem atualização registrada.'
                        : 'Atualizado às ${_updatedAt!.hour.toString().padLeft(2, '0')}:${_updatedAt!.minute.toString().padLeft(2, '0')}',
                    style: EaText.small.copyWith(
                      color: EaAdaptiveColor.secondaryText(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _refreshFromDevices,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Refresh from devices'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AddressLocationPage extends StatefulWidget {
  const AddressLocationPage({super.key});

  @override
  State<AddressLocationPage> createState() => _AddressLocationPageState();
}

class _AddressLocationPageState extends State<AddressLocationPage> {
  static const _kStreet = 'profile.address.street';
  static const _kCity = 'profile.address.city';
  static const _kPostal = 'profile.address.postal';
  static const _kCountry = 'profile.address.country';

  final _street = TextEditingController();
  final _city = TextEditingController();
  final _postal = TextEditingController();
  final _country = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _street.dispose();
    _city.dispose();
    _postal.dispose();
    _country.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _street.text = prefs.getString(_kStreet) ?? '';
    _city.text = prefs.getString(_kCity) ?? '';
    _postal.text = prefs.getString(_kPostal) ?? '';
    _country.text = prefs.getString(_kCountry) ?? '';
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kStreet, _street.text.trim());
    await prefs.setString(_kCity, _city.text.trim());
    await prefs.setString(_kPostal, _postal.text.trim());
    await prefs.setString(_kCountry, _country.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Endereço salvo localmente.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Address and location')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          EaFadeSlideIn(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: EaAdaptiveColor.surface(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: EaAdaptiveColor.border(context)),
              ),
              child: Column(
                children: [
                  _textField(_street, 'Street'),
                  _textField(_city, 'City'),
                  _textField(_postal, 'Postal code'),
                  _textField(_country, 'Country'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save address'),
          ),
        ],
      ),
    );
  }

  Widget _textField(TextEditingController c, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: c,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: EaAdaptiveColor.field(context),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}

class LanguageRegionPage extends StatefulWidget {
  const LanguageRegionPage({super.key});

  @override
  State<LanguageRegionPage> createState() => _LanguageRegionPageState();
}

class _LanguageRegionPageState extends State<LanguageRegionPage> {
  static const _kLanguage = 'profile.language';
  static const _kRegion = 'profile.region';
  static const _kTimeFormat24h = 'profile.time_24h';

  String _language = 'Português';
  String _region = 'Brasil';
  bool _time24h = true;

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _language = prefs.getString(_kLanguage) ?? _language;
    _region = prefs.getString(_kRegion) ?? _region;
    _time24h = prefs.getBool(_kTimeFormat24h) ?? true;
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLanguage, _language);
    await prefs.setString(_kRegion, _region);
    await prefs.setBool(_kTimeFormat24h, _time24h);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Idioma e região atualizados.')),
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Language and region')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          EaFadeSlideIn(
            child: Container(
              decoration: BoxDecoration(
                color: EaAdaptiveColor.surface(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: EaAdaptiveColor.border(context)),
              ),
              child: Column(
                children: [
                  ListTile(
                    title: const Text('Language'),
                    trailing: DropdownButton<String>(
                      value: _language,
                      items: const [
                        DropdownMenuItem(
                          value: 'Português',
                          child: Text('Português'),
                        ),
                        DropdownMenuItem(
                          value: 'English',
                          child: Text('English'),
                        ),
                        DropdownMenuItem(
                          value: 'Español',
                          child: Text('Español'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _language = v);
                      },
                    ),
                  ),
                  ListTile(
                    title: const Text('Region'),
                    trailing: DropdownButton<String>(
                      value: _region,
                      items: const [
                        DropdownMenuItem(
                          value: 'Brasil',
                          child: Text('Brasil'),
                        ),
                        DropdownMenuItem(
                          value: 'Portugal',
                          child: Text('Portugal'),
                        ),
                        DropdownMenuItem(
                          value: 'United States',
                          child: Text('United States'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _region = v);
                      },
                    ),
                  ),
                  SwitchListTile.adaptive(
                    value: _time24h,
                    title: const Text('24-hour format'),
                    onChanged: (v) => setState(() => _time24h = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_rounded),
            label: const Text('Save preferences'),
          ),
        ],
      ),
    );
  }
}

class PasswordPasskeysPage extends StatefulWidget {
  const PasswordPasskeysPage({super.key});

  @override
  State<PasswordPasskeysPage> createState() => _PasswordPasskeysPageState();
}

class _PasswordPasskeysPageState extends State<PasswordPasskeysPage> {
  static const _kFingerprintEnabled = 'account.security.fingerprint';
  final _secure = const FlutterSecureStorage();
  bool _fingerprintEnabled = false;
  bool _hasPassword = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _fingerprintEnabled = prefs.getBool(_kFingerprintEnabled) ?? false;
    final pwd = await _secure.read(key: 'account.password');
    _hasPassword = (pwd ?? '').isNotEmpty;
    if (mounted) setState(() {});
  }

  Future<void> _setFingerprint(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kFingerprintEnabled, enabled);
    setState(() => _fingerprintEnabled = enabled);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Password & passkeys')),
      body: ListView(
        children: [
          SwitchListTile.adaptive(
            value: _fingerprintEnabled,
            title: const Text('Enable fingerprint unlock'),
            subtitle: const Text(
              'Device-level biometric gate (no local_auth).',
            ),
            onChanged: _setFingerprint,
          ),
          ListTile(
            leading: const Icon(Icons.password_rounded),
            title: Text(
              _hasPassword ? 'Change login password' : 'Create login password',
            ),
            subtitle: const Text('Configure your local login password'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PasswordSetupPage()),
              ).then((_) => _load());
            },
          ),
        ],
      ),
    );
  }
}

class PasswordSetupPage extends StatefulWidget {
  const PasswordSetupPage({super.key});

  @override
  State<PasswordSetupPage> createState() => _PasswordSetupPageState();
}

class _PasswordSetupPageState extends State<PasswordSetupPage> {
  final _pwd = TextEditingController();
  final _confirm = TextEditingController();
  final _secure = const FlutterSecureStorage();

  @override
  void dispose() {
    _pwd.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _savePassword() async {
    final a = _pwd.text.trim();
    final b = _confirm.text.trim();
    if (a.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A senha precisa ter ao menos 4 caracteres.'),
        ),
      );
      return;
    }
    if (a != b) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('As senhas não coincidem.')));
      return;
    }

    await _secure.write(key: 'account.password', value: a);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Senha salva com sucesso.')));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login password')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _pwd,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'New password'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _confirm,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Confirm password'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _savePassword,
            child: const Text('Save password'),
          ),
        ],
      ),
    );
  }
}

class TwoStepVerificationPage extends StatefulWidget {
  const TwoStepVerificationPage({super.key});

  @override
  State<TwoStepVerificationPage> createState() =>
      _TwoStepVerificationPageState();
}

class _TwoStepVerificationPageState extends State<TwoStepVerificationPage> {
  static const _k2faApp = 'account.security.2fa.app';
  static const _k2faSms = 'account.security.2fa.sms';
  static const _k2faEmail = 'account.security.2fa.email';

  bool _app = true;
  bool _sms = false;
  bool _email = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _app = prefs.getBool(_k2faApp) ?? true;
    _sms = prefs.getBool(_k2faSms) ?? false;
    _email = prefs.getBool(_k2faEmail) ?? true;
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_k2faApp, _app);
    await prefs.setBool(_k2faSms, _sms);
    await prefs.setBool(_k2faEmail, _email);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('2FA atualizada com sucesso.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('2-step verification')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          EaFadeSlideIn(
            child: Container(
              decoration: BoxDecoration(
                color: EaAdaptiveColor.surface(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: EaAdaptiveColor.border(context)),
              ),
              child: Column(
                children: [
                  SwitchListTile.adaptive(
                    value: _app,
                    title: const Text('Authenticator app'),
                    onChanged: (v) => setState(() => _app = v),
                  ),
                  SwitchListTile.adaptive(
                    value: _sms,
                    title: const Text('SMS verification'),
                    onChanged: (v) => setState(() => _sms = v),
                  ),
                  SwitchListTile.adaptive(
                    value: _email,
                    title: const Text('Email verification'),
                    onChanged: (v) => setState(() => _email = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.shield_outlined),
            label: const Text('Save 2FA settings'),
          ),
        ],
      ),
    );
  }
}

class TrustedDevicesPage extends StatefulWidget {
  const TrustedDevicesPage({super.key});

  @override
  State<TrustedDevicesPage> createState() => _TrustedDevicesPageState();
}

class _TrustedDevicesPageState extends State<TrustedDevicesPage> {
  static const _kTrustedDevices = 'account.security.trusted_devices';
  List<String> _devices = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _devices =
        prefs.getStringList(_kTrustedDevices) ??
        ['${Platform.operatingSystem.toUpperCase()} • Este dispositivo'];
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kTrustedDevices, _devices);
  }

  Future<void> _removeAt(int index) async {
    _devices.removeAt(index);
    await _save();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trusted devices')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ...List.generate(_devices.length, (i) {
            return EaFadeSlideIn(
              child: Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.devices_outlined,
                    color: EaColor.fore,
                  ),
                  title: Text(_devices[i]),
                  subtitle: Text(
                    'Session ativa',
                    style: EaText.small.copyWith(
                      color: EaAdaptiveColor.secondaryText(context),
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => _removeAt(i),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class SubscriptionPage extends StatefulWidget {
  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  static const _kPlan = 'account.subscription.plan';
  String _plan = 'Free';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _plan = prefs.getString(_kPlan) ?? 'Free';
    if (mounted) setState(() {});
  }

  Future<void> _setPlan(String plan) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPlan, plan);
    setState(() => _plan = plan);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('EaSync Pro')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          EaFadeSlideIn(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    EaColor.fore.withValues(alpha: 0.22),
                    EaColor.secondaryFore.withValues(alpha: 0.12),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: EaAdaptiveColor.border(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current plan: $_plan',
                    style: EaText.primary.copyWith(
                      color: EaAdaptiveColor.bodyText(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Automations, analytics and advanced assistant controls.',
                    style: EaText.small.copyWith(
                      color: EaAdaptiveColor.secondaryText(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _planTile('Free', 'Basic device and assistant controls'),
          _planTile('Pro', 'Advanced automations and full AI modes'),
        ],
      ),
    );
  }

  Widget _planTile(String plan, String desc) {
    return Card(
      child: ListTile(
        title: Text(plan),
        subtitle: Text(desc),
        trailing: _plan == plan
            ? const Icon(Icons.check_circle, color: EaColor.fore)
            : null,
        onTap: () => _setPlan(plan),
      ),
    );
  }
}

class BillingPage extends StatefulWidget {
  const BillingPage({super.key});

  @override
  State<BillingPage> createState() => _BillingPageState();
}

class _BillingPageState extends State<BillingPage> {
  static const _kBillingItems = 'account.billing.items';
  List<String> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _items = prefs.getStringList(_kBillingItems) ?? [];
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Billing history')),
      body: _items.isEmpty
          ? Center(
              child: Text(
                'Nenhuma cobrança registrada ainda.',
                style: EaText.secondary.copyWith(
                  color: EaAdaptiveColor.secondaryText(context),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _items.length,
              itemBuilder: (_, i) => Card(
                child: ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: Text(_items[i]),
                ),
              ),
            ),
    );
  }
}

class DataExportPage extends StatefulWidget {
  const DataExportPage({super.key});

  @override
  State<DataExportPage> createState() => _DataExportPageState();
}

class _DataExportPageState extends State<DataExportPage> {
  bool _includeProfile = true;
  bool _includeUsage = true;
  bool _includeSecurity = true;

  Future<void> _export() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = <String, dynamic>{
      'exportedAt': DateTime.now().toIso8601String(),
      if (_includeProfile)
        'profile': {
          'fullName': prefs.getString('profile.full_name') ?? '',
          'location': prefs.getString('profile.location') ?? '',
          'language': prefs.getString('profile.language') ?? '',
          'region': prefs.getString('profile.region') ?? '',
        },
      if (_includeUsage)
        'usage': {'pattern': prefs.getString('usage.pattern') ?? 'balanced'},
      if (_includeSecurity)
        'security': {
          'fingerprint': prefs.getBool('account.security.fingerprint') ?? false,
        },
    };

    final jsonText = const JsonEncoder.withIndent('  ').convert(payload);
    await Clipboard.setData(ClipboardData(text: jsonText));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Export copiado para a área de transferência.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Export account data')),
      body: ListView(
        children: [
          CheckboxListTile(
            value: _includeProfile,
            onChanged: (v) => setState(() => _includeProfile = v ?? false),
            title: const Text('Profile data'),
          ),
          CheckboxListTile(
            value: _includeUsage,
            onChanged: (v) => setState(() => _includeUsage = v ?? false),
            title: const Text('Usage data'),
          ),
          CheckboxListTile(
            value: _includeSecurity,
            onChanged: (v) => setState(() => _includeSecurity = v ?? false),
            title: const Text('Security settings'),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: _export,
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('Generate export'),
            ),
          ),
        ],
      ),
    );
  }
}

class DeleteAccountPage extends StatefulWidget {
  const DeleteAccountPage({super.key});

  @override
  State<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends State<DeleteAccountPage> {
  final _confirmController = TextEditingController();
  bool _understand = false;

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (!_understand ||
        _confirmController.text.trim().toUpperCase() != 'DELETE') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Confirme digitando DELETE e marque a opção.'),
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Dados locais da conta removidos.')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Delete account')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.redAccent.withValues(alpha: 0.3),
              ),
            ),
            child: const Text(
              'Esta ação remove seus dados locais e não pode ser desfeita.',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmController,
            decoration: const InputDecoration(
              labelText: 'Type DELETE to confirm',
            ),
          ),
          CheckboxListTile(
            value: _understand,
            onChanged: (v) => setState(() => _understand = v ?? false),
            title: const Text('I understand this operation is irreversible'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: _delete,
            icon: const Icon(Icons.delete_forever_rounded),
            label: const Text('Delete local account data'),
          ),
        ],
      ),
    );
  }
}
