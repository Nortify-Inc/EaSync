// ignore_for_file: use_null_aware_elements

/*!
 * @file account.dart
 * @brief Account page with profile, security and connected app sections.
 * @param No external parameters.
 * @return Account management widgets in EaSync tile/block style.
 * @author Erick Radmann
 */

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
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

class _AccountState extends State<Account> with SingleTickerProviderStateMixin {
  static const String _kOutsideTempCache = 'assistant.outside_temp_cache';
  static const String _kOutsideTempUpdatedAt =
      'assistant.outside_temp_updated_at';
  static const String _kAuthUid = 'account.auth.uid';
  static const String _kAuthName = 'account.auth.name';
  static const String _kAuthEmail = 'account.auth.email';
  static const String _kAuthPhoto = 'account.auth.photo';
  static const String _kAuthProvider = 'account.auth.provider';
  static const String _kFingerprintEnabled = 'account.security.fingerprint';
  static const String _kLanguage = 'profile.language';
  static const String _kRegion = 'profile.region';
  static const String _kAddressStreet = 'profile.address.street';
  static const String _kAddressCity = 'profile.address.city';
  static const String _kAddressPostal = 'profile.address.postal';
  static const String _kAddressCountry = 'profile.address.country';
  static const String _kAddressFull = 'profile.address.full';
  static const String _kProfileLocation = 'profile.location';

  final EaAppSettings _settings = EaAppSettings.instance;
  final ImagePicker _picker = ImagePicker();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  late final AnimationController _updatePulse;

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
  bool _outsideTempRefreshing = false;
  String _language = 'Português';
  String _region = 'Brasil';
  String _fullLocation = 'Localização desconhecida';
  bool _locationRefreshing = false;

  @override
  void initState() {
    super.initState();
    _updatePulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _loadAccountState();
  }

  @override
  void dispose() {
    _updatePulse.dispose();
    super.dispose();
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
    _language = prefs.getString(_kLanguage) ?? _language;
    _region = prefs.getString(_kRegion) ?? _region;
    final fallbackProfileLocation = (prefs.getString(_kProfileLocation) ?? '')
        .trim();

    final parts = <String>[
      (prefs.getString(_kAddressStreet) ?? '').trim(),
      (prefs.getString(_kAddressCity) ?? '').trim(),
      (prefs.getString(_kAddressPostal) ?? '').trim(),
      (prefs.getString(_kAddressCountry) ?? '').trim(),
    ].where((e) => e.isNotEmpty).toList();
    final savedAddressFull = (prefs.getString(_kAddressFull) ?? '').trim();
    _fullLocation = savedAddressFull.isNotEmpty
        ? savedAddressFull
        : (parts.isNotEmpty
              ? parts.join(', ')
              : (fallbackProfileLocation.isNotEmpty
                    ? fallbackProfileLocation
                    : 'Localização desconhecida'));

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

  String _buildWeatherQueryFromPrefs(SharedPreferences prefs) {
    final addressFull = (prefs.getString(_kAddressFull) ?? '').trim();
    if (addressFull.isNotEmpty && addressFull != 'Localização desconhecida') {
      return addressFull;
    }

    final profileLocation = (prefs.getString(_kProfileLocation) ?? '').trim();
    if (profileLocation.isNotEmpty) return profileLocation;

    final city = (prefs.getString(_kAddressCity) ?? '').trim();
    final country = (prefs.getString(_kAddressCountry) ?? '').trim();
    if (city.isNotEmpty && country.isNotEmpty) return '$city, $country';
    if (city.isNotEmpty) return city;

    final current = _fullLocation.trim();
    if (current.isNotEmpty && current != 'Localização desconhecida') {
      return current;
    }
    return '';
  }

  Future<double?> _fetchOutsideTempFromQuery(String query) async {
    if (query.trim().isEmpty) return null;
    HttpClient? client;
    try {
      final encoded = Uri.encodeComponent(query.trim());
      final uri = Uri.parse('https://wttr.in/$encoded?format=j1');
      client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, 'easync-account/1.0');
      final res = await req.close().timeout(const Duration(seconds: 6));
      final raw = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 6));

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final current = decoded['current_condition'];
      if (current is! List || current.isEmpty) return null;
      final first = current.first;
      if (first is! Map) return null;
      final tempRaw = first['temp_C']?.toString() ?? '';
      return double.tryParse(tempRaw);
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  Future<double?> _fetchOutsideTempFromCoordinates(
    double lat,
    double lon,
  ) async {
    HttpClient? client;
    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=${lat.toStringAsFixed(5)}&longitude=${lon.toStringAsFixed(5)}&current=temperature_2m&timezone=auto',
      );

      client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, 'easync-account/1.0');
      final res = await req.close().timeout(const Duration(seconds: 6));
      final raw = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 6));

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final current = decoded['current'];
      if (current is! Map) return null;
      final tempRaw = current['temperature_2m']?.toString() ?? '';
      return double.tryParse(tempRaw);
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  double _estimateTemperatureFromCoordinates(double lat, double lon) {
    final month = DateTime.now().month;
    final southernHemisphere = lat < 0;
    final isSummer = southernHemisphere
        ? (month == 12 || month <= 2)
        : (month >= 6 && month <= 8);
    final seasonOffset = isSummer ? 6.0 : -2.0;
    final latitudeCooling = (lat.abs() * 0.28).clamp(0.0, 13.0);
    final continentality = (lon.abs() % 30) * 0.06;
    return (27.5 + seasonOffset - latitudeCooling + continentality).clamp(
      -8.0,
      44.0,
    );
  }

  Future<void> _refreshOutsideTemperature({
    double? gpsLat,
    double? gpsLon,
  }) async {
    if (_outsideTempRefreshing) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _outsideTempRefreshing = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final query = _buildWeatherQueryFromPrefs(prefs);

      double? parsed;

      if (gpsLat != null && gpsLon != null) {
        parsed = await _fetchOutsideTempFromCoordinates(gpsLat, gpsLon);
      }

      parsed ??= await _fetchOutsideTempFromQuery(query);

      if (parsed == null && query.isNotEmpty) {
        try {
          final locations = await locationFromAddress(query);
          if (locations.isNotEmpty) {
            final l = locations.first;
            parsed = await _fetchOutsideTempFromCoordinates(
              l.latitude,
              l.longitude,
            );
            parsed ??= await _fetchOutsideTempFromQuery(
              '${l.latitude.toStringAsFixed(4)},${l.longitude.toStringAsFixed(4)}',
            );
            parsed ??= _estimateTemperatureFromCoordinates(
              l.latitude,
              l.longitude,
            );
          }
        } catch (_) {}
      }

      parsed ??= _inferOutsideTemperature();

      _outsideTemp = parsed;
      _outsideUpdatedAt = DateTime.now();
      final updatedAt = _outsideUpdatedAt;
      await prefs.setDouble(_kOutsideTempCache, _outsideTemp);
      if (updatedAt != null) {
        await prefs.setInt(
          _kOutsideTempUpdatedAt,
          updatedAt.millisecondsSinceEpoch,
        );
      }

      if (!mounted) return;
      setState(() {});
    } catch (_) {
      if (!mounted) return;
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            EaI18n.t(
              context,
              'Não foi possível atualizar a temperatura agora.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _outsideTempRefreshing = false);
    }
  }

  Future<String?> _resolveLocationFromTypedField() async {
    final prefs = await SharedPreferences.getInstance();
    final typed = (prefs.getString(_kProfileLocation) ?? '').trim();
    if (typed.isEmpty) return null;

    try {
      final forward = await locationFromAddress(typed);
      if (forward.isEmpty) return typed;

      final point = forward.first;
      final places = await placemarkFromCoordinates(
        point.latitude,
        point.longitude,
      );
      final p = places.isNotEmpty ? places.first : Placemark();
      final normalized = <String>[
        (p.street ?? '').trim(),
        (p.subLocality ?? '').trim(),
        (p.locality ?? '').trim(),
        (p.administrativeArea ?? '').trim(),
        (p.postalCode ?? '').trim(),
        (p.country ?? '').trim(),
      ].where((e) => e.isNotEmpty).toList().join(', ');

      return normalized.isEmpty ? typed : normalized;
    } catch (_) {
      return typed;
    }
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
        SnackBar(
          content: Text(
            EaI18n.t(
              context,
              'Firebase ainda não está configurado nesta build.',
            ),
          ),
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
        SnackBar(
          content: Text(
            EaI18n.t(
              context,
              'Firebase ainda não está configurado nesta build.',
            ),
          ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            EaI18n.t(context, 'Não foi possível escolher a imagem: {error}', {
              'error': '$e',
            }),
          ),
        ),
      );
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

  Future<void> _refreshCurrentLocation() async {
    if (_locationRefreshing) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _locationRefreshing = true);

    final prefs = await SharedPreferences.getInstance();
    final fallbackProfileLocation = (prefs.getString(_kProfileLocation) ?? '')
        .trim();

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              EaI18n.t(
                context,
                'Ative o serviço de localização (GPS) para atualizar o endereço.',
              ),
            ),
            action: SnackBarAction(
              label: EaI18n.t(context, 'Abrir ajustes'),
              onPressed: Geolocator.openLocationSettings,
            ),
          ),
        );
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              EaI18n.t(
                context,
                'Permissão de localização negada. Permita o acesso para atualizar.',
              ),
            ),
          ),
        );
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              EaI18n.t(
                context,
                'Permissão de localização bloqueada permanentemente. Libere nas configurações do app.',
              ),
            ),
            action: SnackBarAction(
              label: EaI18n.t(context, 'Abrir app'),
              onPressed: Geolocator.openAppSettings,
            ),
          ),
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      final places = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      final p = places.isNotEmpty ? places.first : Placemark();
      final full = <String>[
        (p.street ?? '').trim(),
        (p.subLocality ?? '').trim(),
        (p.locality ?? '').trim(),
        (p.administrativeArea ?? '').trim(),
        (p.postalCode ?? '').trim(),
        (p.country ?? '').trim(),
      ].where((e) => e.isNotEmpty).toList().join(', ');

      final safe = full.isEmpty
          ? (fallbackProfileLocation.isEmpty
                ? 'Localização desconhecida'
                : fallbackProfileLocation)
          : full;
      await prefs.setString(_kAddressFull, safe);

      if (!mounted) return;
      setState(() => _fullLocation = safe);
      await _refreshOutsideTemperature(
        gpsLat: position.latitude,
        gpsLon: position.longitude,
      );
    } on MissingPluginException {
      final geocoded = await _resolveLocationFromTypedField();
      final safe = (geocoded ?? fallbackProfileLocation).trim().isEmpty
          ? _fullLocation
          : (geocoded ?? fallbackProfileLocation).trim();
      await prefs.setString(_kAddressFull, safe);
      if (!mounted) return;
      setState(() => _fullLocation = safe);
      await _refreshOutsideTemperature();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            kIsWeb
                ? EaI18n.t(
                    context,
                    'GPS indisponível na Web. Usando o campo Localização como fallback.',
                  )
                : EaI18n.t(
                    context,
                    'GPS indisponível nesta plataforma. Usando o campo Localização como fallback.',
                  ),
          ),
        ),
      );
    } catch (e) {
      final geocoded = await _resolveLocationFromTypedField();
      if (geocoded != null && geocoded.trim().isNotEmpty) {
        final safe = geocoded.trim();
        await prefs.setString(_kAddressFull, safe);
        if (mounted) {
          setState(() => _fullLocation = safe);
        }
        await _refreshOutsideTemperature();
      }

      if (!mounted) return;
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            geocoded == null
                ? EaI18n.t(
                    context,
                    'Não foi possível atualizar localização: {error}',
                    {'error': '$e'},
                  )
                : EaI18n.t(
                    context,
                    'Localização atualizada com fallback do campo digitado.',
                  ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _locationRefreshing = false);
    }
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
            _sectionTitle(
              EaI18n.t(context, 'Profile and environment'),
              trailing: _profileUpdateButton(),
            ),
            const SizedBox(height: 6),
            EaFadeSlideIn(
              child: _block(
                children: [
                  _profileEnvironmentSummary(),
                  Divider(height: 1, color: EaAdaptiveColor.border(context)),
                  _profileInfoRow(
                    icon: Icons.badge_outlined,
                    label: EaI18n.t(context, 'Personal information'),
                    value: EaI18n.t(context, 'Name and location'),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PersonalInfoPage(),
                        ),
                      ).then((_) => _loadAccountState());
                    },
                    action: const SizedBox(
                      width: 20,
                      child: Icon(
                        Icons.chevron_right_rounded,
                        color: EaColor.fore,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  _profileInfoRow(
                    icon: Icons.language_outlined,
                    label: EaI18n.t(context, 'Language'),
                    value: _language,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LanguageRegionPage(),
                        ),
                      ).then((_) => _loadAccountState());
                    },
                    action: const SizedBox(
                      width: 20,
                      child: Icon(
                        Icons.chevron_right_rounded,
                        color: EaColor.fore,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _sectionTitle(EaI18n.t(context, 'Security')),
            const SizedBox(height: 6),
            EaFadeSlideIn(
              child: _block(
                children: [
                  _AccountTile(
                    icon: Icons.lock_outline_rounded,
                    title: EaI18n.t(context, 'Password and passkeys'),
                    subtitle: EaI18n.t(context, 'Credential management'),
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
                    title: EaI18n.t(context, '2-step verification'),
                    subtitle: EaI18n.t(context, 'Additional access protection'),
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
                    title: EaI18n.t(context, 'Trusted devices'),
                    subtitle: EaI18n.t(context, 'Current and recent sessions'),
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
            _sectionTitle(EaI18n.t(context, 'Subscription')),
            const SizedBox(height: 6),
            EaFadeSlideIn(
              child: _block(
                children: [
                  _AccountTile(
                    icon: Icons.workspace_premium_outlined,
                    title: 'EaSync Pro',
                    subtitle: EaI18n.t(
                      context,
                      'Detalhes do plano e benefícios',
                    ),
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
                    title: EaI18n.t(context, 'Billing history'),
                    subtitle: EaI18n.t(context, 'Invoices and payment methods'),
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
            _sectionTitle(EaI18n.t(context, 'Data control')),
            const SizedBox(height: 6),
            EaFadeSlideIn(
              child: _block(
                children: [
                  _AccountTile(
                    icon: Icons.download_outlined,
                    title: EaI18n.t(context, 'Export account data'),
                    subtitle: EaI18n.t(context, 'Portable backup package'),
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
                    title: EaI18n.t(context, 'Delete account'),
                    subtitle: EaI18n.t(context, 'Permanent removal flow'),
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
                            ? EaI18n.t(context, 'Authenticated account')
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
                  label: Text(EaI18n.t(context, 'Sign out')),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  EaI18n.t(context, 'You are not authenticated yet.'),
                  style: EaText.secondary.copyWith(
                    color: EaAdaptiveColor.bodyText(context),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: EaGradientButtonFrame(
                        borderRadius: BorderRadius.circular(12),
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: EaColor.back,
                            shadowColor: Colors.transparent,
                          ),
                          onPressed: _openSignIn,
                          icon: const Icon(Icons.login_rounded),
                          label: Text(EaI18n.t(context, 'Sign in')),
                        ),
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
                        label: Text(EaI18n.t(context, 'Create account')),
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
                _isAuthenticated
                    ? EaI18n.t(context, 'Authenticated')
                    : EaI18n.t(context, 'Guest'),
              ),
              _chip(
                Icons.security_outlined,
                _hasPassword
                    ? EaI18n.t(context, 'Password set')
                    : EaI18n.t(context, 'No password'),
              ),
              _chip(
                Icons.fingerprint,
                _fingerprintEnabled
                    ? EaI18n.t(context, 'Fingerprint enabled')
                    : EaI18n.t(context, 'Fingerprint disabled'),
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
    final photo = (_authPhoto ?? '').trim();
    final provider = photo.isEmpty
        ? null
        : (photo.startsWith('http')
              ? NetworkImage(photo)
              : FileImage(File(photo)) as ImageProvider);

    return GestureDetector(
      onTap: _pickProfileImage,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: EaColor.fore.withValues(alpha: 0.18),
            backgroundImage: provider,
            child: provider == null
                ? const Icon(
                    Icons.person_outline_rounded,
                    size: 20,
                    color: EaColor.fore,
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
                shape: BoxShape.circle,
                border: Border.all(color: EaColor.back, width: 1.2),
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

  Widget _profileEnvironmentSummary() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Row(
        children: [
          Expanded(
            child: _summaryTile(
              icon: Icons.thermostat,
              label: EaI18n.t(context, 'Outside'),
              value: '${_outsideTemp.toStringAsFixed(1)} °C',
              trailing: Icon(
                Icons.refresh_rounded,
                size: 14,
                color: EaColor.fore,
              ),
              onTap: _refreshOutsideTemperature,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _summaryTile(
              icon: Icons.place_outlined,
              label: EaI18n.t(context, 'Location'),
              value: _fullLocation,
              trailing: Icon(
                Icons.my_location_rounded,
                size: 14,
                color: EaColor.fore,
              ),
              onTap: _refreshCurrentLocation,
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryTile({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: BoxDecoration(
          color: EaAdaptiveColor.field(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: EaAdaptiveColor.border(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 15, color: EaColor.fore),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: EaText.small.copyWith(
                      color: EaAdaptiveColor.secondaryText(context),
                    ),
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: EaText.secondary.copyWith(
                color: EaAdaptiveColor.bodyText(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Widget? action,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: EaColor.fore),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: EaText.small.copyWith(
                      color: EaAdaptiveColor.bodyText(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: EaText.secondary.copyWith(
                      color: EaAdaptiveColor.secondaryText(context),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            ?action,
          ],
        ),
      ),
    );
  }

  Widget _profileUpdateButton() {
    final borderColor = EaColor.fore;
    final button = OutlinedButton.icon(
      onPressed: _locationRefreshing ? null : _refreshCurrentLocation,
      icon: Icon(Icons.my_location_rounded, size: 14, color: borderColor),
      label: Text(
        EaI18n.t(context, 'Update'),
        style: EaText.small.copyWith(color: EaAdaptiveColor.bodyText(context)),
      ),
      style: OutlinedButton.styleFrom(
        side: BorderSide(
          color: _locationRefreshing ? Colors.transparent : borderColor,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        foregroundColor: borderColor,
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
    );

    return SizedBox(
      width: 118,
      height: 32,
      child: _locationRefreshing
          ? RepaintBoundary(
              child: AnimatedBuilder(
                animation: _updatePulse,
                builder: (_, _) {
                  return CustomPaint(
                    painter: _UpdateBorderPainter(
                      progress: _updatePulse.value,
                      color: borderColor,
                    ),
                    child: button,
                  );
                },
              ),
            )
          : button,
    );
  }

  Widget _sectionTitle(String title, {Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: EaText.secondary.copyWith(
                fontWeight: FontWeight.w700,
                color: EaAdaptiveColor.bodyText(context),
              ),
            ),
          ),
          if (trailing != null) trailing,
        ],
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

class _UpdateBorderPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _UpdateBorderPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const radius = Radius.circular(12);
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect.deflate(.8), radius);

    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = color.withValues(alpha: .24);

    canvas.drawRRect(rrect, base);

    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics();
    if (!metrics.iterator.moveNext()) {
      return;
    }
    final metric = metrics.iterator.current;
    final length = metric.length;

    final segment = length * .22;
    final head = progress * length;
    final tail = head - segment;

    final active = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..color = color;

    if (tail >= 0) {
      canvas.drawPath(metric.extractPath(tail, head), active);
    } else {
      canvas.drawPath(metric.extractPath(length + tail, length), active);
      canvas.drawPath(metric.extractPath(0, head), active);
    }
  }

  @override
  bool shouldRepaint(covariant _UpdateBorderPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
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
        trailing: const Icon(Icons.chevron_right_rounded, color: EaColor.fore),
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
        SnackBar(
          content: Text(
            EaI18n.t(
              context,
              'Firebase ainda não está configurado para esta plataforma.',
            ),
          ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? EaI18n.t(context, 'Falha ao entrar.')),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            EaI18n.t(context, 'Falha ao entrar: {error}', {'error': '$e'}),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(EaI18n.t(context, 'Sign in'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _authField(_email, 'Email', false),
          const SizedBox(height: 10),
          _authField(_password, EaI18n.t(context, 'Password'), true),
          const SizedBox(height: 14),
          EaGradientButtonFrame(
            borderRadius: BorderRadius.circular(12),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: EaColor.back,
                shadowColor: Colors.transparent,
              ),
              onPressed: _loading ? null : _submit,
              icon: const Icon(Icons.login_rounded),
              label: Text(EaI18n.t(context, 'Continue')),
            ),
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
      SnackBar(
        content: Text(
          EaI18n.t(context, 'Código de verificação (demo): {code}', {
            'code': generated,
          }),
        ),
      ),
    );
  }

  Future<void> _submitSignUp() async {
    if (Firebase.apps.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            EaI18n.t(
              context,
              'Firebase ainda não está configurado para esta plataforma.',
            ),
          ),
        ),
      );
      return;
    }

    if (_pin.text.trim() != _expectedPin) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(EaI18n.t(context, 'PIN de verificação inválido.')),
        ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.message ?? EaI18n.t(context, 'Falha ao criar conta.'),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            EaI18n.t(context, 'Falha ao criar conta: {error}', {'error': '$e'}),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(EaI18n.t(context, 'Create account'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _authField(_name, EaI18n.t(context, 'Display name'), false),
          const SizedBox(height: 10),
          _authField(_email, 'Email', false),
          const SizedBox(height: 10),
          _authField(_password, EaI18n.t(context, 'Password'), true),
          const SizedBox(height: 12),
          if (!_awaitingPin)
            EaGradientButtonFrame(
              borderRadius: BorderRadius.circular(12),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: EaColor.back,
                  shadowColor: Colors.transparent,
                ),
                onPressed: _requestVerificationPin,
                icon: const Icon(Icons.pin_outlined),
                label: Text(EaI18n.t(context, 'Send verification PIN')),
              ),
            )
          else ...[
            Text(
              EaI18n.t(
                context,
                'Digite o PIN de 6 dígitos para concluir o cadastro',
              ),
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
            EaGradientButtonFrame(
              borderRadius: BorderRadius.circular(12),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: EaColor.back,
                  shadowColor: Colors.transparent,
                ),
                onPressed: _loading ? null : _submitSignUp,
                icon: const Icon(Icons.check_circle_outline),
                label: Text(EaI18n.t(context, 'Create account')),
              ),
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

  static const List<String> _locationSeed = [
    'Pelotas, Rio Grande do Sul, Brasil',
    'Porto Alegre, Rio Grande do Sul, Brasil',
    'Rio Grande, Rio Grande do Sul, Brasil',
    'Caxias do Sul, Rio Grande do Sul, Brasil',
    'Florianópolis, Santa Catarina, Brasil',
    'Curitiba, Paraná, Brasil',
    'São Paulo, São Paulo, Brasil',
    'Campinas, São Paulo, Brasil',
    'Rio de Janeiro, Rio de Janeiro, Brasil',
    'Belo Horizonte, Minas Gerais, Brasil',
    'Brasília, Distrito Federal, Brasil',
    'Salvador, Bahia, Brasil',
    'Recife, Pernambuco, Brasil',
    'Fortaleza, Ceará, Brasil',
    'Montevideo, Uruguay',
    'Buenos Aires, Argentina',
    'Santiago, Chile',
    'Lisboa, Portugal',
    'Porto, Portugal',
    'Madrid, Spain',
    'Paris, France',
    'Berlin, Germany',
    'Rome, Italy',
    'London, United Kingdom',
    'New York, United States',
    'San Francisco, United States',
    'Toronto, Canada',
  ];

  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _locationFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _locationFocusNode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _nameController.text = prefs.getString(_kFullName) ?? '';
    _locationController.text = prefs.getString(_kLocation) ?? '';
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final manualLocation = _locationController.text.trim();
    await prefs.setString(_kFullName, _nameController.text.trim());
    await prefs.setString(_kLocation, manualLocation);
    if (manualLocation.isNotEmpty) {
      await prefs.setString('profile.address.full', manualLocation);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(EaI18n.t(context, 'Dados salvos localmente.'))),
    );
  }

  Iterable<String> _locationSuggestions(TextEditingValue value) {
    final query = value.text.trim().toLowerCase();
    if (query.isEmpty) return _locationSeed.take(8);

    final startsWith = <String>[];
    final contains = <String>[];

    for (final option in _locationSeed) {
      final normalized = option.toLowerCase();
      if (normalized.startsWith(query)) {
        startsWith.add(option);
      } else if (normalized.contains(query)) {
        contains.add(option);
      }
    }

    return [...startsWith, ...contains].take(8);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(EaI18n.t(context, 'Informações pessoais'))),
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
                  _locationAutocompleteField(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          EaGradientButtonFrame(
            borderRadius: BorderRadius.circular(12),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: EaColor.back,
                shadowColor: Colors.transparent,
              ),
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(EaI18n.t(context, 'Salvar alterações')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _locationAutocompleteField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: RawAutocomplete<String>(
        textEditingController: _locationController,
        focusNode: _locationFocusNode,
        optionsBuilder: _locationSuggestions,
        onSelected: (value) => _locationController.text = value,
        fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
          return TextField(
            controller: controller,
            focusNode: focusNode,
            style: EaText.secondary.copyWith(
              color: EaAdaptiveColor.bodyText(context),
            ),
            decoration: _fieldDecoration(EaI18n.t(context, 'Localização'))
                .copyWith(
                  hintText: EaI18n.t(context, 'Digite cidade, estado ou país'),
                  hintStyle: EaText.small.copyWith(
                    color: EaAdaptiveColor.secondaryText(context),
                  ),
                ),
            onSubmitted: (_) => onSubmitted(),
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              color: EaAdaptiveColor.surface(context),
              elevation: 6,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: MediaQuery.of(context).size.width - 64,
                constraints: const BoxConstraints(maxHeight: 220),
                decoration: BoxDecoration(
                  color: EaAdaptiveColor.surface(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: EaAdaptiveColor.border(context)),
                ),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final option = options.elementAt(index);
                    return InkWell(
                      onTap: () => onSelected(option),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Text(
                          option,
                          style: EaText.small.copyWith(
                            color: EaAdaptiveColor.bodyText(context),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          );
        },
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
        decoration: _fieldDecoration(label),
      ),
    );
  }

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
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
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: EaColor.fore.withValues(alpha: 0.85),
          width: 1.2,
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
    final updatedAt = _updatedAt;
    await prefs.setDouble(_kOutsideTempCache, _outsideTemp);
    if (updatedAt != null) {
      await prefs.setInt(
        _kOutsideTempUpdatedAt,
        updatedAt.millisecondsSinceEpoch,
      );
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(EaI18n.t(context, 'Temperatura externa'))),
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
                        ? EaI18n.t(context, 'Sem atualização registrada.')
                        : EaI18n.t(context, 'Atualizado às {time}', {
                            'time':
                                '${_updatedAt?.hour.toString().padLeft(2, '0') ?? '--'}:${_updatedAt?.minute.toString().padLeft(2, '0') ?? '--'}',
                          }),
                    style: EaText.small.copyWith(
                      color: EaAdaptiveColor.secondaryText(context),
                    ),
                  ),
                  const SizedBox(height: 12),
                  EaGradientButtonFrame(
                    borderRadius: BorderRadius.circular(12),
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        foregroundColor: EaColor.back,
                        shadowColor: Colors.transparent,
                      ),
                      onPressed: _refreshFromDevices,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(
                        EaI18n.t(context, 'Atualizar pelos dispositivos'),
                      ),
                    ),
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(EaI18n.t(context, 'Endereço salvo localmente.'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(EaI18n.t(context, 'Endereço e localização'))),
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
                  _textField(_street, EaI18n.t(context, 'Rua')),
                  _textField(_city, EaI18n.t(context, 'Cidade')),
                  _textField(_postal, EaI18n.t(context, 'CEP')),
                  _textField(_country, EaI18n.t(context, 'País')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          EaGradientButtonFrame(
            borderRadius: BorderRadius.circular(12),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: EaColor.back,
                shadowColor: Colors.transparent,
              ),
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(EaI18n.t(context, 'Salvar endereço')),
            ),
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
    EaAppSettings.instance.setLocaleFromProfileLanguage(_language);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(EaI18n.t(context, 'Idioma e região atualizados.')),
      ),
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
      appBar: AppBar(title: Text(EaI18n.t(context, 'Idioma e região'))),
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
                    title: Text(EaI18n.t(context, 'Idioma')),
                    trailing: DropdownButton<String>(
                      value: _language,
                      items: [
                        DropdownMenuItem(
                          value: 'Português',
                          child: Text(EaI18n.t(context, 'Português')),
                        ),
                        DropdownMenuItem(
                          value: 'English',
                          child: Text(EaI18n.t(context, 'Inglês')),
                        ),
                        DropdownMenuItem(
                          value: 'Español',
                          child: Text(EaI18n.t(context, 'Español')),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _language = v);
                      },
                    ),
                  ),
                  ListTile(
                    title: Text(EaI18n.t(context, 'Região')),
                    trailing: DropdownButton<String>(
                      value: _region,
                      items: [
                        DropdownMenuItem(
                          value: 'Brasil',
                          child: Text(EaI18n.t(context, 'Brasil')),
                        ),
                        DropdownMenuItem(
                          value: 'Portugal',
                          child: Text(EaI18n.t(context, 'Portugal')),
                        ),
                        DropdownMenuItem(
                          value: 'United States',
                          child: Text(EaI18n.t(context, 'Estados Unidos')),
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
                    title: Text(EaI18n.t(context, 'Formato 24 horas')),
                    onChanged: (v) => setState(() => _time24h = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          EaGradientButtonFrame(
            borderRadius: BorderRadius.circular(12),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: EaColor.back,
                shadowColor: Colors.transparent,
              ),
              onPressed: _save,
              icon: const Icon(Icons.save_rounded),
              label: Text(EaI18n.t(context, 'Salvar preferências')),
            ),
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
      appBar: AppBar(title: Text(EaI18n.t(context, 'Senha e passkeys'))),
      body: ListView(
        children: [
          SwitchListTile.adaptive(
            value: _fingerprintEnabled,
            title: Text(EaI18n.t(context, 'Ativar desbloqueio por digital')),
            subtitle: Text(
              EaI18n.t(
                context,
                'Barreira biométrica no dispositivo (sem local_auth).',
              ),
            ),
            onChanged: _setFingerprint,
          ),
          ListTile(
            leading: const Icon(Icons.password_rounded),
            title: Text(
              _hasPassword
                  ? EaI18n.t(context, 'Alterar senha de login')
                  : EaI18n.t(context, 'Criar senha de login'),
            ),
            subtitle: Text(
              EaI18n.t(context, 'Configurar sua senha local de login'),
            ),
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
        SnackBar(
          content: Text(
            EaI18n.t(context, 'A senha precisa ter ao menos 4 caracteres.'),
          ),
        ),
      );
      return;
    }
    if (a != b) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(EaI18n.t(context, 'As senhas não coincidem.'))),
      );
      return;
    }

    await _secure.write(key: 'account.password', value: a);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(EaI18n.t(context, 'Senha salva com sucesso.'))),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(EaI18n.t(context, 'Senha de login'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _pwd,
            obscureText: true,
            decoration: InputDecoration(
              labelText: EaI18n.t(context, 'Nova senha'),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _confirm,
            obscureText: true,
            decoration: InputDecoration(
              labelText: EaI18n.t(context, 'Confirmar senha'),
            ),
          ),
          const SizedBox(height: 12),
          EaGradientButtonFrame(
            borderRadius: BorderRadius.circular(12),
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: EaColor.back,
                shadowColor: Colors.transparent,
              ),
              onPressed: _savePassword,
              child: Text(EaI18n.t(context, 'Salvar senha')),
            ),
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
      SnackBar(content: Text(EaI18n.t(context, '2FA atualizada com sucesso.'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(EaI18n.t(context, 'Verificação em 2 etapas'))),
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
                    title: Text(EaI18n.t(context, 'Aplicativo autenticador')),
                    onChanged: (v) => setState(() => _app = v),
                  ),
                  SwitchListTile.adaptive(
                    value: _sms,
                    title: Text(EaI18n.t(context, 'Verificação por SMS')),
                    onChanged: (v) => setState(() => _sms = v),
                  ),
                  SwitchListTile.adaptive(
                    value: _email,
                    title: Text(EaI18n.t(context, 'Verificação por email')),
                    onChanged: (v) => setState(() => _email = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          EaGradientButtonFrame(
            borderRadius: BorderRadius.circular(12),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.transparent,
                foregroundColor: EaColor.back,
                shadowColor: Colors.transparent,
              ),
              onPressed: _save,
              icon: const Icon(Icons.shield_outlined),
              label: Text(EaI18n.t(context, 'Salvar configurações de 2FA')),
            ),
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
      appBar: AppBar(title: Text(EaI18n.t(context, 'Dispositivos confiáveis'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ...List.generate(_devices.length, (i) {
            return EaFadeSlideIn(
              child: Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.devices_other_outlined,
                    color: EaColor.fore,
                  ),
                  title: Text(_devices[i]),
                  subtitle: Text(
                    i == 0
                        ? EaI18n.t(context, 'Sessão atual')
                        : EaI18n.t(context, 'Sessão confiável'),
                  ),
                  trailing: i == 0
                      ? const Icon(Icons.verified_rounded, color: EaColor.fore)
                      : IconButton(
                          icon: const Icon(
                            Icons.logout_rounded,
                            color: Colors.redAccent,
                          ),
                          tooltip: EaI18n.t(context, 'Remover dispositivo'),
                          onPressed: () => _removeAt(i),
                        ),
                  onTap: i == 0 ? null : () => _removeAt(i),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  tileColor: EaAdaptiveColor.surface(context),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  dense: false,
                  visualDensity: VisualDensity.standard,
                  isThreeLine: false,
                  horizontalTitleGap: 12,
                  minLeadingWidth: 0,
                  minVerticalPadding: 8,
                  enabled: true,
                  selected: false,
                  selectedTileColor: EaAdaptiveColor.surface(context),
                  selectedColor: EaAdaptiveColor.bodyText(context),
                  iconColor: EaAdaptiveColor.bodyText(context),
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
      appBar: AppBar(title: Text(EaI18n.t(context, 'EaSync Pro'))),
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
                    EaI18n.t(context, 'Plano atual: {plan}', {'plan': _plan}),
                    style: EaText.primary.copyWith(
                      color: EaAdaptiveColor.bodyText(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    EaI18n.t(
                      context,
                      'Automações, análises e controles avançados do assistente.',
                    ),
                    style: EaText.small.copyWith(
                      color: EaAdaptiveColor.secondaryText(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _planTile(
            'Free',
            EaI18n.t(context, 'Controles básicos de dispositivos e assistente'),
          ),
          _planTile(
            'Pro',
            EaI18n.t(context, 'Automações avançadas e modos completos de IA'),
          ),
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
      appBar: AppBar(title: Text(EaI18n.t(context, 'Histórico de cobranças'))),
      body: _items.isEmpty
          ? Center(
              child: Text(
                EaI18n.t(context, 'Nenhuma cobrança registrada ainda.'),
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
      SnackBar(
        content: Text(
          EaI18n.t(context, 'Export copiado para a área de transferência.'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(EaI18n.t(context, 'Exportar dados da conta'))),
      body: ListView(
        children: [
          CheckboxListTile(
            value: _includeProfile,
            onChanged: (v) => setState(() => _includeProfile = v ?? false),
            title: Text(EaI18n.t(context, 'Dados de perfil')),
          ),
          CheckboxListTile(
            value: _includeUsage,
            onChanged: (v) => setState(() => _includeUsage = v ?? false),
            title: Text(EaI18n.t(context, 'Dados de uso')),
          ),
          CheckboxListTile(
            value: _includeSecurity,
            onChanged: (v) => setState(() => _includeSecurity = v ?? false),
            title: Text(EaI18n.t(context, 'Configurações de segurança')),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: EaGradientButtonFrame(
              borderRadius: BorderRadius.circular(12),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: EaColor.back,
                  shadowColor: Colors.transparent,
                ),
                onPressed: _export,
                icon: const Icon(Icons.file_download_outlined),
                label: Text(EaI18n.t(context, 'Gerar exportação')),
              ),
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
        SnackBar(
          content: Text(
            EaI18n.t(context, 'Confirme digitando DELETE e marque a opção.'),
          ),
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(EaI18n.t(context, 'Dados locais da conta removidos.')),
      ),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(EaI18n.t(context, 'Excluir conta'))),
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
            child: Text(
              EaI18n.t(
                context,
                'Esta ação remove seus dados locais e não pode ser desfeita.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmController,
            decoration: InputDecoration(
              labelText: EaI18n.t(context, 'Digite DELETE para confirmar'),
            ),
          ),
          CheckboxListTile(
            value: _understand,
            onChanged: (v) => setState(() => _understand = v ?? false),
            title: Text(
              EaI18n.t(context, 'Entendo que esta operação é irreversível'),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: _delete,
            icon: const Icon(Icons.delete_forever_rounded),
            label: Text(EaI18n.t(context, 'Excluir dados locais da conta')),
          ),
        ],
      ),
    );
  }
}
