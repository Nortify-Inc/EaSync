/*!
 * @file account.dart
 * @brief Account page with profile, security and connected app sections.
 * @param No external parameters.
 * @return Account management widgets in EaSync tile/block style.
 * @author Erick Radmann
 */

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import 'auth/provider.dart';
import 'auth/security.dart';
import 'auth/service.dart';
import 'handler.dart';
import 'legalConsent.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Account extends StatefulWidget {
  const Account({super.key});

  @override
  State<Account> createState() => _AccountState();
}

class _AccountState extends State<Account> with SingleTickerProviderStateMixin {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (mounted) _loadAccountState();
  }

  static const String _kOutsideTempCache = 'assistant.outside_temp_cache';
  static const String _kOutsideConditionCache =
      'assistant.outside_condition_cache';
  static const String _kOutsideTempUpdatedAt =
      'assistant.outside_temp_updated_at';
  static const String _kAuthName = 'account.auth.name';
  static const String _kAuthUid = 'account.auth.uid';
  static const String _kAuthEmail = 'account.auth.email';
  static const String _kAuthPhoto = 'account.auth.photo';
  static const String _kAuthProvider = 'account.auth.provider';
  static const String _kFingerprintEnabled = 'account.security.fingerprint';
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
  bool _authBusy = false;
  String? _authName;
  String? _authEmail;
  String? _authPhoto;
  String? _authProvider;
  bool _fingerprintEnabled = false;
  double _outsideTemp = 0.0;
  String _outsideCondition = '';
  DateTime? _outsideUpdatedAt;
  bool _outsideTempRefreshing = false;
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
    final cachedCondition = (prefs.getString(_kOutsideConditionCache) ?? '')
        .trim();
    final updatedAtMs = prefs.getInt(_kOutsideTempUpdatedAt);

    if (cachedTemp != null) {
      _outsideTemp = cachedTemp;
      _outsideCondition = cachedCondition;
    } else {
      _outsideTemp = _inferOutsideTemperature();
      _outsideCondition = '';
      await prefs.setDouble(_kOutsideTempCache, _outsideTemp);
      await prefs.setString(_kOutsideConditionCache, _outsideCondition);
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
    if (_authBusy) return;
    if (mounted) setState(() => _authBusy = true);
    try {
      final profile = await OAuthService.instance.login(provider);

      final security = await AppSecurityService.instance
          .readStartupSecurityState();
      if (security.requiresAuthenticatorCode) {
        var unlocked = false;
        var attempts = 0;
        while (mounted && attempts < 5) {
          attempts++;
          final normalized = await _askAuthenticatorCodeForSecurityAccess();
          if (!mounted || normalized == null) break;

          final ok = await AppSecurityService.instance.verifyAuthenticatorCode(
            normalized,
          );
          if (ok) {
            unlocked = true;
            break;
          }

          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text(EaI18n.t(context, 'Invalid code. Try again.')),
            ),
          );
        }

        if (!unlocked) {
          await OAuthService.instance.logout();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text(EaI18n.t(context, 'Sign-in failed.')),
            ),
          );
          return;
        }
      }

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            EaI18n.t(context, 'Unexpected error: {error}', {'error': '$e'}),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _authBusy = false);
    }
  }

  void _openAuthSheet({required bool signUp}) {
    if (_authBusy) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AuthSheet(
        signUp: signUp,
        onLogin: _loginWith,
        onOpenTerms: _openTermsOfUse,
        onOpenPrivacy: _openPrivacyPolicy,
      ),
    );
  }

  void _openTermsOfUse() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LegalArticlePage(
          articleType: LegalArticleType.contracts,
          isPtBr: Localizations.localeOf(context).languageCode == 'pt',
        ),
      ),
    );
  }

  void _openPrivacyPolicy() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LegalArticlePage(
          articleType: LegalArticleType.privacyTerms,
          isPtBr: Localizations.localeOf(context).languageCode == 'pt',
        ),
      ),
    );
  }

  Future<void> _openTwoStepVerificationSafely() async {
    final security = await AppSecurityService.instance
        .readStartupSecurityState();
    if (!mounted) return;

    if (security.requiresAuthenticatorCode) {
      var unlocked = false;
      var attempts = 0;
      while (mounted && attempts < 5) {
        attempts++;
        final normalized = await _askAuthenticatorCodeForSecurityAccess();
        if (!mounted || normalized == null) return;

        final ok = await AppSecurityService.instance.verifyAuthenticatorCode(
          normalized,
        );
        if (ok) {
          unlocked = true;
          break;
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(EaI18n.t(context, 'Invalid code. Try again.')),
          ),
        );
      }
      if (!unlocked) return;
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TwoStepVerificationPage()),
    );
  }

  Future<String?> _askAuthenticatorCodeForSecurityAccess() async {
    final controller = TextEditingController();
    var invalid = false;

    try {
      return await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setLocalState) {
              return SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    16 + MediaQuery.of(ctx).viewInsets.bottom,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: EaAdaptiveColor.surface(context),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: EaAdaptiveColor.border(context),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            EaI18n.t(
                              context,
                              'Enter your 6-digit verification code to continue.',
                            ),
                            style: EaText.small.copyWith(
                              color: EaAdaptiveColor.secondaryText(context),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: controller,
                            autofocus: true,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              const _GroupedOtpInputFormatter(),
                            ],
                            decoration: InputDecoration(
                              hintText: '123 456',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                          if (invalid) ...[
                            const SizedBox(height: 8),
                            Text(
                              EaI18n.t(context, 'Invalid code.'),
                              style: EaText.small.copyWith(
                                color: Colors.redAccent,
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: EaColor.fore,
                                foregroundColor: EaColor.back,
                              ),
                              onPressed: () {
                                final normalized = controller.text.replaceAll(
                                  RegExp(r'[^0-9]'),
                                  '',
                                );
                                if (normalized.length != 6) {
                                  setLocalState(() => invalid = true);
                                  return;
                                }
                                Navigator.of(ctx).pop(normalized);
                              },
                              child: Text(EaI18n.t(context, 'Verify')),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      controller.dispose();
    }
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
    return 0.0;
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

  Future<_OutsideWeatherSnapshot?> _fetchOutsideTempFromQuery(
    String query,
  ) async {
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
      final temp = double.tryParse(tempRaw);
      if (temp == null) return null;

      String condition = '';
      final weatherDesc = first['weatherDesc'];
      if (weatherDesc is List && weatherDesc.isNotEmpty) {
        final firstDesc = weatherDesc.first;
        if (firstDesc is Map) {
          condition = (firstDesc['value']?.toString() ?? '').trim();
        }
      }

      return _OutsideWeatherSnapshot(
        temp: temp,
        condition: _normalizeWeatherCondition(condition),
      );
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  Future<_OutsideWeatherSnapshot?> _fetchOutsideTempFromCoordinates(
    double lat,
    double lon,
  ) async {
    HttpClient? client;
    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=${lat.toStringAsFixed(5)}'
        '&longitude=${lon.toStringAsFixed(5)}'
        '&current=temperature_2m,weather_code&timezone=auto',
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
      final temp = double.tryParse(tempRaw);
      if (temp == null) return null;

      final weatherCodeRaw = current['weather_code']?.toString() ?? '';
      final weatherCode = int.tryParse(weatherCodeRaw);
      final condition = weatherCode == null
          ? ''
          : _openMeteoWeatherLabel(weatherCode);

      return _OutsideWeatherSnapshot(temp: temp, condition: condition);
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  String _openMeteoWeatherLabel(int code) {
    switch (code) {
      case 0:
        return 'Clear sky';
      case 1:
      case 2:
      case 3:
        return 'Cloudy sky';
      case 45:
      case 48:
        return 'Foggy';
      case 51:
      case 53:
      case 55:
      case 56:
      case 57:
        return 'Light drizzle';
      case 61:
      case 63:
      case 65:
      case 66:
      case 67:
      case 80:
      case 81:
      case 82:
        return 'Rainy';
      case 71:
      case 73:
      case 75:
      case 77:
      case 85:
      case 86:
        return 'Snowy';
      case 95:
      case 96:
      case 99:
        return 'Stormy';
      default:
        return 'Weather';
    }
  }

  String _normalizeWeatherCondition(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';

    final lower = value.toLowerCase();

    if (lower.contains('storm') ||
        lower.contains('thunder') ||
        lower.contains('trov')) {
      return 'Stormy';
    }
    if (lower.contains('snow') ||
        lower.contains('neve') ||
        lower.contains('sleet')) {
      return 'Snowy';
    }
    if (lower.contains('drizzle') || lower.contains('garoa')) {
      return 'Light drizzle';
    }
    if (lower.contains('rain') ||
        lower.contains('chuva') ||
        lower.contains('shower')) {
      return 'Rainy';
    }
    if (lower.contains('fog') ||
        lower.contains('mist') ||
        lower.contains('nebl')) {
      return 'Foggy';
    }
    if (lower.contains('cloud')) {
      return 'Cloudy sky';
    }
    if (lower.contains('clear') ||
        lower.contains('sun') ||
        lower.contains('limpo')) {
      return 'Clear sky';
    }

    return 'Weather';
  }

  Future<_GpsCoordinates?> _readGeolocatorCoordinatesForWeather() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return null;

      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
        ),
      ).timeout(const Duration(seconds: 4));

      return _GpsCoordinates(position.latitude, position.longitude);
    } catch (_) {
      return null;
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

      var lat = gpsLat;
      var lon = gpsLon;
      if (lat == null || lon == null) {
        final gps = await _readGeolocatorCoordinatesForWeather();
        lat = gps?.lat;
        lon = gps?.lon;
      }

      _OutsideWeatherSnapshot? parsed;

      if (lat != null && lon != null) {
        parsed = await _fetchOutsideTempFromCoordinates(lat, lon);
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
            parsed ??= _OutsideWeatherSnapshot(
              temp: _estimateTemperatureFromCoordinates(
                l.latitude,
                l.longitude,
              ),
              condition: '',
            );
          }
        } catch (_) {}
      }

      parsed ??= _OutsideWeatherSnapshot(
        temp: _inferOutsideTemperature(),
        condition: '',
      );

      _outsideTemp = parsed.temp;
      _outsideCondition = parsed.condition;
      _outsideUpdatedAt = DateTime.now();
      final updatedAt = _outsideUpdatedAt;
      await prefs.setDouble(_kOutsideTempCache, _outsideTemp);
      await prefs.setString(_kOutsideConditionCache, _outsideCondition);
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

  Future<Position> _readCurrentPositionWithRetry() async {
    Position? lastKnown;
    try {
      lastKnown = await Geolocator.getLastKnownPosition();
    } catch (_) {}

    Object? lastError;
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0,
      timeLimit: Duration(seconds: 15),
    );

    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) {
        await Future.delayed(const Duration(milliseconds: 700));
      }
      try {
        return await Geolocator.getCurrentPosition(locationSettings: settings);
      } on TimeoutException catch (e) {
        lastError = e;
      } on PlatformException catch (e) {
        lastError = e;
        final message = (e.message ?? '').toLowerCase();
        final retryable =
            message.contains('waited') ||
            message.contains('timeout') ||
            message.contains('time out');
        if (!retryable) break;
      } catch (e) {
        lastError = e;
      }
    }

    if (lastKnown != null) return lastKnown;
    throw lastError ?? Exception('Location unavailable');
  }

  Future<Placemark?> _reverseGeocodeWithRetry(double lat, double lon) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) {
        await Future.delayed(const Duration(milliseconds: 350));
      }
      try {
        final places = await placemarkFromCoordinates(
          lat,
          lon,
        ).timeout(const Duration(seconds: 8));
        if (places.isNotEmpty) return places.first;
      } on TimeoutException {
        continue;
      } on PlatformException {
        continue;
      } catch (_) {
        break;
      }
    }
    return null;
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
                'Enable location service (GPS) to update address.',
              ),
            ),
            action: SnackBarAction(
              label: EaI18n.t(context, 'Open settings'),
              onPressed: Geolocator.openLocationSettings,
            ),
          ),
        );
        return;
      }

      final previousPermission = await Geolocator.checkPermission();
      var permission = previousPermission;
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        messenger?.showSnackBar(
          SnackBar(
            content: Text(
              EaI18n.t(
                context,
                'Location permission denied. Allow access to update.',
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
                'Location permission permanently denied. Allow it in app settings.',
              ),
            ),
            action: SnackBarAction(
              label: EaI18n.t(context, 'Open app'),
              onPressed: Geolocator.openAppSettings,
            ),
          ),
        );
        return;
      }

      if (previousPermission == LocationPermission.denied &&
          (permission == LocationPermission.whileInUse ||
              permission == LocationPermission.always)) {
        // On first Android grant, providers may need a short warm-up.
        await Future.delayed(const Duration(milliseconds: 450));
      }

      final position = await _readCurrentPositionWithRetry();
      final placemark = await _reverseGeocodeWithRetry(
        position.latitude,
        position.longitude,
      );

      final p = placemark ?? Placemark();
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
                    'GPS unavailable on Web. Using the Location field as fallback.',
                  )
                : EaI18n.t(
                    context,
                    'GPS unavailable on this platform. Using the Location field as fallback.',
                  ),
          ),
        ),
      );
    } on TimeoutException {
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
            EaI18n.t(
              context,
              'Could not get GPS right now. Using Location fallback when available.',
            ),
          ),
        ),
      );
    } on PlatformException {
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
            EaI18n.t(
              context,
              'Could not get GPS right now. Using Location fallback when available.',
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
                ? EaI18n.t(context, 'Could not update location: {error}', {
                    'error': '$e',
                  })
                : EaI18n.t(
                    context,
                    'Location updated using typed field fallback.',
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
                    title: EaI18n.t(context, 'Biometrics and passkeys'),
                    subtitle: EaI18n.t(
                      context,
                      'Increase the security to access the app',
                    ),
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
                    subtitle: EaI18n.t(
                      context,
                      'Additional access protection to your account',
                    ),
                    onTap: _openTwoStepVerificationSafely,
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
                    title: EaI18n.t(context, 'Experience'),
                    subtitle: EaI18n.t(context, 'Plan details and benefits'),
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
                    title: EaI18n.t(context, 'Billing'),
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
                    title: EaI18n.t(context, 'Delete application data'),
                    subtitle: EaI18n.t(
                      context,
                      'Permanent local data deletion',
                    ),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: EaAdaptiveColor.surface(context).withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: EaAdaptiveColor.border(context).withValues(alpha: 0.1),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
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
                        child: ElevatedButton.icon(
                          style: EaButtonStyle.gradientFilled(
                            context: context,
                            borderRadius: BorderRadius.circular(12),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                          ),
                          onPressed: () {
                            if (_authBusy) return;
                            _openAuthSheet(signUp: false);
                          },
                          icon: _authBusy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      EaColor.back,
                                    ),
                                  ),
                                )
                              : const Icon(Icons.login_rounded),

                          label: _authBusy
                              ? const SizedBox.shrink()
                              : Text(
                                  EaI18n.t(context, 'Sign in'),
                                  style: EaText.secondary.copyWith(
                                    color: EaColor.back,
                                  ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
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
                    ? EaI18n.t(context, 'Authenticated via {provider}', {
                        'provider': _authProvider ?? 'OAuth',
                      })
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
          Container(
            padding: const EdgeInsets.all(2),
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [EaColor.fore, Color(0xFFB155FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: CircleAvatar(
              radius: 20,
              backgroundColor: EaColor.back,
              backgroundImage: provider,
              onBackgroundImageError: provider == null ? null : (_, _) {},
              child: (provider == null)
                  ? const Icon(
                      Icons.person_outline_rounded,
                      size: 20,
                      color: Colors.white,
                    )
                  : null,
            ),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [EaColor.fore, Color(0xFFB155FF)],
                ),
                shape: BoxShape.circle,
                border: Border.all(color: EaColor.back, width: 1.2),
              ),
              child: const Icon(Icons.edit, size: 9, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            EaColor.fore.withValues(alpha: 0.15),
            const Color(0xFFB155FF).withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: EaColor.fore.withValues(alpha: 0.1),
        ),
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
              value: _outsideCondition.isEmpty
                  ? '${_outsideTemp.toStringAsFixed(1)} °C'
                  : '${_outsideTemp.toStringAsFixed(1)} °C • ${EaI18n.t(context, _outsideCondition)}',
              onTap: _outsideTempRefreshing
                  ? () {}
                  : _refreshOutsideTemperature,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _summaryTile(
              icon: Icons.place_rounded,
              label: EaI18n.t(context, 'Location'),
              value: _fullLocation,
              onTap: () {},
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
    final button = EaGradientButtonFrame(
      borderRadius: BorderRadius.circular(12),
      child: OutlinedButton.icon(
        onPressed: _locationRefreshing ? null : _refreshCurrentLocation,
        icon: const Icon(Icons.air_outlined, size: 16),
        label: Text(
          EaI18n.t(context, 'Update'),
          style: EaText.small.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        style: EaButtonStyle.gradientFilled(
          context: context,
          borderRadius: BorderRadius.circular(12),
        ).copyWith(
          minimumSize: WidgetStateProperty.all(const Size(0, 32)),
          padding: WidgetStateProperty.all(
            const EdgeInsets.symmetric(horizontal: 16),
          ),
        ),
      ),
    );

    return SizedBox(
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

class _OutsideWeatherSnapshot {
  final double temp;
  final String condition;

  const _OutsideWeatherSnapshot({required this.temp, required this.condition});
}

class _GpsCoordinates {
  final double lat;
  final double lon;

  const _GpsCoordinates(this.lat, this.lon);
}

class _AuthSheet extends StatelessWidget {
  final bool signUp;
  final void Function(OAuthProvider) onLogin;
  final VoidCallback onOpenTerms;
  final VoidCallback onOpenPrivacy;

  const _AuthSheet({
    required this.signUp,
    required this.onLogin,
    required this.onOpenTerms,
    required this.onOpenPrivacy,
  });

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
                : EaI18n.t(context, 'Welcome'),
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
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: EaText.small.copyWith(
                color: EaAdaptiveColor.secondaryText(context),
                fontSize: 11,
                height: 1.35,
              ),
              children: [
                TextSpan(
                  text: EaI18n.t(context, 'By continuing you agree to our '),
                ),
                TextSpan(
                  text: EaI18n.t(context, 'Terms of Use'),
                  style: EaText.small.copyWith(
                    color: EaColor.fore,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                  ),
                  recognizer: TapGestureRecognizer()..onTap = onOpenTerms,
                ),
                TextSpan(text: EaI18n.t(context, ' and ')),
                TextSpan(
                  text: EaI18n.t(context, 'Privacy Policy'),
                  style: EaText.small.copyWith(
                    color: EaColor.fore,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                  ),
                  recognizer: TapGestureRecognizer()..onTap = onOpenPrivacy,
                ),
                const TextSpan(text: '.'),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _GroupedOtpInputFormatter extends TextInputFormatter {
  const _GroupedOtpInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final capped = digits.length > 6 ? digits.substring(0, 6) : digits;
    final grouped = capped.length <= 3
        ? capped
        : '${capped.substring(0, 3)} ${capped.substring(3)}';

    return TextEditingValue(
      text: grouped,
      selection: TextSelection.collapsed(offset: grouped.length),
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
    child: Image.asset(
      'assets/images/google.png',
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => CustomPaint(painter: _GooglePainter()),
    ),
  );
}

class _GooglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const blue = Color(0xFF4285F4);
    const red = Color(0xFFEA4335);
    const yellow = Color(0xFFFBBC05);
    const green = Color(0xFF34A853);

    final stroke = size.width * 0.18;
    final radius = (size.width - stroke) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);

    double deg(double v) => v * pi / 180.0;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;

    paint.color = red;
    canvas.drawArc(rect, deg(-40), deg(85), false, paint);

    paint.color = yellow;
    canvas.drawArc(rect, deg(45), deg(90), false, paint);

    paint.color = green;
    canvas.drawArc(rect, deg(135), deg(90), false, paint);

    paint.color = blue;
    canvas.drawArc(rect, deg(225), deg(95), false, paint);

    final barHeight = stroke * 0.7;
    final barTop = center.dy - barHeight / 2;
    final barLeft = center.dx + radius * 0.05;
    final barRight = center.dx + radius * 1.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(barLeft, barTop, barRight, barTop + barHeight),
        Radius.circular(barHeight / 2),
      ),
      Paint()..color = blue,
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
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(
                EaI18n.t(context, 'Save changes'),
                style: EaText.small.copyWith(color: EaColor.back),
              ),
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

class PasswordPasskeysPage extends StatefulWidget {
  const PasswordPasskeysPage({super.key});

  @override
  State<PasswordPasskeysPage> createState() => _PasswordPasskeysPageState();
}

class _PasswordPasskeysPageState extends State<PasswordPasskeysPage> {
  static const _kFingerprintEnabled = 'account.security.fingerprint';
  bool _fingerprintEnabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _fingerprintEnabled = prefs.getBool(_kFingerprintEnabled) ?? false;
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                EaI18n.t(
                                  context,
                                  'Enable device biometrics unlock',
                                ),
                                style: EaText.secondary.copyWith(
                                  color: EaAdaptiveColor.bodyText(context),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                EaI18n.t(
                                  context,
                                  'Use fingerprint or face recognition to unlock the app faster.',
                                ),
                                style: EaText.small.copyWith(
                                  color: EaAdaptiveColor.secondaryText(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Switch.adaptive(
                          activeThumbColor: EaColor.fore,
                          value: _fingerprintEnabled,
                          onChanged: _setFingerprint,
                        ),
                      ],
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
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 14),
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
  final _otpController = TextEditingController();
  bool _app = false;
  bool _verified = false;
  String _manualKey = '';
  String _otpauthUri = '';
  bool _busy = false;
  _TwoFactorSetupMode _setupMode = _TwoFactorSetupMode.qrCode;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final startup = await AppSecurityService.instance
        .readStartupSecurityState();
    _app = startup.authenticatorEnabled;
    _verified = startup.authenticatorVerified;
    _manualKey = startup.manualEntryKey ?? '';
    _otpauthUri = startup.otpauthUri?.toString() ?? '';
    if (mounted) setState(() {});
  }

  Future<void> _toggleAuthenticator(bool enabled) async {
    if (enabled) {
      await _generateSecret();
      return;
    }

    await AppSecurityService.instance.disableAuthenticator(removeSecret: true);
    await _load();
  }

  Future<void> _generateSecret() async {
    setState(() => _busy = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final email = (prefs.getString('account.auth.email') ?? '').trim();
      final name = (prefs.getString('account.auth.name') ?? '').trim();
      final accountLabel = email.isNotEmpty
          ? email
          : (name.isNotEmpty ? name : 'user@easync.local');

      final setup = await AppSecurityService.instance
          .createOrRotateAuthenticator(accountLabel: accountLabel);

      _app = true;
      _verified = false;
      _manualKey = setup.manualEntryKey;
      _otpauthUri = setup.otpauthUri.toString();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyOtpCode() async {
    final normalizedOtp = _otpController.text.replaceAll(RegExp(r'\D'), '');
    final ok = await AppSecurityService.instance.verifyAuthenticatorCode(
      normalizedOtp,
    );
    if (!mounted) return;

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(EaI18n.t(context, 'Invalid code. Try again.'))),
      );
      return;
    }

    _otpController.clear();
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          EaI18n.t(context, 'Authenticator app activated successfully.'),
        ),
      ),
    );
  }

  Future<void> _confirmQrSetup() async {
    final ok = await AppSecurityService.instance
        .confirmAuthenticatorSetupViaQr();
    if (!mounted) return;

    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            EaI18n.t(
              context,
              'Could not confirm QR setup. Try Setup key mode.',
            ),
          ),
        ),
      );
      return;
    }

    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          EaI18n.t(context, 'QR setup confirmed. 2FA is now active.'),
        ),
      ),
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(EaI18n.t(context, 'Authenticator app')),
                              const SizedBox(height: 2),
                              Text(
                                _verified
                                    ? EaI18n.t(context, 'Enabled')
                                    : EaI18n.t(context, 'Disabled'),
                                style: EaText.small.copyWith(
                                  color: EaAdaptiveColor.secondaryText(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Switch.adaptive(
                          activeThumbColor: EaColor.fore,
                          value: _app,
                          onChanged: _busy ? null : _toggleAuthenticator,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: EaAdaptiveColor.field(context),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: EaAdaptiveColor.border(context),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _verified
                                ? Icons.verified_user_rounded
                                : (_app
                                      ? Icons.pending_actions_rounded
                                      : Icons.radio_button_unchecked_rounded),
                            color: _verified
                                ? Colors.green
                                : (_app
                                      ? EaColor.fore
                                      : EaAdaptiveColor.secondaryText(context)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  EaI18n.t(context, 'Status'),
                                  style: EaText.small.copyWith(
                                    color: EaAdaptiveColor.secondaryText(
                                      context,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  EaI18n.t(
                                    context,
                                    !_app
                                        ? 'Inactive'
                                        : (_verified
                                              ? 'Active and protected'
                                              : 'Pending setup'),
                                  ),
                                  style: EaText.secondary.copyWith(
                                    color: EaAdaptiveColor.bodyText(context),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_app && !_verified)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 8, 18, 22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SegmentedButton<_TwoFactorSetupMode>(
                            segments: [
                              ButtonSegment<_TwoFactorSetupMode>(
                                value: _TwoFactorSetupMode.qrCode,
                                icon: const Icon(Icons.qr_code_2_rounded),
                                label: Text(EaI18n.t(context, 'QR-Code')),
                              ),
                              ButtonSegment<_TwoFactorSetupMode>(
                                value: _TwoFactorSetupMode.setupKey,
                                icon: const Icon(Icons.vpn_key_outlined),
                                label: Text(EaI18n.t(context, 'Setup Key')),
                              ),
                            ],
                            selected: {_setupMode},
                            onSelectionChanged: (v) {
                              setState(() => _setupMode = v.first);
                            },
                          ),
                          const SizedBox(height: 14),
                          if (_setupMode == _TwoFactorSetupMode.qrCode) ...[
                            Center(
                              child: Container(
                                width: 250,
                                height: 250,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: EaAdaptiveColor.border(context),
                                  ),
                                ),
                                child: BarcodeWidget(
                                  data: _otpauthUri,
                                  barcode: Barcode.qrCode(),
                                  color: Colors.black,
                                  backgroundColor: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: EaColor.fore,
                                  foregroundColor: EaColor.back,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                                onPressed: _confirmQrSetup,
                                icon: const Icon(Icons.qr_code_scanner_rounded),
                                label: Text(
                                  EaI18n.t(
                                    context,
                                    'I scanned the QR code and want to continue',
                                  ),
                                ),
                              ),
                            ),
                          ] else ...[
                            Text(
                              EaI18n.t(context, 'Manual setup key'),
                              style: EaText.small.copyWith(
                                color: EaAdaptiveColor.secondaryText(context),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              width: double.infinity,
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: EaAdaptiveColor.field(context),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: EaAdaptiveColor.border(context),
                                ),
                              ),
                              child: SelectableText(
                                _manualKey,
                                textAlign: TextAlign.center,
                                style: EaText.secondary.copyWith(
                                  color: EaAdaptiveColor.bodyText(context),
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: _manualKey),
                                  );
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        EaI18n.t(
                                          context,
                                          'Setup key copied to clipboard.',
                                        ),
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.content_copy_rounded),
                                label: Text(
                                  EaI18n.t(context, 'Copy setup key'),
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              controller: _otpController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                _GroupedOtpInputFormatter(),
                              ],
                              decoration: InputDecoration(
                                labelText: EaI18n.t(
                                  context,
                                  'Enter 6-digit code',
                                ),
                                hintText: '123 456',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: EaColor.fore,
                                  foregroundColor: EaColor.back,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                ),
                                onPressed: _verifyOtpCode,
                                icon: const Icon(Icons.verified_user_outlined),
                                label: Text(EaI18n.t(context, 'Verify')),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  if (_app && _verified)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: EaAdaptiveColor.field(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: EaAdaptiveColor.border(context),
                          ),
                        ),
                        child: Text(
                          EaI18n.t(
                            context,
                            '2FA is active. Disable and enable again to generate a new setup key.',
                          ),
                          style: EaText.small.copyWith(
                            color: EaAdaptiveColor.secondaryText(context),
                            height: 1.35,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          EaFadeSlideIn(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: EaAdaptiveColor.surface(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: EaAdaptiveColor.border(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    EaI18n.t(context, 'How to configure 2FA'),
                    style: EaText.secondary.copyWith(
                      color: EaAdaptiveColor.bodyText(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _tutorialStep(
                    icon: Icons.toggle_on_rounded,
                    text: EaI18n.t(context, '1. Enable Authenticator app.'),
                  ),
                  const SizedBox(height: 6),
                  _tutorialStep(
                    icon: Icons.swap_horiz_rounded,
                    text: EaI18n.t(context, '2. Choose QR-Code or Setup Key.'),
                  ),
                  const SizedBox(height: 6),
                  _tutorialStep(
                    icon: Icons.rule_folder_outlined,
                    text: EaI18n.t(
                      context,
                      '3. Setup Key mode requires the 6-digit code. QR-Code mode does not require code on this screen.',
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

  Widget _tutorialStep({required IconData icon, required String text}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: EaColor.fore),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: EaText.small.copyWith(
              color: EaAdaptiveColor.secondaryText(context),
            ),
          ),
        ),
      ],
    );
  }
}

enum _TwoFactorSetupMode { qrCode, setupKey }

class TrustedDevicesPage extends StatefulWidget {
  const TrustedDevicesPage({super.key});

  @override
  State<TrustedDevicesPage> createState() => _TrustedDevicesPageState();
}

class _TrustedPeerNode {
  final String instanceId;
  String displayName;
  String platform;
  String photo;
  String address;
  DateTime lastSeen;

  _TrustedPeerNode({
    required this.instanceId,
    required this.displayName,
    required this.platform,
    required this.photo,
    required this.address,
    required this.lastSeen,
  });
}

class _HostTransferRequest {
  final String requestId;
  final String requesterId;
  String requesterName;
  final DateTime createdAt;
  final Set<String> approvedBy = <String>{};
  final Set<String> rejectedBy = <String>{};
  bool resolved = false;
  bool accepted = false;
  String resolutionMessage = '';

  _HostTransferRequest({
    required this.requestId,
    required this.requesterId,
    required this.requesterName,
    required this.createdAt,
  });

  bool hasVoteFrom(String instanceId) {
    return approvedBy.contains(instanceId) || rejectedBy.contains(instanceId);
  }
}

class _NetDiagItem {
  final String label;
  final bool ok;
  final String detail;

  const _NetDiagItem({
    required this.label,
    required this.ok,
    required this.detail,
  });
}

class _TrustedDevicesPageState extends State<TrustedDevicesPage> {
  static const _kTrustedDevices = 'account.security.trusted_devices';
  static const _kTrustedHostId = 'account.security.trusted.host_id';
  static const _kTrustedInstanceId = 'account.security.trusted.instance_id';
  static const _kTrustedPermissions =
      'account.security.trusted.permissions_json';
  static const _kRemoteCanControl = 'security.remote.can_control';
  static const _kRemoteCanModify = 'security.remote.can_modify';
  static const _udpPort = 48321;
  static const _packetProto = 'easync_trusted_v1';
  static const _hostStaleSeconds = 9;

  RawDatagramSocket? _socket;
  Timer? _helloTimer;
  Timer? _cleanupTimer;

  String _instanceId = '';
  String _hostId = '';
  String _displayName = 'EaSync Device';
  String _profilePhoto = '';
  bool _loading = true;
  bool _canControl = true;
  bool _canModify = true;

  final Map<String, _TrustedPeerNode> _peers = <String, _TrustedPeerNode>{};
  final Map<String, Map<String, bool>> _policies =
      <String, Map<String, bool>>{};
  final Map<String, String> _instanceNames = <String, String>{};
  final Map<String, int> _peerDiscoveryOrder = <String, int>{};
  int _nextPeerOrder = 0;
  final Map<String, _HostTransferRequest> _transferRequests =
      <String, _HostTransferRequest>{};

  String? _activeTransferRequestId;

  bool get _isHost => _hostId.isNotEmpty && _hostId == _instanceId;

  Set<String> get _activeSessionIds => <String>{_instanceId, ..._peers.keys};

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _helloTimer?.cancel();
    _cleanupTimer?.cancel();
    _socket?.close();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();

    _displayName =
        (prefs.getString('account.auth.name') ?? '').trim().isNotEmpty
        ? (prefs.getString('account.auth.name') ?? '').trim()
        : '${Platform.operatingSystem.toUpperCase()} • EaSync';

    _profilePhoto = (prefs.getString('account.auth.photo') ?? '').trim();
    if (_profilePhoto.isEmpty) {
      final saved = await OAuthService.instance.getSavedProfile();
      _profilePhoto = (saved?.avatarUrl ?? '').trim();
    }

    var existingId = (prefs.getString(_kTrustedInstanceId) ?? '').trim();
    if (existingId.isEmpty) {
      final n = Random.secure().nextInt(0x7fffffff).toRadixString(16);
      existingId =
          '${Platform.operatingSystem}-${DateTime.now().millisecondsSinceEpoch}-$n';
      await prefs.setString(_kTrustedInstanceId, existingId);
    }
    _instanceId = existingId;
    _instanceNames[_instanceId] = _displayName;

    _hostId = (prefs.getString(_kTrustedHostId) ?? '').trim();
    if (_hostId.isEmpty) {
      _hostId = _instanceId;
      await prefs.setString(_kTrustedHostId, _hostId);
    }

    final policyRaw = prefs.getString(_kTrustedPermissions);
    if (policyRaw != null && policyRaw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(policyRaw);
        if (decoded is Map) {
          for (final e in decoded.entries) {
            final key = e.key.toString();
            final value = e.value;
            if (value is Map) {
              _policies[key] = {
                'canControl': (value['canControl'] ?? true) == true,
                'canModify': (value['canModify'] ?? true) == true,
              };
            }
          }
        }
      } catch (_) {}
    }

    _canControl = prefs.getBool(_kRemoteCanControl) ?? true;
    _canModify = prefs.getBool(_kRemoteCanModify) ?? true;

    final pending = TrustedPresenceService.instance
        .pendingHostTransferRequests();
    for (final notice in pending) {
      _transferRequests.putIfAbsent(
        notice.requestId,
        () => _HostTransferRequest(
          requestId: notice.requestId,
          requesterId: notice.requesterId,
          requesterName: notice.requesterName.trim().isEmpty
              ? _displayNameForInstance(notice.requesterId)
              : notice.requesterName.trim(),
          createdAt: DateTime.now(),
        ),
      );
    }

    await _saveTrustedLegacyList();
    if (!mounted) return;
    setState(() => _loading = false);

    if (!kIsWeb) {
      await _startDiscovery();
    }
  }

  Future<void> _saveTrustedLegacyList() async {
    final prefs = await SharedPreferences.getInstance();
    final peers = _sortedPeers;
    final list = <String>[
      '${Platform.operatingSystem.toUpperCase()} • This device',
    ];
    for (final p in peers) {
      list.add('${p.displayName} (${p.address})');
    }
    await prefs.setStringList(_kTrustedDevices, list);
  }

  Future<void> _savePolicies() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTrustedPermissions, jsonEncode(_policies));
  }

  List<_TrustedPeerNode> get _sortedPeers {
    final peers = _peers.values.toList();
    peers.sort((a, b) {
      final ao = _peerDiscoveryOrder[a.instanceId] ?? 1 << 30;
      final bo = _peerDiscoveryOrder[b.instanceId] ?? 1 << 30;
      if (ao != bo) return ao.compareTo(bo);
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return peers;
  }

  String _displayNameForInstance(String instanceId) {
    if (instanceId == _instanceId) {
      return '${Platform.operatingSystem.toUpperCase()} • ${EaI18n.t(context, 'This device')}';
    }

    final peerName = (_peers[instanceId]?.displayName ?? '').trim();
    if (peerName.isNotEmpty) return peerName;

    final cachedName = (_instanceNames[instanceId] ?? '').trim();
    if (cachedName.isNotEmpty) return cachedName;

    final normalized = instanceId.trim();
    if (normalized.isEmpty) return EaI18n.t(context, 'Unknown session');

    final platform = _platformFromInstanceId(instanceId);
    return platform.isNotEmpty
        ? platform
        : EaI18n.t(context, 'Unknown session');
  }

  String _platformFromInstanceId(String instanceId) {
    final normalized = instanceId.trim();
    if (normalized.isEmpty) return '';

    final prefix = normalized.split('-').first.toLowerCase().trim();
    switch (prefix) {
      case 'android':
        return 'Android';
      case 'ios':
        return 'iOS';
      case 'linux':
        return 'Linux';
      case 'macos':
        return 'macOS';
      case 'windows':
        return 'Windows';
      case 'web':
        return 'Web';
      default:
        return '';
    }
  }

  Future<void> _requestHostTransfer() async {
    if (_isHost) return;

    if (_activeTransferRequestId != null) {
      final active = _transferRequests[_activeTransferRequestId!];
      if (active != null && !active.resolved) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              EaI18n.t(
                context,
                'There is already a pending host transfer request.',
              ),
            ),
          ),
        );
        return;
      }
    }

    final requestId =
        '${DateTime.now().millisecondsSinceEpoch}-${Random.secure().nextInt(0x7fffffff).toRadixString(16)}';

    final req = _HostTransferRequest(
      requestId: requestId,
      requesterId: _instanceId,
      requesterName: _displayName,
      createdAt: DateTime.now(),
    );

    _transferRequests[requestId] = req;
    _activeTransferRequestId = requestId;
    if (mounted) setState(() {});

    final packet = {
      'proto': _packetProto,
      'type': 'host_transfer_request',
      'requestId': req.requestId,
      'requesterId': req.requesterId,
      'requesterName': req.requesterName,
      'currentHostId': _hostId,
      'atMs': req.createdAt.millisecondsSinceEpoch,
    };

    _broadcastPacket(packet);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          EaI18n.t(
            context,
            'Host transfer request sent. All online sessions must approve.',
          ),
        ),
      ),
    );
  }

  void _broadcastPacket(Map<String, dynamic> packet) {
    final socket = _socket;
    if (socket == null) return;

    final data = utf8.encode(jsonEncode(packet));
    try {
      socket.send(data, InternetAddress('255.255.255.255'), _udpPort);
      if (_hostId.isNotEmpty && _hostId != _instanceId) {
        final hostNode = _peers[_hostId];
        if (hostNode != null) {
          socket.send(data, InternetAddress(hostNode.address), _udpPort);
        }
      }
    } catch (_) {}
  }

  void _requestTransferStateSync() {
    _broadcastPacket({
      'proto': _packetProto,
      'type': 'host_transfer_sync_request',
      'requesterId': _instanceId,
      'atMs': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _sendTransferStateToAddress(_HostTransferRequest req, String address) {
    final socket = _socket;
    if (socket == null) return;
    final packet = {
      'proto': _packetProto,
      'type': 'host_transfer_state',
      'requestId': req.requestId,
      'requesterId': req.requesterId,
      'requesterName': req.requesterName,
      'approvedBy': req.approvedBy.toList(growable: false),
      'rejectedBy': req.rejectedBy.toList(growable: false),
      'resolved': req.resolved,
      'accepted': req.accepted,
      'message': req.resolutionMessage,
      'hostId': _hostId,
      'atMs': DateTime.now().millisecondsSinceEpoch,
    };
    final data = utf8.encode(jsonEncode(packet));
    try {
      socket.send(data, InternetAddress(address), _udpPort);
    } catch (_) {}
  }

  void _broadcastTransferState(_HostTransferRequest req) {
    _broadcastPacket({
      'proto': _packetProto,
      'type': 'host_transfer_state',
      'requestId': req.requestId,
      'requesterId': req.requesterId,
      'requesterName': req.requesterName,
      'approvedBy': req.approvedBy.toList(growable: false),
      'rejectedBy': req.rejectedBy.toList(growable: false),
      'resolved': req.resolved,
      'accepted': req.accepted,
      'message': req.resolutionMessage,
      'hostId': _hostId,
      'atMs': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _sendAllTransferStatesToAddress(String address) {
    for (final req in _transferRequests.values) {
      if (req.resolved) continue;
      _sendTransferStateToAddress(req, address);
    }
  }

  Future<void> _submitTransferVote(
    _HostTransferRequest req,
    bool approve,
  ) async {
    if (req.resolved || req.requesterId == _instanceId) return;
    if (req.hasVoteFrom(_instanceId)) return;

    if (approve) {
      req.approvedBy.add(_instanceId);
      req.rejectedBy.remove(_instanceId);
    } else {
      req.rejectedBy.add(_instanceId);
      req.approvedBy.remove(_instanceId);
    }

    final packet = {
      'proto': _packetProto,
      'type': 'host_transfer_vote',
      'requestId': req.requestId,
      'requesterId': req.requesterId,
      'voterId': _instanceId,
      'approve': approve,
      'atMs': DateTime.now().millisecondsSinceEpoch,
    };
    _broadcastPacket(packet);

    if (_isHost) {
      _broadcastTransferState(req);
    }

    if (_isHost) {
      _evaluateTransferRequest(req);
    }
    if (mounted) setState(() {});
  }

  Future<void> _resolveTransferRequest(
    _HostTransferRequest req, {
    required bool accepted,
    required String message,
  }) async {
    if (req.resolved) return;

    req.resolved = true;
    req.accepted = accepted;
    req.resolutionMessage = message;

    if (accepted) {
      _hostId = req.requesterId;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kTrustedHostId, _hostId);

      if (_hostId == _instanceId) {
        _broadcastHello();
        for (final peer in _peers.values) {
          _sendPolicyToPeer(peer);
        }
      }
    }

    if (_activeTransferRequestId == req.requestId) {
      _activeTransferRequestId = null;
    }

    final resultPacket = {
      'proto': _packetProto,
      'type': 'host_transfer_result',
      'requestId': req.requestId,
      'requesterId': req.requesterId,
      'accepted': accepted,
      'newHostId': accepted ? req.requesterId : _hostId,
      'message': message,
      'atMs': DateTime.now().millisecondsSinceEpoch,
    };
    _broadcastTransferState(req);
    _broadcastPacket(resultPacket);
    if (mounted) setState(() {});
  }

  void _evaluateTransferRequest(_HostTransferRequest req) {
    if (!_isHost || req.resolved) return;

    if (req.rejectedBy.isNotEmpty) {
      _resolveTransferRequest(
        req,
        accepted: false,
        message: EaI18n.t(
          context,
          'Transfer canceled because one session rejected.',
        ),
      );
      return;
    }

    final requiredApprovals = _activeSessionIds
        .where((id) => id != req.requesterId)
        .toSet();

    final approvedAll = requiredApprovals.every(req.approvedBy.contains);
    if (!approvedAll) return;

    _resolveTransferRequest(
      req,
      accepted: true,
      message: EaI18n.t(context, 'Transfer approved by all online sessions.'),
    );
  }

  Future<void> _startDiscovery() async {
    try {
      RawDatagramSocket socket;
      try {
        socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          _udpPort,
          reuseAddress: true,
          reusePort: true,
        );
      } catch (_) {
        socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          _udpPort,
          reuseAddress: true,
        );
      }
      socket.broadcastEnabled = true;
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        Datagram? d;
        while ((d = socket.receive()) != null) {
          _handleDatagram(d!);
        }
      });
      _socket = socket;

      _broadcastHello();
      Future<void>.delayed(const Duration(milliseconds: 420), () {
        _requestTransferStateSync();
      });
      _helloTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        _broadcastHello();
      });
      _cleanupTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        _cleanupPeers();
      });
    } catch (_) {
      // Discovery is best-effort; page still works in local-only mode.
    }
  }

  void _cleanupPeers() {
    final now = DateTime.now();
    final expired = <String>[];
    for (final e in _peers.entries) {
      if (now.difference(e.value.lastSeen).inSeconds > 18) {
        expired.add(e.key);
      }
    }
    if (expired.isEmpty) return;
    for (final id in expired) {
      _peers.remove(id);
      _peerDiscoveryOrder.remove(id);
    }
    _saveTrustedLegacyList();
    if (mounted) setState(() {});
  }

  bool _isHostPeerFresh(String hostId) {
    final host = _peers[hostId];
    if (host == null) return false;
    return DateTime.now().difference(host.lastSeen).inSeconds <=
        _hostStaleSeconds;
  }

  bool _shouldAcceptHelloHostClaim({
    required String peerId,
    required String announcedHost,
  }) {
    if (_isHost) return false;
    if (announcedHost.isEmpty) return false;
    if (announcedHost != peerId) return false;
    if (_hostId == announcedHost) return false;
    if (_hostId.isEmpty) return true;

    // Keep the host stable while current host is still alive.
    return !_isHostPeerFresh(_hostId);
  }

  void _broadcastHello() {
    final socket = _socket;
    if (socket == null) return;

    final packet = {
      'proto': _packetProto,
      'type': 'hello',
      'instanceId': _instanceId,
      'displayName': _displayName,
      'platform': Platform.operatingSystem,
      'photo': _profilePhoto.startsWith('http') ? _profilePhoto : '',
      'hostId': _hostId,
      'atMs': DateTime.now().millisecondsSinceEpoch,
    };

    final data = utf8.encode(jsonEncode(packet));
    socket.send(data, InternetAddress('255.255.255.255'), _udpPort);
  }

  void _sendPolicyToPeer(_TrustedPeerNode peer) {
    final socket = _socket;
    if (socket == null || !_isHost) return;

    final p =
        _policies[peer.instanceId] ?? {'canControl': true, 'canModify': true};
    final packet = {
      'proto': _packetProto,
      'type': 'policy',
      'hostId': _instanceId,
      'targetId': peer.instanceId,
      'canControl': p['canControl'] == true,
      'canModify': p['canModify'] == true,
      'atMs': DateTime.now().millisecondsSinceEpoch,
    };
    final data = utf8.encode(jsonEncode(packet));
    try {
      socket.send(data, InternetAddress(peer.address), _udpPort);
      socket.send(data, InternetAddress('255.255.255.255'), _udpPort);
    } catch (_) {}
  }

  Future<void> _applyIncomingPolicy(bool canControl, bool canModify) async {
    _canControl = canControl;
    _canModify = canModify;
    await EaAppSettings.instance.applyRemotePermissions(
      canControl: canControl,
      canModify: canModify,
    );
    if (!mounted) return;
    setState(() {});
  }

  void _handleDatagram(Datagram datagram) {
    Map<String, dynamic>? packet;
    try {
      final text = utf8.decode(datagram.data, allowMalformed: true);
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        packet = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      return;
    }
    if (packet == null || packet['proto'] != _packetProto) return;

    final type = (packet['type'] ?? '').toString();
    if (type == 'hello') {
      final peerId = (packet['instanceId'] ?? '').toString().trim();
      if (peerId.isEmpty || peerId == _instanceId) return;

      final display = (packet['displayName'] ?? '').toString().trim();
      final platformRaw = (packet['platform'] ?? '').toString().trim();
      final platform = platformRaw.isEmpty
          ? _platformFromInstanceId(peerId)
          : platformRaw.toLowerCase();
      final photo = (packet['photo'] ?? '').toString().trim();
      if (display.isNotEmpty) {
        _instanceNames[peerId] = display;
      }
      final node = _peers.putIfAbsent(
        peerId,
        () => _TrustedPeerNode(
          instanceId: peerId,
          displayName: display.isEmpty ? 'EaSync Node' : display,
          platform: platform,
          photo: photo,
          address: datagram.address.address,
          lastSeen: DateTime.now(),
        ),
      );
      _peerDiscoveryOrder.putIfAbsent(peerId, () => _nextPeerOrder++);
      node.displayName = display.isEmpty ? node.displayName : display;
      node.platform = platform.isEmpty ? node.platform : platform;
      node.photo = photo.isEmpty ? node.photo : photo;
      node.address = datagram.address.address;
      node.lastSeen = DateTime.now();

      final announcedHost = (packet['hostId'] ?? '').toString().trim();
      if (_shouldAcceptHelloHostClaim(
        peerId: peerId,
        announcedHost: announcedHost,
      )) {
        _hostId = announcedHost;
        SharedPreferences.getInstance().then((prefs) {
          prefs.setString(_kTrustedHostId, _hostId);
        });
      }

      _saveTrustedLegacyList();

      if (_isHost) {
        _sendPolicyToPeer(node);
        _sendAllTransferStatesToAddress(node.address);
      }
      if (mounted) setState(() {});
      return;
    }

    if (type == 'policy') {
      final hostId = (packet['hostId'] ?? '').toString().trim();
      final target = (packet['targetId'] ?? '').toString().trim();
      if (target != _instanceId || hostId.isEmpty || hostId == _instanceId) {
        return;
      }
      _hostId = hostId;
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString(_kTrustedHostId, _hostId);
      });
      final canControl = packet['canControl'] == true;
      final canModify = packet['canModify'] == true;
      _applyIncomingPolicy(canControl, canModify);
      return;
    }

    if (type == 'host_transfer_request') {
      final requestId = (packet['requestId'] ?? '').toString().trim();
      final requesterId = (packet['requesterId'] ?? '').toString().trim();
      if (requestId.isEmpty ||
          requesterId.isEmpty ||
          requesterId == _instanceId) {
        return;
      }

      final requesterName = (packet['requesterName'] ?? '').toString().trim();
      if (requesterName.isNotEmpty) {
        _instanceNames[requesterId] = requesterName;
      }
      final req = _transferRequests.putIfAbsent(
        requestId,
        () => _HostTransferRequest(
          requestId: requestId,
          requesterId: requesterId,
          requesterName: requesterName.isEmpty
              ? EaI18n.t(context, 'Unknown session')
              : requesterName,
          createdAt: DateTime.now(),
        ),
      );

      if (requesterName.isNotEmpty && req.requesterName != requesterName) {
        req.requesterName = requesterName;
      }

      if (_isHost) {
        _broadcastTransferState(req);
      }

      if (mounted) setState(() {});
      return;
    }

    if (type == 'host_transfer_sync_request') {
      if (!_isHost) return;
      final requesterId = (packet['requesterId'] ?? '').toString().trim();
      if (requesterId.isEmpty || requesterId == _instanceId) return;
      _sendAllTransferStatesToAddress(datagram.address.address);
      return;
    }

    if (type == 'host_transfer_state') {
      final requestId = (packet['requestId'] ?? '').toString().trim();
      final requesterId = (packet['requesterId'] ?? '').toString().trim();
      if (requestId.isEmpty || requesterId.isEmpty) return;

      final requesterName = (packet['requesterName'] ?? '').toString().trim();
      final req = _transferRequests.putIfAbsent(
        requestId,
        () => _HostTransferRequest(
          requestId: requestId,
          requesterId: requesterId,
          requesterName: requesterName.isEmpty
              ? _displayNameForInstance(requesterId)
              : requesterName,
          createdAt: DateTime.now(),
        ),
      );

      if (requesterName.isNotEmpty) {
        req.requesterName = requesterName;
        _instanceNames[requesterId] = requesterName;
      }

      final approvedByRaw = packet['approvedBy'];
      if (approvedByRaw is List) {
        req.approvedBy
          ..clear()
          ..addAll(
            approvedByRaw
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty),
          );
      }

      final rejectedByRaw = packet['rejectedBy'];
      if (rejectedByRaw is List) {
        req.rejectedBy
          ..clear()
          ..addAll(
            rejectedByRaw
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty),
          );
      }

      req.resolved = packet['resolved'] == true;
      req.accepted = packet['accepted'] == true;
      req.resolutionMessage = (packet['message'] ?? '').toString().trim();

      final hostId = (packet['hostId'] ?? '').toString().trim();
      if (hostId.isNotEmpty && _hostId != hostId) {
        _hostId = hostId;
        SharedPreferences.getInstance().then((prefs) {
          prefs.setString(_kTrustedHostId, _hostId);
        });
      }

      if (_activeTransferRequestId == requestId && req.resolved) {
        _activeTransferRequestId = null;
      }

      if (mounted) setState(() {});
      return;
    }

    if (type == 'host_transfer_vote') {
      final requestId = (packet['requestId'] ?? '').toString().trim();
      final voterId = (packet['voterId'] ?? '').toString().trim();
      final approve = packet['approve'] == true;
      final req = _transferRequests[requestId];
      if (req == null || req.resolved || voterId.isEmpty) return;

      if (approve) {
        req.approvedBy.add(voterId);
        req.rejectedBy.remove(voterId);
      } else {
        req.rejectedBy.add(voterId);
        req.approvedBy.remove(voterId);
      }

      if (_isHost) {
        _broadcastTransferState(req);
        _evaluateTransferRequest(req);
      }
      if (mounted) setState(() {});
      return;
    }

    if (type == 'host_transfer_result') {
      final requestId = (packet['requestId'] ?? '').toString().trim();
      if (requestId.isEmpty) return;

      final req = _transferRequests[requestId];
      final accepted = packet['accepted'] == true;
      final newHostId = (packet['newHostId'] ?? '').toString().trim();
      final message = (packet['message'] ?? '').toString().trim();

      if (req != null) {
        req.resolved = true;
        req.accepted = accepted;
        req.resolutionMessage = message;
      }

      if (newHostId.isNotEmpty) {
        _hostId = newHostId;
        SharedPreferences.getInstance().then((prefs) {
          prefs.setString(_kTrustedHostId, _hostId);
        });
      }

      if (_activeTransferRequestId == requestId) {
        _activeTransferRequestId = null;
      }

      if (mounted) setState(() {});
    }
  }

  Future<void> _setPeerPolicy(
    String peerId, {
    bool? canControl,
    bool? canModify,
  }) async {
    final current =
        _policies[peerId] ?? {'canControl': true, 'canModify': true};
    _policies[peerId] = {
      'canControl': canControl ?? current['canControl'] == true,
      'canModify': canModify ?? current['canModify'] == true,
    };
    await _savePolicies();
    final peer = _peers[peerId];
    if (peer != null) {
      _sendPolicyToPeer(peer);
    }
    if (mounted) setState(() {});
  }

  Widget _flagChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: EaColor.fore.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(text, style: EaText.small.copyWith(color: EaColor.fore)),
    );
  }

  ImageProvider? _avatarProvider(String raw, {required bool isLocal}) {
    final photo = raw.trim();
    if (photo.isEmpty) return null;
    if (photo.startsWith('http')) return NetworkImage(photo);
    if (isLocal) return FileImage(File(photo));
    return null;
  }

  String _shortId(String id) => id.substring(0, min(10, id.length));

  Widget _sessionTile({
    required String instanceId,
    required String displayName,
    required String platform,
    required String photo,
    String? address,
  }) {
    final isYou = instanceId == _instanceId;
    final isHost = instanceId == _hostId;
    final avatar = _avatarProvider(photo, isLocal: isYou);
    final subtitlePlatform = platform.trim().isEmpty
        ? _platformFromInstanceId(instanceId)
        : platform;

    final p = _policies[instanceId] ?? {'canControl': true, 'canModify': true};

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: EaAdaptiveColor.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EaAdaptiveColor.border(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: EaColor.fore.withValues(alpha: 0.14),
                  backgroundImage: avatar,
                  child: avatar == null
                      ? Icon(
                          isYou
                              ? Icons.person_outline_rounded
                              : Icons.devices_other_outlined,
                          size: 18,
                          color: EaColor.fore,
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: EaText.secondary.copyWith(
                          color: EaAdaptiveColor.bodyText(context),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$subtitlePlatform • ID: ${_shortId(instanceId)}',
                        style: EaText.small.copyWith(
                          color: EaAdaptiveColor.secondaryText(context),
                        ),
                      ),
                      if (!isYou && (address ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${address!.trim()} • ${EaI18n.t(context, 'Trusted session')}',
                          style: EaText.small.copyWith(
                            color: EaAdaptiveColor.secondaryText(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.end,
                  children: [
                    if (isHost) _flagChip(EaI18n.t(context, 'Host')),
                    if (isYou) _flagChip(EaI18n.t(context, 'You')),
                  ],
                ),
              ],
            ),
            if (isYou && !_isHost) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: _requestHostTransfer,
                  icon: const Icon(Icons.swap_horiz, size: 16),
                  label: Text(EaI18n.t(context, 'Request to be Host')),
                ),
              ),
            ],
            if (!isYou && _isHost) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(EaI18n.t(context, 'Can control devices')),
                  ),
                  Switch.adaptive(
                    activeThumbColor: EaColor.fore,
                    value: p['canControl'] == true,
                    onChanged: (v) => _setPeerPolicy(instanceId, canControl: v),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(EaI18n.t(context, 'Can modify configuration')),
                  ),
                  Switch.adaptive(
                    activeThumbColor: EaColor.fore,
                    value: p['canModify'] == true,
                    onChanged: (v) => _setPeerPolicy(instanceId, canModify: v),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _transferRequestCard(_HostTransferRequest req) {
    final participants = _activeSessionIds
        .where((id) => id != req.requesterId)
        .toSet();
    final needed = participants.length;
    final approvals = req.approvedBy.length;
    final rejections = req.rejectedBy.length;
    final canVote =
        !req.resolved &&
        req.requesterId != _instanceId &&
        !req.hasVoteFrom(_instanceId);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: EaAdaptiveColor.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EaAdaptiveColor.border(context)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.swap_horizontal_circle_outlined,
                  color: EaColor.fore,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    req.requesterId == _instanceId
                        ? EaI18n.t(context, 'You requested host transfer')
                        : EaI18n.t(context, '{name} requested host transfer', {
                            'name': _displayNameForInstance(req.requesterId),
                          }),
                    style: EaText.secondary.copyWith(
                      color: EaAdaptiveColor.bodyText(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (req.resolved) ...[
                  const SizedBox(width: 10),
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: (req.accepted ? Colors.green : Colors.redAccent)
                          .withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      req.accepted ? Icons.check : Icons.close,
                      color: req.accepted ? Colors.green : Colors.redAccent,
                      size: 14,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              EaI18n.t(context, 'Approvals {ok}/{total} • Rejections {no}', {
                'ok': '$approvals',
                'total': '$needed',
                'no': '$rejections',
              }),
              style: EaText.small.copyWith(
                color: EaAdaptiveColor.secondaryText(context),
              ),
            ),
            if (req.resolutionMessage.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                req.resolutionMessage,
                style: EaText.small.copyWith(
                  color: EaAdaptiveColor.secondaryText(context),
                ),
              ),
            ],
            if (canVote) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _submitTransferVote(req, false),
                      icon: const Icon(Icons.close_rounded, size: 16),
                      label: Text(EaI18n.t(context, 'Reject')),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _submitTransferVote(req, true),
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: Text(EaI18n.t(context, 'Approve')),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _hostTransferTutorial() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: EaAdaptiveColor.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EaAdaptiveColor.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            EaI18n.t(context, 'Host transfer tutorial'),
            style: EaText.secondary.copyWith(
              color: EaAdaptiveColor.bodyText(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          _tutorialStep(
            icon: Icons.touch_app_rounded,
            text: EaI18n.t(
              context,
              'The candidate session taps Request transfer in the status tile.',
            ),
          ),
          const SizedBox(height: 12),
          _tutorialStep(
            icon: Icons.campaign_outlined,
            text: EaI18n.t(
              context,
              'Everyone online receives an Approve or Reject prompt.',
            ),
          ),
          const SizedBox(height: 12),
          _tutorialStep(
            icon: Icons.verified_user_outlined,
            text: EaI18n.t(
              context,
              'If all approve, host is switched and policies are reapplied.',
            ),
          ),
          const SizedBox(height: 12),
          _tutorialStep(
            icon: Icons.gpp_bad_outlined,
            text: EaI18n.t(
              context,
              'If any session rejects, transfer is canceled immediately.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _tutorialStep({required IconData icon, required String text}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 22,
          child: Align(
            alignment: Alignment.topCenter,
            child: Icon(icon, size: 20, color: EaColor.fore),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: EaText.secondary.copyWith(
              color: EaAdaptiveColor.secondaryText(context),
              fontSize: 12,
              height: 1.32,
            ),
          ),
        ),
      ],
    );
  }

  Future<_NetDiagItem> _dnsCheck(String host) async {
    try {
      final results = await InternetAddress.lookup(
        host,
      ).timeout(const Duration(seconds: 5));
      if (results.isEmpty) {
        return _NetDiagItem(
          label: 'DNS $host',
          ok: false,
          detail: EaI18n.t(context, 'No DNS records returned'),
        );
      }
      final first = results.first.address;
      return _NetDiagItem(label: 'DNS $host', ok: true, detail: first);
    } catch (e) {
      return _NetDiagItem(label: 'DNS $host', ok: false, detail: '$e');
    }
  }

  Future<_NetDiagItem> _httpsCheck(Uri uri) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
      final req = await client.getUrl(uri);
      req.followRedirects = false;
      final res = await req.close().timeout(const Duration(seconds: 6));
      return _NetDiagItem(
        label: 'HTTPS ${uri.host}',
        ok: true,
        detail: 'HTTP ${res.statusCode}',
      );
    } catch (e) {
      return _NetDiagItem(label: 'HTTPS ${uri.host}', ok: false, detail: '$e');
    } finally {
      client?.close(force: true);
    }
  }

  Future<List<_NetDiagItem>> _collectDiagnostics() async {
    final items = <_NetDiagItem>[];

    items.add(
      _NetDiagItem(
        label: EaI18n.t(context, 'LAN discovery socket'),
        ok: _socket != null,
        detail: _socket == null
            ? EaI18n.t(context, 'Socket not active yet')
            : EaI18n.t(context, 'Socket active'),
      ),
    );

    items.add(
      _NetDiagItem(
        label: EaI18n.t(context, 'Peers currently visible'),
        ok: _peers.isNotEmpty,
        detail: '${_peers.length}',
      ),
    );

    items.add(await _dnsCheck('oauth2.googleapis.com'));
    items.add(await _dnsCheck('www.googleapis.com'));
    items.add(await _dnsCheck('accounts.google.com'));

    items.add(
      await _httpsCheck(Uri.parse('https://oauth2.googleapis.com/token')),
    );
    items.add(
      await _httpsCheck(
        Uri.parse('https://www.googleapis.com/oauth2/v4/token'),
      ),
    );
    items.add(
      await _httpsCheck(
        Uri.parse('https://accounts.google.com/o/oauth2/token'),
      ),
    );

    return items;
  }

  void _openDiagnosticsSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) {
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
            color: EaAdaptiveColor.surface(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: EaAdaptiveColor.border(context)),
          ),
          child: FutureBuilder<List<_NetDiagItem>>(
            future: _collectDiagnostics(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const SizedBox(
                  height: 220,
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final items = snap.data!;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    EaI18n.t(context, 'Diagnostics'),
                    style: EaText.secondary.copyWith(
                      color: EaAdaptiveColor.bodyText(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(context).size.height * 0.64,
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, _) => Divider(
                        color: EaAdaptiveColor.border(context),
                        height: 12,
                      ),
                      itemBuilder: (_, i) {
                        final item = items[i];
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              item.ok
                                  ? Icons.check_circle_rounded
                                  : Icons.error_outline_rounded,
                              size: 18,
                              color: item.ok ? Colors.green : Colors.redAccent,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.label,
                                    style: EaText.secondary.copyWith(
                                      color: EaAdaptiveColor.bodyText(context),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    item.detail,
                                    style: EaText.small.copyWith(
                                      color: EaAdaptiveColor.secondaryText(
                                        context,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final peers = _sortedPeers;
    final requests = _transferRequests.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return Scaffold(
      appBar: AppBar(
        title: Text(EaI18n.t(context, 'Trusted devices')),
        actions: [
          IconButton(
            tooltip: EaI18n.t(context, 'Diagnostics'),
            onPressed: _openDiagnosticsSheet,
            icon: const Icon(Icons.network_check_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 8, bottom: 10),
              child: Center(child: CircularProgressIndicator()),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
            child: Text(
              EaI18n.t(context, 'Current and recent sessions'),
              style: EaText.secondary.copyWith(
                color: EaAdaptiveColor.bodyText(context),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          _sessionTile(
            instanceId: _instanceId,
            displayName: _displayName,
            platform: Platform.operatingSystem,
            photo: _profilePhoto,
          ),
          ...peers.map(
            (peer) => _sessionTile(
              instanceId: peer.instanceId,
              displayName: peer.displayName,
              platform: peer.platform,
              photo: peer.photo,
              address: peer.address,
            ),
          ),
          if (requests.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
              child: Text(
                EaI18n.t(context, 'Host transfer requests'),
                style: EaText.secondary.copyWith(
                  color: EaAdaptiveColor.bodyText(context),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ...requests.map(_transferRequestCard),
          if (peers.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: Center(
                child: Text(
                  EaI18n.t(
                    context,
                    'There are no other EaSync active sessions.',
                  ),
                  textAlign: TextAlign.center,
                  style: EaText.secondary.copyWith(
                    color: EaAdaptiveColor.secondaryText(context),
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          _hostTransferTutorial(),
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

  String _displayPlan(String raw) {
    final normalized = raw.trim().toLowerCase();
    if (normalized == 'pro') return 'Pro';
    if (normalized == 'plus') return 'Plus';
    return 'Free';
  }

  @override
  Widget build(BuildContext context) {
    final displayedPlan = _displayPlan(_plan);

    return Scaffold(
      appBar: AppBar(title: Text(EaI18n.t(context, 'Experience'))),
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
                    EaI18n.t(context, 'Current plan: {plan}', {
                      'plan': displayedPlan,
                    }),
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
          _planTile('Free', EaI18n.t(context, 'Up to 3 devices and 1 profile')),
          _planTile(
            'Plus',
            EaI18n.t(
              context,
              'Up to 3 profiles, temperature control, and basic assistant.',
            ),
          ),
          _planTile(
            'Pro',
            EaI18n.t(context, 'Unlimited resources and full assistant modes'),
            displayName: EaI18n.t(context, 'Pro'),
          ),
        ],
      ),
    );
  }

  Widget _planTile(String plan, String desc, {String? displayName}) {
    return Card(
      child: ListTile(
        title: Text(displayName ?? plan),
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
      appBar: AppBar(title: Text(EaI18n.t(context, 'Billing'))),
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
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
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

    await OAuthService.instance.logout();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    const secure = FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    );
    await secure.deleteAll();

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
