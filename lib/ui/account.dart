/*!
 * @file account.dart
 * @brief Account page with profile, security and connected app sections.
 * @param No external parameters.
 * @return Account management widgets in EaSync tile/block style.
 * @author Erick Radmann
 */

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import 'auth/provider.dart';
import 'auth/service.dart';
import 'handler.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Account extends StatefulWidget {
  const Account({super.key});

  @override
  State<Account> createState() => _AccountState();
}

class _AccountState extends State<Account> with SingleTickerProviderStateMixin {
  static String _normalizeLanguageValue(String raw) {
    final v = raw.trim().toLowerCase();
    if (v == 'portuguese' ||
        v == 'português' ||
        v == 'portugues' ||
        v == 'pt' ||
        v == 'pt-br') {
      return 'Português (Brasil)';
    }
    return 'English';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (mounted) _loadAccountState();
  }

  static const String _kOutsideTempCache = 'assistant.outside_temp_cache';
  static const String _kOutsideTempUpdatedAt =
      'assistant.outside_temp_updated_at';
  static const String _kAuthName = 'account.auth.name';
  static const String _kAuthUid = 'account.auth.uid';
  static const String _kAuthEmail = 'account.auth.email';
  static const String _kAuthPhoto = 'account.auth.photo';
  static const String _kAuthProvider = 'account.auth.provider';
  static const String _kFingerprintEnabled = 'account.security.fingerprint';
  static const String _kLanguage = 'profile.language';
  static const String _kAddressStreet = 'profile.address.street';
  static const String _kAddressCity = 'profile.address.city';
  static const String _kAddressPostal = 'profile.address.postal';
  static const String _kAddressCountry = 'profile.address.country';
  static const String _kAddressFull = 'profile.address.full';
  static const String _kProfileLocation = 'profile.location';

  final EaAppSettings _settings = EaAppSettings.instance;
  final ImagePicker _picker = ImagePicker();
  late final AnimationController _updatePulse;

  bool _isAuthenticated = false;
  String? _authName;
  String? _authEmail;
  String? _authPhoto;
  String? _authProvider;
  bool _fingerprintEnabled = false;
  double _outsideTemp = 0.0;
  DateTime? _outsideUpdatedAt;
  bool _outsideTempRefreshing = false;
  String _language = 'English';
  String _fullLocation = 'Unknown location';
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

    final saved = await OAuthService.instance.getSavedProfile();
    if (saved != null) {
      _authName = saved.name;
      _authEmail = saved.email;
      _authPhoto = saved.avatarUrl;
      _authProvider = saved.provider;
      _isAuthenticated = true;
    } else {
      _authName = prefs.getString(_kAuthName);
      _authEmail = prefs.getString(_kAuthEmail);
      _authPhoto = prefs.getString(_kAuthPhoto);
      _authProvider = prefs.getString(_kAuthProvider);
      final uid = (prefs.getString(_kAuthUid) ?? '').trim();
      final name = (_authName ?? '').trim();
      final email = (_authEmail ?? '').trim();
      final provider = (_authProvider ?? '').trim();
      _isAuthenticated =
          uid.isNotEmpty ||
          name.isNotEmpty ||
          email.isNotEmpty ||
          provider.isNotEmpty;
    }

    _fingerprintEnabled = prefs.getBool(_kFingerprintEnabled) ?? false;
    _language = _normalizeLanguageValue(prefs.getString(_kLanguage) ?? '');

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
                    : 'Unknown location'));

    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loginWith(OAuthProvider provider) async {
    try {
      final profile = await OAuthService.instance.login(provider);
      _authName = profile.name;
      _authEmail = profile.email;
      _authPhoto = profile.avatarUrl;
      _authProvider = profile.provider;
      _isAuthenticated = true;
      if (!mounted) return;
      setState(() {});
    } on OAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), behavior: SnackBarBehavior.floating),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unexpected error: $e')));
    }
  }

  void _openAuthSheet({required bool signUp}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AuthSheet(signUp: signUp, onLogin: _loginWith),
    );
  }

  Future<void> _signOut() async {
    await OAuthService.instance.logout();
    _authName = _authEmail = _authPhoto = _authProvider = null;
    _isAuthenticated = false;
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
    final unknownLocation = EaI18n.t(context, 'Unknown location');
    if (addressFull.isNotEmpty && addressFull != unknownLocation) {
      return addressFull;
    }
    final profileLocation = (prefs.getString(_kProfileLocation) ?? '').trim();
    if (profileLocation.isNotEmpty) return profileLocation;
    final city = (prefs.getString(_kAddressCity) ?? '').trim();
    final country = (prefs.getString(_kAddressCountry) ?? '').trim();
    if (city.isNotEmpty && country.isNotEmpty) return '$city, $country';
    if (city.isNotEmpty) return city;
    final current = _fullLocation.trim();
    if (current.isNotEmpty && current != unknownLocation) {
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
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=${lat.toStringAsFixed(5)}'
        '&longitude=${lon.toStringAsFixed(5)}'
        '&current=temperature_2m&timezone=auto',
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
                ? EaI18n.t(context, 'Unknown location')
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
        if (mounted) setState(() => _fullLocation = safe);
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
            EaI18n.t(context, 'Could not pick image: {error}', {'error': '$e'}),
          ),
        ),
      );
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
                      const SizedBox(height: 1),
                      Text(
                        _authEmail ?? '',
                        style: EaText.small.copyWith(
                          fontSize: 10,
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
                const SizedBox(height: 10),
                Row(
                  children: [
                    // Sign in
                    Expanded(
                      child: EaGradientButtonFrame(
                        borderRadius: BorderRadius.circular(12),
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: EaColor.back,
                            shadowColor: Colors.transparent,
                          ),
                          onPressed: () => _openAuthSheet(signUp: false),
                          icon: const Icon(Icons.login_rounded),
                          label: Text(EaI18n.t(context, 'Sign in')),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Sign up
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: EaColor.textPrimary,
                          side: BorderSide(
                            color: EaAdaptiveColor.border(context),
                          ),
                          backgroundColor: EaColor.back,
                        ),
                        onPressed: () => _openAuthSheet(signUp: true),
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        label: Text(EaI18n.t(context, 'Sign up')),
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
                    ? EaI18n.t(context, '${_authProvider!} Authenticated ')
                    : EaI18n.t(context, 'Not authenticated'),
              ),
              _chip(
                Icons.fingerprint,
                _fingerprintEnabled
                    ? EaI18n.t(context, 'Enabled')
                    : EaI18n.t(context, 'Disabled'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _profileAvatar() {
    final photo = (_authPhoto ?? '').trim();
    ImageProvider? provider;
    if (photo.isNotEmpty) {
      if (photo.startsWith('http')) {
        provider = NetworkImage(photo);
      } else {
        provider = FileImage(File(photo));
      }
    }

    return GestureDetector(
      onTap: _pickProfileImage,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: EaColor.fore.withValues(alpha: 0.18),
            backgroundImage: provider,
            onBackgroundImageError: provider == null ? null : (_, _) {},
            child: (provider == null)
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
        padding: const EdgeInsets.all(10),
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
                ?trailing,
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
                      fontWeight: FontWeight.w600,
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
                builder: (_, _) => CustomPaint(
                  painter: _UpdateBorderPainter(
                    progress: _updatePulse.value,
                    color: borderColor,
                  ),
                  child: button,
                ),
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
          ?trailing,
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

class _AuthSheet extends StatelessWidget {
  final bool signUp;
  final void Function(OAuthProvider) onLogin;

  const _AuthSheet({required this.signUp, required this.onLogin});

  @override
  Widget build(BuildContext context) {
    final isIosOrMac = !kIsWeb && (Platform.isIOS || Platform.isMacOS);

    return Container(
      decoration: BoxDecoration(
        color: EaAdaptiveColor.surface(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: EaAdaptiveColor.border(context)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        14,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Alça
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: EaAdaptiveColor.border(context),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(height: 22),

          // Título
          Text(
            signUp
                ? EaI18n.t(context, 'Create your account')
                : EaI18n.t(context, 'Welcome back'),
            style: EaText.primary.copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: EaAdaptiveColor.bodyText(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            signUp
                ? EaI18n.t(context, 'Choose a provider to get started')
                : EaI18n.t(context, 'Choose a provider to continue'),
            style: EaText.small.copyWith(
              color: EaAdaptiveColor.secondaryText(context),
            ),
          ),
          const SizedBox(height: 28),

          // Google
          _ProviderButton(
            label: 'Google',
            icon: const _GoogleIcon(),
            onTap: () {
              Navigator.pop(context);
              onLogin(OAuthProvider.google);
            },
          ),
          const SizedBox(height: 10),

          // Microsoft
          _ProviderButton(
            label: 'Microsoft',
            icon: const _MicrosoftIcon(),
            onTap: () {
              Navigator.pop(context);
              onLogin(OAuthProvider.microsoft);
            },
          ),

          // Apple — iOS e macOS apenas
          if (isIosOrMac) ...[
            const SizedBox(height: 10),
            _ProviderButton(
              label: 'Apple',
              icon: Icon(
                Icons.apple_rounded,
                size: 22,
                color: EaAdaptiveColor.bodyText(context),
              ),
              onTap: () {
                Navigator.pop(context);
                onLogin(OAuthProvider.apple);
              },
            ),
          ],

          const SizedBox(height: 24),

          // Rodapé
          Text(
            EaI18n.t(
              context,
              'By continuing you agree to our Terms of Service.',
            ),
            textAlign: TextAlign.center,
            style: EaText.small.copyWith(
              color: EaAdaptiveColor.secondaryText(context),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ProviderButton extends StatelessWidget {
  final String label;
  final Widget icon;
  final VoidCallback onTap;

  const _ProviderButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: EaAdaptiveColor.border(context)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          backgroundColor: EaAdaptiveColor.field(context),
          padding: const EdgeInsets.symmetric(horizontal: 18),
        ),
        child: Row(
          children: [
            SizedBox(width: 26, child: Center(child: icon)),
            const SizedBox(width: 14),
            Text(
              label,
              style: EaText.secondary.copyWith(
                color: EaAdaptiveColor.bodyText(context),
                fontWeight: FontWeight.w500,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoogleIcon extends StatelessWidget {
  const _GoogleIcon();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 22,
    height: 22,
    child: CustomPaint(painter: _GooglePainter()),
  );
}

class _GooglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    const colors = [
      Color(0xFF4285F4),
      Color(0xFF34A853),
      Color(0xFFFBBC05),
      Color(0xFFEA4335),
    ];

    const sweep = 3.14159265 * 2 / 4; // 90°

    for (int i = 0; i < 4; i++) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r * 0.72),
        -1.5708 + sweep * i,
        sweep * 0.92,
        false,
        Paint()
          ..color = colors[i]
          ..style = PaintingStyle.stroke
          ..strokeWidth = size.width * 0.22,
      );
    }

    // Barra horizontal
    canvas.drawLine(
      Offset(cx, cy),
      Offset(size.width * 0.96, cy),
      Paint()
        ..color = const Color(0xFF4285F4)
        ..strokeWidth = size.height * 0.22
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
}

class _MicrosoftIcon extends StatelessWidget {
  const _MicrosoftIcon();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 22,
    height: 22,
    child: CustomPaint(painter: _MicrosoftPainter()),
  );
}

class _MicrosoftPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final half = size.width / 2 - 1.0;
    const gap = 2.0;

    final rects = [
      Rect.fromLTWH(0, 0, half, half),
      Rect.fromLTWH(half + gap, 0, half, half),
      Rect.fromLTWH(0, half + gap, half, half),
      Rect.fromLTWH(half + gap, half + gap, half, half),
    ];

    const colors = [
      Color(0xFFF25022),
      Color(0xFF7FBA00),
      Color(0xFFFFB900),
      Color(0xFF00A4EF),
    ];

    for (int i = 0; i < 4; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rects[i], const Radius.circular(1.5)),
        Paint()..color = colors[i],
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter _) => false;
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

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = color.withValues(alpha: .24),
    );

    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics();
    if (!metrics.iterator.moveNext()) return;

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
  bool shouldRepaint(covariant _UpdateBorderPainter old) =>
      old.progress != progress || old.color != color;
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Icon(icon, color: danger ? Colors.redAccent : EaColor.fore),
        title: Text(
          title,
          style: EaText.secondary.copyWith(
            color: danger
                ? Colors.redAccent
                : EaAdaptiveColor.bodyText(context),
            fontWeight: FontWeight.w600,
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

class PersonalInfoPage extends StatefulWidget {
  const PersonalInfoPage({super.key});

  @override
  State<PersonalInfoPage> createState() => _PersonalInfoPageState();
}

class _PersonalInfoPageState extends State<PersonalInfoPage> {
  static const _kFullName = 'profile.full_name';
  static const _kLocation = 'profile.location';
  static const _kAuthName = 'account.auth.name';

  static const List<String> _locationSeed = [
    // Brasil
    'Pelotas, Rio Grande do Sul, Brasil',
    'Porto Alegre, Rio Grande do Sul, Brasil',
    'Rio Grande, Rio Grande do Sul, Brasil',
    'Caxias do Sul, Rio Grande do Sul, Brasil',
    'Santa Maria, Rio Grande do Sul, Brasil',
    'Passo Fundo, Rio Grande do Sul, Brasil',
    'Florianópolis, Santa Catarina, Brasil',
    'Joinville, Santa Catarina, Brasil',
    'Blumenau, Santa Catarina, Brasil',
    'Curitiba, Paraná, Brasil',
    'Londrina, Paraná, Brasil',
    'Maringá, Paraná, Brasil',
    'São Paulo, São Paulo, Brasil',
    'Campinas, São Paulo, Brasil',
    'Santos, São Paulo, Brasil',
    'Ribeirão Preto, São Paulo, Brasil',
    'Rio de Janeiro, Rio de Janeiro, Brasil',
    'Niterói, Rio de Janeiro, Brasil',
    'Belo Horizonte, Minas Gerais, Brasil',
    'Uberlândia, Minas Gerais, Brasil',
    'Brasília, Distrito Federal, Brasil',
    'Salvador, Bahia, Brasil',
    'Feira de Santana, Bahia, Brasil',
    'Recife, Pernambuco, Brasil',
    'Fortaleza, Ceará, Brasil',
    'Manaus, Amazonas, Brasil',
    'Belém, Pará, Brasil',
    'Goiânia, Goiás, Brasil',
    'Campo Grande, Mato Grosso do Sul, Brasil',
    'Cuiabá, Mato Grosso, Brasil',
    'Palmas, Tocantins, Brasil',

    // América do Sul
    'Montevideo, Uruguay',
    'Punta del Este, Uruguay',
    'Buenos Aires, Argentina',
    'Córdoba, Argentina',
    'Rosario, Argentina',
    'Mendoza, Argentina',
    'La Plata, Argentina',
    'Santiago, Chile',
    'Valparaíso, Chile',
    'Concepción, Chile',
    'Lima, Peru',
    'Arequipa, Peru',
    'Bogotá, Colombia',
    'Medellín, Colombia',
    'Cali, Colombia',
    'Cartagena, Colombia',
    'Caracas, Venezuela',
    'Maracaibo, Venezuela',
    'Quito, Ecuador',
    'Guayaquil, Ecuador',
    'La Paz, Bolivia',
    'Santa Cruz, Bolivia',
    'Asunción, Paraguay',

    // América do Norte
    'New York, United States',
    'Los Angeles, United States',
    'Chicago, United States',
    'Houston, United States',
    'Phoenix, United States',
    'Philadelphia, United States',
    'San Antonio, United States',
    'San Diego, United States',
    'Dallas, United States',
    'San Jose, United States',
    'Austin, United States',
    'Jacksonville, United States',
    'San Francisco, United States',
    'Columbus, United States',
    'Indianapolis, United States',
    'Seattle, United States',
    'Denver, United States',
    'Washington, United States',
    'Boston, United States',
    'Miami, United States',
    'Atlanta, United States',
    'Detroit, United States',
    'Minneapolis, United States',
    'Las Vegas, United States',
    'Toronto, Canada',
    'Vancouver, Canada',
    'Montreal, Canada',
    'Ottawa, Canada',
    'Calgary, Canada',
    'Edmonton, Canada',
    'Quebec City, Canada',
    'Mexico City, Mexico',
    'Guadalajara, Mexico',
    'Monterrey, Mexico',
    'Tijuana, Mexico',
    'Cancún, Mexico',

    // Europa
    'Lisboa, Portugal',
    'Porto, Portugal',
    'Braga, Portugal',
    'Madrid, Spain',
    'Barcelona, Spain',
    'Valencia, Spain',
    'Seville, Spain',
    'Bilbao, Spain',
    'Paris, France',
    'Marseille, France',
    'Lyon, France',
    'Nice, France',
    'Berlin, Germany',
    'Hamburg, Germany',
    'Munich, Germany',
    'Frankfurt, Germany',
    'Cologne, Germany',
    'Rome, Italy',
    'Milan, Italy',
    'Naples, Italy',
    'Turin, Italy',
    'Florence, Italy',
    'London, United Kingdom',
    'Manchester, United Kingdom',
    'Birmingham, United Kingdom',
    'Liverpool, United Kingdom',
    'Leeds, United Kingdom',
    'Glasgow, United Kingdom',
    'Edinburgh, United Kingdom',
    'Amsterdam, Netherlands',
    'Rotterdam, Netherlands',
    'The Hague, Netherlands',
    'Brussels, Belgium',
    'Antwerp, Belgium',
    'Vienna, Austria',
    'Salzburg, Austria',
    'Zurich, Switzerland',
    'Geneva, Switzerland',
    'Basel, Switzerland',
    'Stockholm, Sweden',
    'Gothenburg, Sweden',
    'Oslo, Norway',
    'Copenhagen, Denmark',
    'Helsinki, Finland',
    'Dublin, Ireland',
    'Prague, Czech Republic',
    'Warsaw, Poland',
    'Krakow, Poland',
    'Budapest, Hungary',
    'Athens, Greece',
    'Thessaloniki, Greece',
    'Istanbul, Turkey',
    'Ankara, Turkey',
    'Moscow, Russia',
    'Saint Petersburg, Russia',
    'Kyiv, Ukraine',

    // Ásia
    'Tokyo, Japan',
    'Osaka, Japan',
    'Kyoto, Japan',
    'Nagoya, Japan',
    'Seoul, South Korea',
    'Busan, South Korea',
    'Incheon, South Korea',
    'Beijing, China',
    'Shanghai, China',
    'Shenzhen, China',
    'Guangzhou, China',
    'Chengdu, China',
    'Hong Kong, China',
    'Taipei, Taiwan',
    'Bangkok, Thailand',
    'Chiang Mai, Thailand',
    'Singapore, Singapore',
    'Kuala Lumpur, Malaysia',
    'Penang, Malaysia',
    'Jakarta, Indonesia',
    'Bali, Indonesia',
    'Manila, Philippines',
    'Cebu, Philippines',
    'Hanoi, Vietnam',
    'Ho Chi Minh City, Vietnam',
    'New Delhi, India',
    'Mumbai, India',
    'Bangalore, India',
    'Hyderabad, India',
    'Chennai, India',
    'Kolkata, India',
    'Pune, India',
    'Karachi, Pakistan',
    'Lahore, Pakistan',
    'Islamabad, Pakistan',
    'Dhaka, Bangladesh',
    'Colombo, Sri Lanka',
    'Kathmandu, Nepal',
    'Dubai, United Arab Emirates',
    'Abu Dhabi, United Arab Emirates',
    'Sharjah, United Arab Emirates',
    'Doha, Qatar',
    'Riyadh, Saudi Arabia',
    'Jeddah, Saudi Arabia',
    'Mecca, Saudi Arabia',
    'Tehran, Iran',
    'Baghdad, Iraq',
    'Tel Aviv, Israel',
    'Jerusalem, Israel',

    // África
    'Cairo, Egypt',
    'Alexandria, Egypt',
    'Lagos, Nigeria',
    'Abuja, Nigeria',
    'Nairobi, Kenya',
    'Mombasa, Kenya',
    'Johannesburg, South Africa',
    'Cape Town, South Africa',
    'Durban, South Africa',
    'Pretoria, South Africa',
    'Casablanca, Morocco',
    'Rabat, Morocco',
    'Marrakesh, Morocco',
    'Algiers, Algeria',
    'Tunis, Tunisia',
    'Accra, Ghana',
    'Addis Ababa, Ethiopia',
    'Dakar, Senegal',

    // Oceania
    'Sydney, Australia',
    'Melbourne, Australia',
    'Brisbane, Australia',
    'Perth, Australia',
    'Adelaide, Australia',
    'Gold Coast, Australia',
    'Auckland, New Zealand',
    'Wellington, New Zealand',
    'Christchurch, New Zealand',
  ];

  final _nameController = TextEditingController();
  final _locationController = TextEditingController();
  final _locationFocusNode = FocusNode();

  static String _normalizeSearch(String input) {
    return input
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('ã', 'a')
        .replaceAll('â', 'a')
        .replaceAll('ä', 'a')
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('ë', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ì', 'i')
        .replaceAll('î', 'i')
        .replaceAll('ï', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ò', 'o')
        .replaceAll('õ', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('ö', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ù', 'u')
        .replaceAll('û', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ç', 'c');
  }

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
    final savedName = (prefs.getString(_kFullName) ?? '').trim();
    final authName = (prefs.getString(_kAuthName) ?? '').trim();
    _nameController.text = savedName.isNotEmpty ? savedName : authName;
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
      SnackBar(content: Text(EaI18n.t(context, 'Data saved locally.'))),
    );
  }

  Iterable<String> _locationSuggestions(TextEditingValue value) {
    final query = _normalizeSearch(value.text.trim());
    if (query.isEmpty) return _locationSeed.take(30);
    final startsWith = <String>[];
    final contains = <String>[];
    for (final option in _locationSeed) {
      final n = _normalizeSearch(option);
      if (n.startsWith(query)) {
        startsWith.add(option);
      } else if (n.contains(query)) {
        contains.add(option);
      }
    }
    return [...startsWith, ...contains].take(30);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(EaI18n.t(context, 'Personal information'))),
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
                  _field(_nameController, EaI18n.t(context, 'Full name')),
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
              label: Text(EaI18n.t(context, 'Save changes')),
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
        onSelected: (v) => _locationController.text = v,
        fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
          return TextField(
            controller: controller,
            focusNode: focusNode,
            style: EaText.secondary.copyWith(
              color: EaAdaptiveColor.bodyText(context),
            ),
            decoration: _fieldDecoration(EaI18n.t(context, 'Location'))
                .copyWith(
                  hintText: EaI18n.t(context, 'Type city, state or country'),
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
                constraints: const BoxConstraints(maxHeight: 360),
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

  Widget _field(TextEditingController c, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
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

class LanguageRegionPage extends StatefulWidget {
  const LanguageRegionPage({super.key});

  @override
  State<LanguageRegionPage> createState() => _LanguageRegionPageState();
}

class _LanguageRegionPageState extends State<LanguageRegionPage> {
  static const _kLanguage = 'profile.language';
  static const _kRegion = 'profile.region';
  static const _kTimeFormat24h = 'profile.time_24h';

  String _language = 'English';
  String _region = 'United States';
  bool _time24h = true;

  static String _normalizeLanguageValue(String raw) {
    final v = raw.trim().toLowerCase();
    if (v == 'portuguese' ||
        v == 'português' ||
        v == 'portugues' ||
        v == 'pt' ||
        v == 'pt-br') {
      return 'Portuguese';
    }
    return 'English';
  }

  static String _normalizeRegionValue(String raw) {
    final v = raw.trim().toLowerCase();
    if (v == 'brazil' || v == 'brasil') return 'Brazil';
    if (v == 'united states' || v == 'estados unidos' || v == 'usa') {
      return 'United States';
    }
    return 'United States';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _language = _normalizeLanguageValue(prefs.getString(_kLanguage) ?? '');
    _region = _normalizeRegionValue(prefs.getString(_kRegion) ?? _region);
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
        content: Text(EaI18n.t(context, 'Language and region updated.')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(EaI18n.t(context, 'Language and region'))),
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
                    title: Text(EaI18n.t(context, 'Language')),
                    trailing: DropdownButton<String>(
                      value: _language,
                      items: [
                        DropdownMenuItem(
                          value: 'English',
                          child: Text(EaI18n.t(context, 'English')),
                        ),
                        DropdownMenuItem(
                          value: 'Portuguese',
                          child: Text(EaI18n.t(context, 'Portuguese')),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _language = v);
                      },
                    ),
                  ),
                  ListTile(
                    title: Text(EaI18n.t(context, 'Region')),
                    trailing: DropdownButton<String>(
                      value: _region,
                      items: [
                        DropdownMenuItem(
                          value: 'United States',
                          child: Text(EaI18n.t(context, 'United States')),
                        ),
                        DropdownMenuItem(
                          value: 'Brazil',
                          child: Text(EaI18n.t(context, 'Brazil')),
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
                    activeThumbColor: EaColor.fore,
                    inactiveThumbColor: EaAdaptiveColor.border(context),
                    inactiveTrackColor: EaAdaptiveColor.field(context),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    title: Text(
                      EaI18n.t(context, '24-hour format'),
                      style: EaText.small.copyWith(
                        color: EaAdaptiveColor.bodyText(context),
                      ),
                    ),
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
              label: Text(EaI18n.t(context, 'Save preferences')),
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
      appBar: AppBar(title: Text(EaI18n.t(context, 'Password and passkeys'))),
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
                    value: _fingerprintEnabled,
                    title: Text(
                      EaI18n.t(context, 'Enable fingerprint unlock'),
                      style: EaText.secondary.copyWith(
                        color: EaAdaptiveColor.bodyText(context),
                      ),
                    ),
                    subtitle: Text(
                      EaI18n.t(
                        context,
                        'Biometric barrier on the device (without local_auth).',
                      ),
                      style: EaText.small.copyWith(
                        color: EaAdaptiveColor.secondaryText(context),
                      ),
                    ),
                    onChanged: _setFingerprint,
                  ),
                  Divider(height: 1, color: EaAdaptiveColor.border(context)),
                  ListTile(
                    leading: const Icon(Icons.password_rounded),
                    title: Text(
                      _hasPassword
                          ? EaI18n.t(context, 'Change login password')
                          : EaI18n.t(context, 'Create login password'),
                      style: EaText.secondary.copyWith(
                        color: EaAdaptiveColor.bodyText(context),
                      ),
                    ),
                    subtitle: Text(
                      EaI18n.t(context, 'Configure your local login password'),
                      style: EaText.small.copyWith(
                        color: EaAdaptiveColor.secondaryText(context),
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PasswordSetupPage(),
                        ),
                      ).then((_) => _load());
                    },
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
            EaI18n.t(context, 'Password must have at least 4 characters.'),
          ),
        ),
      );
      return;
    }
    if (a != b) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(EaI18n.t(context, 'Passwords do not match.'))),
      );
      return;
    }
    await _secure.write(key: 'account.password', value: a);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(EaI18n.t(context, 'Password saved successfully.')),
      ),
    );
    Navigator.pop(context);
  }

  InputDecoration _inputDecoration(BuildContext context, String label) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(EaI18n.t(context, 'Login password'))),
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
                  TextField(
                    controller: _pwd,
                    obscureText: true,
                    style: EaText.secondary.copyWith(
                      color: EaAdaptiveColor.bodyText(context),
                    ),
                    decoration: _inputDecoration(
                      context,
                      EaI18n.t(context, 'New password'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _confirm,
                    obscureText: true,
                    style: EaText.secondary.copyWith(
                      color: EaAdaptiveColor.bodyText(context),
                    ),
                    decoration: _inputDecoration(
                      context,
                      EaI18n.t(context, 'Confirm password'),
                    ),
                  ),
                ],
              ),
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
              child: Text(EaI18n.t(context, 'Save password')),
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
      appBar: AppBar(title: Text(EaI18n.t(context, '2-step verification'))),
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
                    title: Text(EaI18n.t(context, 'Authenticator app')),
                    onChanged: (v) => setState(() => _app = v),
                  ),
                  SwitchListTile.adaptive(
                    value: _sms,
                    title: Text(EaI18n.t(context, 'SMS verification')),
                    onChanged: (v) => setState(() => _sms = v),
                  ),
                  SwitchListTile.adaptive(
                    value: _email,
                    title: Text(EaI18n.t(context, 'Email verification')),
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
              label: Text(EaI18n.t(context, 'Save 2FA settings')),
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
        ['${Platform.operatingSystem.toUpperCase()} • This device'];
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
      appBar: AppBar(title: Text(EaI18n.t(context, 'Trusted devices'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: List.generate(_devices.length, (i) {
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
                      ? EaI18n.t(context, 'Current session')
                      : EaI18n.t(context, 'Trusted session'),
                ),
                trailing: i == 0
                    ? const Icon(Icons.verified_rounded, color: EaColor.fore)
                    : IconButton(
                        icon: const Icon(
                          Icons.logout_rounded,
                          color: Colors.redAccent,
                        ),
                        tooltip: EaI18n.t(context, 'Remove device'),
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
              ),
            ),
          );
        }),
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
                    EaI18n.t(context, 'Current plan: {plan}', {'plan': _plan}),
                    style: EaText.primary.copyWith(
                      color: EaAdaptiveColor.bodyText(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    EaI18n.t(
                      context,
                      'Advanced automations, analytics, and assistant controls.',
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
            EaI18n.t(context, 'Basic device and assistant controls'),
          ),
          _planTile(
            'Pro',
            EaI18n.t(context, 'Advanced automations and full AI modes'),
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
      appBar: AppBar(title: Text(EaI18n.t(context, 'Billing history'))),
      body: _items.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                decoration: BoxDecoration(
                  color: EaAdaptiveColor.surface(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: EaAdaptiveColor.border(context)),
                ),
                padding: const EdgeInsets.all(18),
                child: Text(
                  EaI18n.t(context, 'No billing entries yet.'),
                  textAlign: TextAlign.center,
                  style: EaText.secondary.copyWith(
                    color: EaAdaptiveColor.secondaryText(context),
                  ),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _items.length,
              itemBuilder: (_, i) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: EaAdaptiveColor.surface(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: EaAdaptiveColor.border(context)),
                ),
                child: ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: Text(
                    _items[i],
                    style: EaText.secondary.copyWith(
                      color: EaAdaptiveColor.bodyText(context),
                    ),
                  ),
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
      SnackBar(content: Text(EaI18n.t(context, 'Export copied to clipboard.'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(EaI18n.t(context, 'Export account data'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            decoration: BoxDecoration(
              color: EaAdaptiveColor.surface(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: EaAdaptiveColor.border(context)),
            ),
            child: Column(
              children: [
                CheckboxListTile(
                  value: _includeProfile,
                  onChanged: (v) =>
                      setState(() => _includeProfile = v ?? false),
                  title: Text(
                    EaI18n.t(context, 'Profile data'),
                    style: EaText.secondary.copyWith(
                      color: EaAdaptiveColor.bodyText(context),
                    ),
                  ),
                ),
                Divider(height: 1, color: EaAdaptiveColor.border(context)),
                CheckboxListTile(
                  value: _includeUsage,
                  onChanged: (v) => setState(() => _includeUsage = v ?? false),
                  title: Text(
                    EaI18n.t(context, 'Usage data'),
                    style: EaText.secondary.copyWith(
                      color: EaAdaptiveColor.bodyText(context),
                    ),
                  ),
                ),
                Divider(height: 1, color: EaAdaptiveColor.border(context)),
                CheckboxListTile(
                  value: _includeSecurity,
                  onChanged: (v) =>
                      setState(() => _includeSecurity = v ?? false),
                  title: Text(
                    EaI18n.t(context, 'Security settings'),
                    style: EaText.secondary.copyWith(
                      color: EaAdaptiveColor.bodyText(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 16),
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
                label: Text(EaI18n.t(context, 'Generate export')),
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
            EaI18n.t(
              context,
              'Confirm by typing DELETE and checking the option.',
            ),
          ),
        ),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await OAuthService.instance.logout();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(EaI18n.t(context, 'Local account data removed.'))),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(EaI18n.t(context, 'Delete account'))),
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
                'This action removes your local data and cannot be undone.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmController,
            decoration: InputDecoration(
              labelText: EaI18n.t(context, 'Type DELETE to confirm'),
            ),
          ),
          CheckboxListTile(
            value: _understand,
            onChanged: (v) => setState(() => _understand = v ?? false),
            title: Text(
              EaI18n.t(context, 'I understand this operation is irreversible'),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: _delete,
            icon: const Icon(Icons.delete_forever_rounded),
            label: Text(EaI18n.t(context, 'Delete local account data')),
          ),
        ],
      ),
    );
  }
}
