/*!
 * @file assistant.dart
 * @brief AI-style assistant page with local pattern learning and recommendations.
 * @param No external parameters.
 * @return Stateful page with insights and smart suggestion actions.
 * @author Erick Radmann
 */

import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'handler.dart';

class Assistant extends StatefulWidget {
  const Assistant({super.key});

  @override
  State<Assistant> createState() => _AssistantState();
}

class _AssistantState extends State<Assistant> {
  static const _kPowerOnByHour = 'assistant.power_on_by_hour';
  static const _kAppOpenByHour = 'assistant.app_open_by_hour';
  static const _kObservedActions = 'assistant.observed_actions';
  static const _kOutsideTemp = 'assistant.outside_temp';
  static const _kLocationQuery = 'assistant.location_query';
  static const _kAutoArrivalEnabled = 'assistant.auto_arrival_enabled';
  static const _kLastAutoRunDay = 'assistant.last_auto_run_day';
  static const _kUseLocationData = 'assistant.use_location_data';
  static const _kUseWeatherData = 'assistant.use_weather_data';
  static const _kUseUsageHistory = 'assistant.use_usage_history';
  static const _kAllowDeviceControl = 'assistant.allow_device_control';
  static const _kAllowAutoRoutines = 'assistant.allow_auto_routines';

  bool _loading = true;
  String? _initError;
  int _observedActions = 0;
  double _outsideTemp = 27;
  String _locationQuery = '';
  bool _weatherLoading = false;
  bool _autoArrivalEnabled = false;
  String _lastAutoRunDay = '';
  bool _useLocationData = true;
  bool _useWeatherData = true;
  bool _useUsageHistory = true;
  bool _allowDeviceControl = true;
  bool _allowAutoRoutines = true;
  int _annotationIndex = 0;

  final Map<int, int> _powerOnByHour = {};
  final Map<int, int> _appOpenByHour = {};
  final Map<String, bool> _lastPowerByDevice = {};

  StreamSubscription<CoreEventData>? _eventSub;
  Timer? _automationTimer;
  Timer? _annotationTimer;
  final TextEditingController _commandController = TextEditingController();
  bool _useAudioInput = false;
  bool _isRecordingAudio = false;
  final List<String> _commandLog = [];
  String _assistantReply = 'Hello! I can automate your devices from text commands.';

  @override
  void initState() {
    super.initState();
    _initAssistant();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _automationTimer?.cancel();
    _annotationTimer?.cancel();
    _commandController.dispose();
    super.dispose();
  }

  void _pushCommandLog(String line) {
    _commandLog.insert(0, line);
    if (_commandLog.length > 6) {
      _commandLog.removeRange(6, _commandLog.length);
    }
  }

  int? _extractFirstInt(String text) {
    final m = RegExp(r'(\d{1,3})').firstMatch(text);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  Map<String, int> _encodeHourMap(Map<int, int> source) {
    return source.map((k, v) => MapEntry(k.toString(), v));
  }

  String _normalizeInput(String raw) {
    final lower = raw.toLowerCase();
    final collapsed = lower.replaceAll(RegExp(r'\s+'), ' ').trim();
    return collapsed
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('ã', 'a')
        .replaceAll('é', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('õ', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ç', 'c');
  }

  bool _isGreeting(String text) {
    return text.contains('good morning') ||
        text.contains('good afternoon') ||
        text.contains('good evening') ||
        text.contains('hello') ||
        text.contains('hi');
  }

  bool _containsActionKeyword(String text) {
    return text.contains('turn on') ||
        text.contains('turn off') ||
        text.contains('brightness') ||
        text.contains('temp') ||
        text.contains('temperature') ||
        text.contains('mode') ||
        text.contains('color') ||
        text.contains('position') ||
        text.contains('open') ||
        text.contains('close') ||
        text.contains('set') ||
        text.contains('position');
  }

  String _greetingResponse() {
    final h = DateTime.now().hour;
    if (h < 12) {
      return 'Good morning! I can turn devices on/off and set temperature, brightness, mode and color.';
    }
    if (h < 18) {
      return 'Good afternoon! Tell me a command and I will automate it.';
    }
    return 'Good evening! I can prepare your home with a quick command.';
  }

  DeviceInfo? _findBestDevice(String raw) {
    final query = raw.toLowerCase();
    final devices = Bridge.listDevices();

    for (final d in devices) {
      final hay = '${d.name} ${d.brand} ${d.model}'.toLowerCase();
      if (query.contains(d.name.toLowerCase()) || hay.contains(query)) {
        return d;
      }
    }

    for (final d in devices) {
      final hay = '${d.name} ${d.brand} ${d.model}'.toLowerCase();
      final words = query.split(RegExp(r'\s+')).where((e) => e.isNotEmpty);
      final score = words.where((w) => hay.contains(w)).length;
      if (score >= 2) return d;
    }

    return devices.isEmpty ? null : devices.first;
  }

  int _resolveModeIndex(DeviceInfo device, String query) {
    final count = Bridge.modeCount(device.uuid);
    final intRaw = _extractFirstInt(query);
    if (intRaw != null) {
      return intRaw.clamp(0, count - 1);
    }

    for (var i = 0; i < count; i++) {
      final name = Bridge.modeName(device.uuid, i).toLowerCase();
      if (query.contains(name)) return i;
    }
    return 0;
  }

  int _resolveColor(String text) {
    final q = text.toLowerCase();
    if (q.contains('blue')) return 0x000066FF;
    if (q.contains('green')) return 0x0000C853;
    if (q.contains('red')) return 0x00E53935;
    if (q.contains('purple')) return 0x009C27B0;
    if (q.contains('yellow')) return 0x00FFD600;
    if (q.contains('orange')) return 0x00FB8C00;
    if (q.contains('white')) return 0x00F5F5F5;
    return 0x00D084FF;
  }

  List<String> _applyClause(DeviceInfo target, String clause) {
    if (!_allowDeviceControl) {
      return ['device control is disabled in Assistant Data'];
    }

    final actions = <String>[];

    if ((clause.contains('turn off') || clause.contains('power off')) &&
        target.capabilities.contains(CoreCapability.CORE_CAP_POWER)) {
      Bridge.setPower(target.uuid, false);
      actions.add('turned off ${target.name}');
      _pushCommandLog('Power OFF → ${target.name}');
    }

    if ((clause.contains('turn on') || clause.contains('power on')) &&
        target.capabilities.contains(CoreCapability.CORE_CAP_POWER)) {
      Bridge.setPower(target.uuid, true);
      actions.add('turned on ${target.name}');
      _pushCommandLog('Power ON → ${target.name}');
    }

    if (clause.contains('brightness') &&
        target.capabilities.contains(CoreCapability.CORE_CAP_BRIGHTNESS)) {
      final pct = (_extractFirstInt(clause) ?? 70).clamp(0, 100);
      Bridge.setBrightness(target.uuid, pct);
      actions.add('set brightness to ${pct}% on ${target.name}');
      _pushCommandLog('Brightness $pct% → ${target.name}');
    }

    if ((clause.contains('temperature') || clause.contains('temp')) &&
        target.capabilities.contains(CoreCapability.CORE_CAP_TEMPERATURE)) {
      final rawInt = _extractFirstInt(clause) ?? 23;
      final temp = rawInt.clamp(16, 30).toDouble();
      Bridge.setTemperature(target.uuid, temp);
      actions.add('set temperature to ${temp.toStringAsFixed(0)}°C on ${target.name}');
      _pushCommandLog('Temperature ${temp.toStringAsFixed(0)}°C → ${target.name}');
    }

    if (clause.contains('mode') &&
        target.capabilities.contains(CoreCapability.CORE_CAP_MODE)) {
      final idx = _resolveModeIndex(target, clause);
      Bridge.setMode(target.uuid, idx);
      final modeName = Bridge.modeName(target.uuid, idx);
      actions.add('set mode $modeName on ${target.name}');
      _pushCommandLog('Mode $modeName → ${target.name}');
    }

    if (clause.contains('color') &&
        target.capabilities.contains(CoreCapability.CORE_CAP_COLOR)) {
      final c = _resolveColor(clause);
      Bridge.setColor(target.uuid, c);
      actions.add('set color on ${target.name}');
      _pushCommandLog('Color set → ${target.name}');
    }

    if (clause.contains('position') &&
        target.capabilities.contains(CoreCapability.CORE_CAP_POSITION)) {
      final pos = (_extractFirstInt(clause) ?? 50).clamp(0, 100).toDouble();
      Bridge.setPosition(target.uuid, pos);
      actions.add('set position to ${pos.toStringAsFixed(0)}% on ${target.name}');
      _pushCommandLog('Position ${pos.toStringAsFixed(0)}% → ${target.name}');
    }

    if ((clause.contains('open') || clause.contains('close')) &&
        target.capabilities.contains(CoreCapability.CORE_CAP_POSITION)) {
      final pos = clause.contains('close') ? 0.0 : 100.0;
      Bridge.setPosition(target.uuid, pos);
      actions.add('${clause.contains('close') ? 'closed' : 'opened'} ${target.name}');
      _pushCommandLog('Position ${pos.toStringAsFixed(0)}% → ${target.name}');
    }

    return actions;
  }

  Future<void> _executeAssistantCommand(String raw) async {
    final input = raw.trim();
    if (input.isEmpty) return;

    final text = _normalizeInput(input);
    final hasAction = _containsActionKeyword(text);
    final greeted = _isGreeting(text);

    if (greeted && !hasAction) {
      setState(() {
        _assistantReply = _greetingResponse();
      });
      return;
    }

    final devices = Bridge.listDevices();
    final fallbackTarget = _findBestDevice(text);

    if (devices.isEmpty || fallbackTarget == null) {
      setState(() {
        _assistantReply = 'I could not find devices to automate right now.';
      });
      return;
    }

    if (!_allowDeviceControl) {
      setState(() {
        _assistantReply =
            'Device control is disabled. Enable it in Assistant Data to run automation commands.';
      });
      return;
    }

    try {
      final clauses = text
          .split(RegExp(r',|;|\band\b|\bthen\b|\bafter\b'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final allActions = <String>[];
      for (final clause in clauses) {
        final target = _findBestDevice(clause) ?? fallbackTarget;
        allActions.addAll(_applyClause(target, clause));
      }

      if (allActions.isEmpty) {
        setState(() {
          _assistantReply =
              'I could not map this command. Try: "turn on AC and set temperature 23", "set brightness 80 and color blue".';
        });
        return;
      }

      final greetingPrefix = greeted ? '${_greetingResponse()} ' : '';
      setState(() {
        _assistantReply =
            '${greetingPrefix}Done. I executed ${allActions.length} action(s): ${allActions.take(3).join(', ')}${allActions.length > 3 ? '...' : ''}.';
      });
    } catch (_) {
      setState(() {
        _assistantReply = 'I failed to apply the command. Please try again.';
      });
    }
  }

  Future<void> _toggleAudioCapture() async {
    if (!_isRecordingAudio) {
      setState(() => _isRecordingAudio = true);
      return;
    }

    setState(() => _isRecordingAudio = false);

    // Minimal audio placeholder transcript until ASR is wired.
    if (_commandController.text.trim().isEmpty) {
      _commandController.text = 'turn on AC and set temperature 23';
    }

    await _executeAssistantCommand(_commandController.text);
  }

  Future<void> _initAssistant() async {
    try {
      _initError = null;
      await _loadState();

      // Baseline state for edge detection (power OFF -> ON)
      for (final d in Bridge.listDevices()) {
        try {
          _lastPowerByDevice[d.uuid] = Bridge.getState(d.uuid).power;
        } catch (_) {
          _lastPowerByDevice[d.uuid] = false;
        }
      }

      await _recordAppOpenSignal();

      _eventSub = Bridge.onEvents.listen((event) {
        if (event.type != CoreEventType.CORE_EVENT_STATE_CHANGED) return;

        final prev = _lastPowerByDevice[event.uuid] ?? false;
        final next = event.state.power;
        _lastPowerByDevice[event.uuid] = next;

        if (!prev && next) {
          _recordPowerOnSignal();
        }
      });

      _startAutomationLoop();
      _startAnnotationRotation();

      if (_useLocationData) {
        await _resolveLocationFromDeviceOrNetwork();
      }

      if (_locationQuery.trim().isNotEmpty && _useWeatherData) {
        await _fetchOutsideTemperature();
      }
    } catch (e) {
      _initError = 'Assistant failed to initialize: $e';
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _startAutomationLoop() {
    _automationTimer?.cancel();
    _automationTimer = Timer.periodic(const Duration(minutes: 3), (_) async {
      if (!_autoArrivalEnabled) return;
      if (!_allowAutoRoutines) return;
      if (!_allowDeviceControl) return;
      if (!_useWeatherData) return;
      if (_outsideTemp < 25) return;

      final learnedArrivalHour = _topHour(_powerOnByHour);
      final now = DateTime.now();
      final nearArrival = (now.hour - learnedArrivalHour).abs() <= 1;
      if (!nearArrival) return;

      final dayKey = '${now.year}-${now.month}-${now.day}';
      if (_lastAutoRunDay == dayKey) return;

      await _runArrivalRoutine(automatic: true);
    });
  }

  Map<int, int> _decodeHourMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <int, int>{};
      for (final entry in decoded.entries) {
        final hour = int.tryParse(entry.key.toString());
        final count = int.tryParse(entry.value.toString());
        if (hour == null || count == null) continue;
        out[hour.clamp(0, 23)] = count;
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<void> _persistState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPowerOnByHour, jsonEncode(_encodeHourMap(_powerOnByHour)));
    await prefs.setString(_kAppOpenByHour, jsonEncode(_encodeHourMap(_appOpenByHour)));
    await prefs.setInt(_kObservedActions, _observedActions);
    await prefs.setDouble(_kOutsideTemp, _outsideTemp);
    await prefs.setString(_kLocationQuery, _locationQuery);
    await prefs.setBool(_kAutoArrivalEnabled, _autoArrivalEnabled);
    await prefs.setString(_kLastAutoRunDay, _lastAutoRunDay);
    await prefs.setBool(_kUseLocationData, _useLocationData);
    await prefs.setBool(_kUseWeatherData, _useWeatherData);
    await prefs.setBool(_kUseUsageHistory, _useUsageHistory);
    await prefs.setBool(_kAllowDeviceControl, _allowDeviceControl);
    await prefs.setBool(_kAllowAutoRoutines, _allowAutoRoutines);
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();

    _powerOnByHour
      ..clear()
      ..addAll(_decodeHourMap(prefs.getString(_kPowerOnByHour)));

    _appOpenByHour
      ..clear()
      ..addAll(_decodeHourMap(prefs.getString(_kAppOpenByHour)));

    _observedActions = prefs.getInt(_kObservedActions) ?? 0;
    _outsideTemp = prefs.getDouble(_kOutsideTemp) ?? 27;
    _locationQuery = prefs.getString(_kLocationQuery) ?? '';
    _autoArrivalEnabled = prefs.getBool(_kAutoArrivalEnabled) ?? false;
    _lastAutoRunDay = prefs.getString(_kLastAutoRunDay) ?? '';
    _useLocationData = prefs.getBool(_kUseLocationData) ?? true;
    _useWeatherData = prefs.getBool(_kUseWeatherData) ?? true;
    _useUsageHistory = prefs.getBool(_kUseUsageHistory) ?? true;
    _allowDeviceControl = prefs.getBool(_kAllowDeviceControl) ?? true;
    _allowAutoRoutines = prefs.getBool(_kAllowAutoRoutines) ?? true;
  }

  int _topHour(Map<int, int> source) {
    if (source.isEmpty) return 18;
    var bestHour = source.keys.first;
    var bestCount = source.values.first;
    for (final e in source.entries) {
      if (e.value > bestCount) {
        bestCount = e.value;
        bestHour = e.key;
      }
    }
    return bestHour;
  }

  Future<void> _recordPowerOnSignal() async {
    final nowHour = DateTime.now().hour;
    _powerOnByHour[nowHour] = (_powerOnByHour[nowHour] ?? 0) + 1;
    _observedActions++;
    await _persistState();
    if (mounted) setState(() {});
  }

  Future<void> _recordAppOpenSignal() async {
    final nowHour = DateTime.now().hour;
    _appOpenByHour[nowHour] = (_appOpenByHour[nowHour] ?? 0) + 1;
    _observedActions++;
    await _persistState();
    if (mounted) setState(() {});
  }

  String _hourLabel(int hour) {
    final h = hour.clamp(0, 23);
    return '${h.toString().padLeft(2, '0')}:00';
  }

  Future<void> _promptForLocation() async {
    final controller = TextEditingController(text: _locationQuery);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: EaColor.back,
          title: Text('Your location', style: EaText.primary),
          content: TextField(
            controller: controller,
            autofocus: true,
            cursorColor: EaColor.fore,
            style: EaText.secondary.copyWith(color: EaColor.textPrimary),
            decoration: InputDecoration(
              hintText: 'City or city,country (e.g. London,UK)',
              hintStyle: EaText.secondaryTranslucent,
              filled: true,
              fillColor: EaColor.secondaryBack,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: EaColor.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: EaColor.fore),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: EaText.secondary),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text('Save', style: EaText.accent),
            ),
          ],
        );
      },
    );

    controller.dispose();
    final next = (value ?? '').trim();
    if (next.isEmpty) return;
    setState(() => _locationQuery = next);
    await _persistState();
    await _fetchOutsideTemperature();
  }

  void _startAnnotationRotation() {
    _annotationTimer?.cancel();
    _annotationTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted) return;
      final total = _annotationModels().length;
      if (total <= 1) return;
      setState(() => _annotationIndex = (_annotationIndex + 1) % total);
    });
  }

  Future<void> _resolveLocationFromDeviceOrNetwork() async {
    if (!_useLocationData) return;
    if (_locationQuery.trim().isNotEmpty) return;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        var permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }

        if (permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse) {
          final pos = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
          );

          final viaReverse = await _reverseGeocodeLocation(pos.latitude, pos.longitude);
          if (viaReverse.trim().isNotEmpty) {
            _locationQuery = viaReverse;
          } else {
            _locationQuery =
                '${pos.latitude.toStringAsFixed(2)},${pos.longitude.toStringAsFixed(2)}';
          }

          await _persistState();
          if (mounted) setState(() {});
          return;
        }
      }
    } catch (_) {}

    final fallback = await _resolveLocationFromNetwork();
    if (fallback.trim().isEmpty) return;
    _locationQuery = fallback;
    await _persistState();
    if (mounted) setState(() {});
  }

  Future<String> _reverseGeocodeLocation(double lat, double lon) async {
    try {
      final uri = Uri.parse('https://geocode.maps.co/reverse?lat=$lat&lon=$lon');
      final client = HttpClient();
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, 'easync-assistant/1.0');
      final res = await req.close();
      final raw = await res.transform(utf8.decoder).join();
      client.close();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return '';
      final address = decoded['address'];
      if (address is! Map) return '';
      final city = (address['city'] ?? address['town'] ?? address['village'] ?? '').toString();
      final country = (address['country_code'] ?? '').toString().toUpperCase();
      if (city.isEmpty) return '';
      return country.isEmpty ? city : '$city,$country';
    } catch (_) {
      return '';
    }
  }

  Future<String> _resolveLocationFromNetwork() async {
    try {
      final uri = Uri.parse('https://ipwho.is/');
      final client = HttpClient();
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, 'easync-assistant/1.0');
      final res = await req.close();
      final raw = await res.transform(utf8.decoder).join();
      client.close();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return '';
      final city = (decoded['city'] ?? '').toString();
      final country = (decoded['country_code'] ?? '').toString().toUpperCase();
      if (city.isEmpty) return '';
      return country.isEmpty ? city : '$city,$country';
    } catch (_) {
      return '';
    }
  }

  Future<void> _fetchOutsideTemperature() async {
    if (!_useWeatherData) return;
    if (_locationQuery.trim().isEmpty) return;
    setState(() => _weatherLoading = true);
    try {
      final encoded = Uri.encodeComponent(_locationQuery.trim());
      final uri = Uri.parse('https://wttr.in/$encoded?format=j1');
      final client = HttpClient();
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, 'easync-assistant/1.0');
      final res = await req.close();
      final raw = await res.transform(utf8.decoder).join();
      client.close();

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final current = decoded['current_condition'];
      if (current is! List || current.isEmpty) return;
      final first = current.first;
      if (first is! Map) return;
      final tempRaw = first['temp_C']?.toString() ?? '';
      final parsed = double.tryParse(tempRaw);
      if (parsed == null) return;

      _outsideTemp = parsed;
      await _persistState();
      if (mounted) setState(() {});
    } catch (_) {
      // Keep previously known temperature.
    } finally {
      if (mounted) setState(() => _weatherLoading = false);
    }
  }

  Future<void> _applyClimateSuggestion() async {
    if (!_allowDeviceControl) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Device control is disabled in Assistant Data.')),
      );
      return;
    }

    final list = Bridge.listDevices();
    final target = list.firstWhere(
      (d) => d.capabilities.contains(CoreCapability.CORE_CAP_TEMPERATURE),
      orElse: () => DeviceInfo(
        uuid: '',
        name: '',
        brand: '',
        model: '',
        protocol: CoreProtocol.CORE_PROTOCOL_MOCK,
        capabilities: const [],
      ),
    );

    if (target.uuid.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No temperature-capable device found.')),
      );
      return;
    }

    try {
      Bridge.setPower(target.uuid, true);
      Bridge.setTemperature(target.uuid, 23);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Suggestion applied to ${target.name}.')),
      );
    } catch (_) {}
  }

  double _arrivalConfidence() {
    final total = _powerOnByHour.values.fold<int>(0, (a, b) => a + b);
    if (total <= 0) return 0.35;
    final peak = _powerOnByHour[_topHour(_powerOnByHour)] ?? 0;
    final ratio = (peak / total).clamp(0.0, 1.0);
    return (0.35 + ratio * 0.60).clamp(0.35, 0.95);
  }

  Future<void> _runArrivalRoutine({bool automatic = false}) async {
    if (!_allowDeviceControl || !_allowAutoRoutines) return;

    final list = Bridge.listDevices();
    final target = list.firstWhere(
      (d) => d.capabilities.contains(CoreCapability.CORE_CAP_TEMPERATURE),
      orElse: () => DeviceInfo(
        uuid: '',
        name: '',
        brand: '',
        model: '',
        protocol: CoreProtocol.CORE_PROTOCOL_MOCK,
        capabilities: const [],
      ),
    );

    if (target.uuid.isEmpty) return;

    final desiredTemp = _outsideTemp >= 33
        ? 22.0
        : _outsideTemp >= 27
        ? 23.0
        : 24.0;

    try {
      Bridge.setPower(target.uuid, true);
      Bridge.setTemperature(target.uuid, desiredTemp);

      if (automatic) {
        final now = DateTime.now();
        _lastAutoRunDay = '${now.year}-${now.month}-${now.day}';
        await _persistState();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            automatic
                ? 'Assistant auto-routine applied on ${target.name}.'
                : 'Arrival routine applied on ${target.name}.',
          ),
        ),
      );
    } catch (_) {}
  }

  Widget _card({
    required IconData icon,
    required String title,
    required String description,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: EaColor.secondaryBack,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EaColor.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: EaColor.fore, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: EaText.secondary.copyWith(fontSize: 15)),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: EaText.secondaryTranslucent.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing,
          ],
        ],
      ),
    );
  }

  List<_AnnotationModel> _annotationModels() {
    final learnedArrivalHour = _topHour(_powerOnByHour);
    final openPatternHour = _topHour(_appOpenByHour);
    final nowHour = DateTime.now().hour;
    final nearArrival = (nowHour - learnedArrivalHour).abs() <= 1;
    final arrivalConfidence = (_arrivalConfidence() * 100).round();

    final items = <_AnnotationModel>[
      _AnnotationModel(
        icon: Icons.psychology_outlined,
        title: 'Learning your patterns',
        description: _useUsageHistory
            ? 'Observed actions: $_observedActions. Typical app-open around ${_hourLabel(openPatternHour)}.'
            : 'Usage-history consumption is disabled in Assistant Data.',
      ),
      _AnnotationModel(
        icon: Icons.schedule,
        title: 'Arrival behavior',
        description: _useUsageHistory
            ? 'The user usually gets home around ${_hourLabel(learnedArrivalHour)} and tends to prefer ${_outsideTemp >= 26 ? 'cooler' : 'balanced'} comfort settings.'
            : 'Enable usage history to improve arrival-behavior learning.',
      ),
    ];

    if (_outsideTemp >= 27 && _useWeatherData) {
      items.add(
        _AnnotationModel(
          icon: Icons.wb_sunny_outlined,
          title: 'Climate suggestion',
          description: nearArrival
              ? 'It is warm and near your typical arrival time. Suggestion: enable AC at 23°C now.'
              : 'Warm weather detected. Suggestion: prepare cooling mode before arrival.',
          onApply: _allowDeviceControl ? _applyClimateSuggestion : null,
          actionLabel: _allowDeviceControl ? 'Apply' : 'Disabled',
        ),
      );
    }

    items.add(
      _AnnotationModel(
        icon: Icons.home_outlined,
        title: 'Arrival routine',
        description:
            'Confidence: $arrivalConfidence%. Learned arrival around ${_hourLabel(learnedArrivalHour)}. Routine: turn on AC and set comfort temperature based on weather.',
        onApply: (_allowDeviceControl && _allowAutoRoutines) ? _runArrivalRoutine : null,
        actionLabel: (_allowDeviceControl && _allowAutoRoutines) ? 'Run now' : 'Disabled',
      ),
    );

    if (_outsideTemp < 27 || !_useWeatherData) {
      items.add(
        const _AnnotationModel(
          icon: Icons.auto_awesome_outlined,
          title: 'No urgent annotation',
          description:
              'Assistant is still learning your routine. Keep using devices normally to improve suggestions.',
        ),
      );
    }

    return items;
  }

  void _showAllAnnotationsBottomSheet(List<_AnnotationModel> annotations) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: EaColor.back,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('All annotations', style: EaText.primary.copyWith(fontSize: 17)),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close, color: EaColor.fore),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: annotations.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final a = annotations[i];
                      return _card(
                        icon: a.icon,
                        title: a.title,
                        description: a.description,
                        trailing: a.onApply == null
                            ? null
                            : TextButton(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  a.onApply?.call();
                                },
                                child: Text(a.actionLabel ?? 'Apply', style: EaText.accent),
                              ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: EaColor.fore),
      );
    }

    if (_initError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent, size: 34),
              const SizedBox(height: 10),
              Text(
                _initError!,
                textAlign: TextAlign.center,
                style: EaText.secondary.copyWith(color: EaColor.textSecondary),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  setState(() => _loading = true);
                  _initAssistant();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: EaColor.fore,
                  side: const BorderSide(color: EaColor.fore),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final annotations = _annotationModels();
    final currentAnnotation = annotations[_annotationIndex % annotations.length];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Assistant Data', style: EaText.primary.copyWith(fontSize: 18)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: EaColor.back,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: EaColor.border),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const SizedBox(width: 8),
                      Text('Outside temperature', style: EaText.secondary),
                      const Spacer(),
                      if (_weatherLoading)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: EaColor.fore),
                        )
                      else
                        Text('${_outsideTemp.toStringAsFixed(0)}°C', style: EaText.accent),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: _useLocationData ? _promptForLocation : null,
                        icon: const Icon(Icons.place_outlined, size: 18),
                        label: Text(
                          _locationQuery.trim().isEmpty
                              ? 'Set location'
                              : _locationQuery,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: (_useWeatherData && _locationQuery.trim().isNotEmpty)
                            ? _fetchOutsideTemperature
                            : null,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Refresh'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _useLocationData,
                    activeColor: EaColor.fore,
                    onChanged: (v) async {
                      if (v == null) return;
                      setState(() => _useLocationData = v);
                      if (v) {
                        await _resolveLocationFromDeviceOrNetwork();
                        if (_locationQuery.trim().isNotEmpty && _useWeatherData) {
                          await _fetchOutsideTemperature();
                        }
                      }
                      await _persistState();
                    },
                    title: Text('Allow AI to consume location', style: EaText.secondary),
                    subtitle: Text(
                      'Use device GPS when available, otherwise network-based location.',
                      style: EaText.secondaryTranslucent,
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _useWeatherData,
                    activeColor: EaColor.fore,
                    onChanged: (v) async {
                      if (v == null) return;
                      setState(() => _useWeatherData = v);
                      if (v && _locationQuery.trim().isNotEmpty) {
                        await _fetchOutsideTemperature();
                      }
                      await _persistState();
                    },
                    title: Text('Allow AI to consume weather data', style: EaText.secondary),
                    subtitle: Text(
                      'Weather informs climate and arrival suggestions.',
                      style: EaText.secondaryTranslucent,
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _useUsageHistory,
                    activeColor: EaColor.fore,
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _useUsageHistory = v);
                      _persistState();
                    },
                    title: Text('Allow AI to consume usage history', style: EaText.secondary),
                    subtitle: Text(
                      'Lets Assistant learn open/arrival patterns over time.',
                      style: EaText.secondaryTranslucent,
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _allowDeviceControl,
                    activeColor: EaColor.fore,
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _allowDeviceControl = v);
                      _persistState();
                    },
                    title: Text('Allow AI to control devices', style: EaText.secondary),
                    subtitle: Text(
                      'Enables command execution and suggestion apply buttons.',
                      style: EaText.secondaryTranslucent,
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _allowAutoRoutines,
                    activeColor: EaColor.fore,
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _allowAutoRoutines = v);
                      _persistState();
                    },
                    title: Text('Allow AI to run automatic routines', style: EaText.secondary),
                    subtitle: Text(
                      'Allows periodic auto-arrival automation near learned time.',
                      style: EaText.secondaryTranslucent,
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  const SizedBox(height: 2),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _autoArrivalEnabled && _allowAutoRoutines,
                    activeThumbColor: EaColor.fore,
                    onChanged: (v) {
                      if (!_allowAutoRoutines) return;
                      setState(() => _autoArrivalEnabled = v);
                      _persistState();
                    },
                    title: Text('Enable auto-arrival routine', style: EaText.secondary),
                    subtitle: Text(
                      'Auto run near ${_hourLabel(_topHour(_powerOnByHour))} when weather is warm.',
                      style: EaText.secondaryTranslucent,
                    ),
                    secondary: const Icon(Icons.auto_mode, color: EaColor.fore),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text('Annotations', style: EaText.primary.copyWith(fontSize: 18)),
                ),
                TextButton(
                  onPressed: () => _showAllAnnotationsBottomSheet(annotations),
                  child: Text('View details', style: EaText.secondary.copyWith(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 220,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _card(
                      icon: currentAnnotation.icon,
                      title: currentAnnotation.title,
                      description: currentAnnotation.description,
                      trailing: currentAnnotation.onApply == null
                          ? null
                          : TextButton(
                              onPressed: currentAnnotation.onApply,
                              child: Text(
                                currentAnnotation.actionLabel ?? 'Apply',
                                style: EaText.accent,
                              ),
                            ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(annotations.length, (i) {
                        final active = i == (_annotationIndex % annotations.length);
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          width: active ? 18 : 6,
                          height: 6,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: active
                                ? EaColor.fore
                                : EaColor.fore.withValues(alpha: .22),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('Command center', style: EaText.primary.copyWith(fontSize: 18)),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: EaColor.back,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: EaColor.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Text'),
                        selected: !_useAudioInput,
                        onSelected: (_) => setState(() => _useAudioInput = false),
                        selectedColor: EaColor.fore.withValues(alpha: .22),
                        side: const BorderSide(color: EaColor.border),
                        labelStyle: EaText.secondary,
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Audio'),
                        selected: _useAudioInput,
                        onSelected: (_) => setState(() => _useAudioInput = true),
                        selectedColor: EaColor.fore.withValues(alpha: .22),
                        side: const BorderSide(color: EaColor.border),
                        labelStyle: EaText.secondary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _commandController,
                    minLines: 1,
                    maxLines: 3,
                    cursorColor: EaColor.fore,
                    style: EaText.secondary.copyWith(color: EaColor.textPrimary),
                    decoration: InputDecoration(
                      hintText: _useAudioInput
                          ? 'Audio transcript will appear here (minimal mode).'
                          : 'Ex.: turn on living room AC and set temperature 23',
                      hintStyle: EaText.secondaryTranslucent,
                      filled: true,
                      fillColor: EaColor.secondaryBack,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: EaColor.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: EaColor.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: EaColor.fore),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _executeAssistantCommand(_commandController.text),
                          icon: const Icon(Icons.send_rounded),
                          label: const Text('Run command'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: EaColor.fore,
                            foregroundColor: Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _useAudioInput ? _toggleAudioCapture : null,
                          icon: Icon(_isRecordingAudio ? Icons.stop_circle : Icons.mic),
                          label: Text(_isRecordingAudio ? 'Stop' : 'Record'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: EaColor.fore,
                            side: const BorderSide(color: EaColor.fore),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: EaColor.secondaryBack,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: EaColor.border),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.smart_toy_outlined, size: 16, color: EaColor.fore),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _assistantReply,
                            style: EaText.secondary.copyWith(
                              color: EaColor.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_commandLog.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('Recent automation', style: EaText.secondary),
                    const SizedBox(height: 6),
                    ..._commandLog.map(
                      (e) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text('• $e', style: EaText.secondaryTranslucent),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnnotationModel {
  final IconData icon;
  final String title;
  final String description;
  final Future<void> Function()? onApply;
  final String? actionLabel;

  const _AnnotationModel({
    required this.icon,
    required this.title,
    required this.description,
    this.onApply,
    this.actionLabel,
  });
}
