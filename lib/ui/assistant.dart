/*!
 * @file assistant.dart
 * @brief AI-style assistant page with local pattern learning and recommendations.
 * @param No external parameters.
 * @return Stateful page with insights and smart suggestion actions.
 * @author Erick Radmann
 */

// ignore_for_file: unused_element, unused_field

import 'dart:convert';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voice_recognition_flutter/voice_recognition.dart';
import 'package:voice_recognition_flutter/voice_recognition_platform_interface.dart';

import 'handler.dart';

class Assistant extends StatefulWidget {
  const Assistant({super.key});

  @override
  State<Assistant> createState() => _AssistantState();
}

class _AssistantState extends State<Assistant> with TickerProviderStateMixin {
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
  static const _kTemperament = 'assistant.temperament';
  static const _kDeviceActivityById = 'assistant.device_activity_by_id';
  static const _kTempSetSum = 'assistant.temp_set_sum';
  static const _kTempSetCount = 'assistant.temp_set_count';
  static const _kBrightnessSetSum = 'assistant.brightness_set_sum';
  static const _kBrightnessSetCount = 'assistant.brightness_set_count';
  static const _kPositionSetSum = 'assistant.position_set_sum';
  static const _kPositionSetCount = 'assistant.position_set_count';

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
  int _temperament = 0;
  int _assistantDataIndex = 0;
  int _annotationIndex = 0;
  String _typedCommand = '';
  String _lastRoundRefreshKey = '';
  final Random _rng = Random();

  final Map<int, int> _powerOnByHour = {};
  final Map<int, int> _appOpenByHour = {};
  final Map<String, bool> _lastPowerByDevice = {};
  final Map<String, DeviceState> _lastStateByDevice = {};
  final Map<String, int> _deviceActivityById = {};
  double _tempSetSum = 0;
  int _tempSetCount = 0;
  double _brightnessSetSum = 0;
  int _brightnessSetCount = 0;
  double _positionSetSum = 0;
  int _positionSetCount = 0;
  String? _lastReferencedDeviceId;
  final List<DeviceInfo> _pendingTargets = [];
  String? _pendingClause;
  final VoiceRecognition _voiceRecognition = VoiceRecognition();

  StreamSubscription<CoreEventData>? _eventSub;
  Timer? _automationTimer;
  Timer? _assistantDataTimer;
  Timer? _roundHourWeatherTimer;
  Timer? _annotationTimer;
  StreamSubscription<dynamic>? _voiceEventSub;
  Timer? _voiceSilenceTimer;
  Timer? _chatTypingTimer;
  bool _voiceCommandExecuted = false;
  bool _assistantThinking = false;
  bool _chatBorderStarted = false;
  late final AnimationController _thinkingController;
  late final AnimationController _chatBorderPulse;
  int _annotationSlideDir = 1;
  double _assistantDataDragAccum = 0;
  bool _assistantDataDragConsumed = false;
  double _annotationDragAccum = 0;
  bool _annotationDragConsumed = false;
  final TextEditingController _commandController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  bool _isRecordingAudio = false;
  final List<String> _commandLog = [];
  final List<_ChatMessage> _chatMessages = [];

  @override
  void initState() {
    super.initState();
    _thinkingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );
    _chatBorderPulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _commandController.addListener(_onCommandTextChanged);
    _initAssistant();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _automationTimer?.cancel();
    _assistantDataTimer?.cancel();
    _roundHourWeatherTimer?.cancel();
    _annotationTimer?.cancel();
    _voiceEventSub?.cancel();
    _voiceSilenceTimer?.cancel();
    _chatTypingTimer?.cancel();
    _thinkingController.dispose();
    _chatBorderPulse.dispose();
    _commandController.removeListener(_onCommandTextChanged);
    _commandController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _onCommandTextChanged() {
    final next = _commandController.text;
    if (next == _typedCommand) return;
    setState(() => _typedCommand = next);
  }

  bool get _isVoiceSupportedPlatform {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android;
  }

  void _setAssistantThinking(bool value) {
    if (_assistantThinking == value) return;
    _assistantThinking = value;
    if (value) {
      _thinkingController.repeat();
    } else {
      _thinkingController.stop();
      _thinkingController.reset();
    }
    if (mounted) setState(() {});
  }

  void _pushCommandLog(String line) {
    _commandLog.insert(0, line);
    if (_commandLog.length > 6) {
      _commandLog.removeRange(6, _commandLog.length);
    }
  }

  void _appendUserChat(String text) {
    final msg = text.trim();
    if (msg.isEmpty) return;
    setState(() {
      _chatMessages.add(_ChatMessage(role: _ChatRole.user, text: msg));
    });
    _scrollChatToBottom();
  }

  void _appendAssistantChat(String text, {bool animate = true}) {
    final msg = text.trim();
    if (msg.isEmpty) return;

    _chatTypingTimer?.cancel();

    if (!animate) {
      setState(() {
        _chatMessages.add(_ChatMessage(role: _ChatRole.assistant, text: msg));
      });
      _scrollChatToBottom();
      _setAssistantThinking(false);
      return;
    }

    setState(() {
      _chatMessages.add(
        const _ChatMessage(role: _ChatRole.assistant, text: ''),
      );
    });
    _scrollChatToBottom();

    var i = 0;
    _chatTypingTimer = Timer.periodic(const Duration(milliseconds: 14), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      i++;
      final end = i.clamp(0, msg.length);
      setState(() {
        final idx = _chatMessages.length - 1;
        _chatMessages[idx] = _ChatMessage(
          role: _ChatRole.assistant,
          text: msg.substring(0, end),
        );
      });
      _scrollChatToBottom();
      if (end >= msg.length) {
        t.cancel();
        _setAssistantThinking(false);
      }
    });
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_chatScrollController.hasClients) return;
      _chatScrollController.animateTo(
        _chatScrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  int? _extractFirstInt(String text) {
    final m = RegExp(r'(\d{1,3})').firstMatch(text);
    if (m == null) return null;
    return int.tryParse(m.group(1)!);
  }

  Map<String, int> _encodeHourMap(Map<int, int> source) {
    return source.map((k, v) => MapEntry(k.toString(), v));
  }

  Map<String, int> _decodeStringIntMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, int>{};
      for (final e in decoded.entries) {
        final k = e.key.toString();
        final v = int.tryParse(e.value.toString());
        if (k.isEmpty || v == null) continue;
        out[k] = v;
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  DeviceState _copyState(DeviceState s) {
    return DeviceState(power: s.power)
      ..brightness = s.brightness
      ..color = s.color
      ..temperature = s.temperature
      ..temperatureFridge = s.temperatureFridge
      ..temperatureFreezer = s.temperatureFreezer
      ..timestamp = s.timestamp
      ..colorTemperature = s.colorTemperature
      ..lock = s.lock
      ..mode = s.mode
      ..position = s.position;
  }

  void _recordStatePattern(String uuid, DeviceState? prev, DeviceState next) {
    if (prev == null || !_useUsageHistory) return;

    try {
      Bridge.aiRecordPattern(uuid, prev, next);
    } catch (_) {}

    var changed = false;
    if (prev.power != next.power) changed = true;

    if (prev.brightness != next.brightness) {
      changed = true;
      _brightnessSetSum += next.brightness.toDouble();
      _brightnessSetCount++;
    }

    if ((prev.temperature - next.temperature).abs() >= 0.3) {
      changed = true;
      _tempSetSum += next.temperature;
      _tempSetCount++;
    }

    if (prev.color != next.color) changed = true;
    if (prev.mode != next.mode) changed = true;
    if (prev.lock != next.lock) changed = true;

    if ((prev.position - next.position).abs() >= 1) {
      changed = true;
      _positionSetSum += next.position;
      _positionSetCount++;
    }

    if (!changed) return;
    _deviceActivityById[uuid] = (_deviceActivityById[uuid] ?? 0) + 1;
    unawaited(_persistState());
  }

  // Chat understanding/execution is fully backend-driven via Bridge + native AI.

  IconData _weatherIconForTemp() {
    if (_outsideTemp >= 31) return Icons.wb_sunny;
    if (_outsideTemp >= 26) return Icons.wb_sunny_outlined;
    if (_outsideTemp >= 20) return Icons.cloud_outlined;
    return Icons.ac_unit;
  }

  Future<void> _executeAssistantCommand(String raw) async {
    final input = raw.trim();
    if (input.isEmpty) return;

    if (_assistantThinking) return;

    _appendUserChat(input);
    _setAssistantThinking(true);

    try {
      final backendReply = (await Bridge.aiExecuteCommandAsync(input)).trim();
      if (backendReply.isNotEmpty) {
        _appendAssistantChat(backendReply, animate: false);
      }
    } catch (_) {
      _appendAssistantChat('Backend AI execution error.', animate: false);
    }
  }

  Future<void> _toggleAudioCapture() async {
    if (!_isVoiceSupportedPlatform) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: Duration(seconds: 2),
          animation: Animation.fromValueListenable(
            CurvedAnimation(
              parent: AlwaysStoppedAnimation(1),
              curve: Curves.easeOutSine,
            ),
          ),
          backgroundColor: EaColor.back,
          content: Text(
            'Voice recognition is only available on Android for now.',
            style: EaText.secondary,
          ),
        ),
      );
      return;
    }

    if (!_isRecordingAudio) {
      await _startVoiceRecognition();
      return;
    }

    await _finishVoiceRecognition();
  }

  Future<void> _startVoiceRecognition() async {
    if (!_isVoiceSupportedPlatform) return;
    _voiceCommandExecuted = false;
    try {
      await _voiceEventSub?.cancel();
      _voiceEventSub = VoiceRecognitionPlatform.instance.listenResult().listen((
        event,
      ) {
        final eventName = event.event;

        if (eventName == 'onPartialResultsEvent') {
          final partial = (event.data ?? '').toString().trim();
          if (partial.isNotEmpty) {
            _commandController.text = partial;
          }
          _armVoiceSilenceTimer();
          return;
        }

        if (eventName == 'onResultsEvent') {
          final finalText = (event.data ?? '').toString().trim();
          if (finalText.isNotEmpty) {
            _commandController.text = finalText;
          }
          _finishVoiceRecognition();
          return;
        }

        if (eventName == 'onRmsChangedEvent') {
          final rms = double.tryParse((event.data ?? '0').toString()) ?? 0;
          if (rms > 1.5) {
            _armVoiceSilenceTimer();
          }
          return;
        }

        if (eventName == 'onErrorEvent') {
          _finishVoiceRecognition();
        }
      });

      await _voiceRecognition.setLanguages('en-US');
      await _voiceRecognition.startVoice();
      if (!mounted) return;
      setState(() => _isRecordingAudio = true);
      _armVoiceSilenceTimer();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isRecordingAudio = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Voice recognition is not available right now.'),
        ),
      );
    }
  }

  void _armVoiceSilenceTimer() {
    _voiceSilenceTimer?.cancel();
    _voiceSilenceTimer = Timer(const Duration(seconds: 2), () {
      if (!_isRecordingAudio) return;
      _finishVoiceRecognition();
    });
  }

  Future<void> _finishVoiceRecognition() async {
    _voiceSilenceTimer?.cancel();

    if (_isRecordingAudio && mounted) {
      setState(() => _isRecordingAudio = false);
    }

    try {
      await _voiceRecognition.stopVoice();
    } catch (_) {}

    final text = _commandController.text.trim();
    if (_voiceCommandExecuted || text.isEmpty) return;
    _voiceCommandExecuted = true;
    await _executeAssistantCommand(text);
  }

  Future<void> _initAssistant() async {
    try {
      _initError = null;
      await _loadState();
      _syncAiPermissions();

      // Baseline state for edge detection (power OFF -> ON)
      for (final d in Bridge.listDevices()) {
        try {
          final st = Bridge.getState(d.uuid);
          _lastPowerByDevice[d.uuid] = st.power;
          _lastStateByDevice[d.uuid] = _copyState(st);
        } catch (_) {}
      }

      _recordAppOpenSignal();
      await _bootstrapLocationAndWeather();
      _startRoundHourWeatherLoop();
      _startAutomationLoop();
      _startAnnotationRotation();
      _startAssistantDataRotation();

      // No canned assistant greeting. Replies should come from backend AI only.
    } catch (e) {
      _initError = 'Assistant failed to initialize: $e';
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _bootstrapLocationAndWeather() async {
    if (_useLocationData) {
      await _resolveLocationFromDeviceOrNetwork();
    }

    if (_shouldAutoRefreshNow()) {
      final now = DateTime.now();
      _lastRoundRefreshKey = '${now.year}-${now.month}-${now.day}-${now.hour}';
      await _fetchOutsideTemperature();
    }
  }

  bool _shouldAutoRefreshNow() {
    if (!_useWeatherData) return false;
    if (_locationQuery.trim().isEmpty) return false;
    return DateTime.now().minute == 0;
  }

  void _startRoundHourWeatherLoop() {
    _roundHourWeatherTimer?.cancel();
    _roundHourWeatherTimer = Timer.periodic(const Duration(seconds: 30), (
      _,
    ) async {
      if (!_shouldAutoRefreshNow()) return;
      final now = DateTime.now();
      final key = '${now.year}-${now.month}-${now.day}-${now.hour}';
      if (_lastRoundRefreshKey == key) return;
      _lastRoundRefreshKey = key;
      await _fetchOutsideTemperature();
    });
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
    await prefs.setString(
      _kPowerOnByHour,
      jsonEncode(_encodeHourMap(_powerOnByHour)),
    );
    await prefs.setString(
      _kAppOpenByHour,
      jsonEncode(_encodeHourMap(_appOpenByHour)),
    );
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
    await prefs.setInt(_kTemperament, _temperament);
    await prefs.setString(
      _kDeviceActivityById,
      jsonEncode(_deviceActivityById),
    );
    await prefs.setDouble(_kTempSetSum, _tempSetSum);
    await prefs.setInt(_kTempSetCount, _tempSetCount);
    await prefs.setDouble(_kBrightnessSetSum, _brightnessSetSum);
    await prefs.setInt(_kBrightnessSetCount, _brightnessSetCount);
    await prefs.setDouble(_kPositionSetSum, _positionSetSum);
    await prefs.setInt(_kPositionSetCount, _positionSetCount);
    _syncAiPermissions();
  }

  void _syncAiPermissions() {
    try {
      Bridge.setAiPermissions(
        AiPermissions(
          useLocationData: _useLocationData,
          useWeatherData: _useWeatherData,
          useUsageHistory: _useUsageHistory,
          allowDeviceControl: _allowDeviceControl,
          allowAutoRoutines: _allowAutoRoutines,
          temperament: _temperament,
        ),
      );
    } catch (_) {}
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
    _temperament = prefs.getInt(_kTemperament) ?? 0;

    _deviceActivityById
      ..clear()
      ..addAll(_decodeStringIntMap(prefs.getString(_kDeviceActivityById)));
    _tempSetSum = prefs.getDouble(_kTempSetSum) ?? 0;
    _tempSetCount = prefs.getInt(_kTempSetCount) ?? 0;
    _brightnessSetSum = prefs.getDouble(_kBrightnessSetSum) ?? 0;
    _brightnessSetCount = prefs.getInt(_kBrightnessSetCount) ?? 0;
    _positionSetSum = prefs.getDouble(_kPositionSetSum) ?? 0;
    _positionSetCount = prefs.getInt(_kPositionSetCount) ?? 0;
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
    _observedActions = (_observedActions + 1).clamp(0, 100).toInt();
    await _persistState();
    if (mounted) setState(() {});
  }

  Future<void> _recordAppOpenSignal() async {
    final nowHour = DateTime.now().hour;
    _appOpenByHour[nowHour] = (_appOpenByHour[nowHour] ?? 0) + 1;
    _observedActions = (_observedActions + 1).clamp(0, 100).toInt();
    try {
      Bridge.aiObserveAppOpen();
    } catch (_) {}
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
  }

  void _nextAnnotationTile() {
    final total = _annotationModels().length;
    if (total <= 1) return;
    setState(() {
      _annotationSlideDir = 1;
      _annotationIndex = (_annotationIndex + 1) % total;
    });
  }

  void _startAnnotationRotation() {
    _annotationTimer?.cancel();
    _annotationTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted) return;
      _nextAnnotationTile();
    });
  }

  void _nextAssistantDataTile() {
    final total = _assistantDataTiles().length;
    if (total <= 1) return;
    setState(() {
      _assistantDataIndex = (_assistantDataIndex + 1) % total;
    });
  }

  void _onAssistantDataDragStart(DragStartDetails details) {
    _assistantDataDragAccum = 0;
    _assistantDataDragConsumed = false;
  }

  void _onAssistantDataDragUpdate(DragUpdateDetails details) {
    if (_assistantDataDragConsumed) return;
    _assistantDataDragAccum += details.delta.dx;
    if (_assistantDataDragAccum.abs() < 22) return;
    if (_assistantDataDragAccum < 0) {
      _nextAssistantDataTile();
    } else {
      final total = _assistantDataTiles().length;
      if (total <= 1) return;
      final prev = (_assistantDataIndex - 1 + total) % total;
      setState(() {
        _assistantDataIndex = prev;
      });
    }
    _assistantDataDragConsumed = true;
  }

  void _onAssistantDataDragEnd(DragEndDetails details) {
    _assistantDataDragAccum = 0;
    _assistantDataDragConsumed = false;
  }

  void _onAnnotationDragStart(DragStartDetails details) {
    _annotationDragAccum = 0;
    _annotationDragConsumed = false;
  }

  void _onAnnotationDragUpdate(DragUpdateDetails details) {
    if (_annotationDragConsumed) return;
    _annotationDragAccum += details.delta.dx;
    if (_annotationDragAccum.abs() < 22) return;
    if (_annotationDragAccum < 0) {
      _nextAnnotationTile();
    } else {
      final total = _annotationModels().length;
      if (total <= 1) return;
      final prev = (_annotationIndex - 1 + total) % total;
      setState(() {
        _annotationSlideDir = -1;
        _annotationIndex = prev;
      });
    }
    _annotationDragConsumed = true;
  }

  void _onAnnotationDragEnd(DragEndDetails details) {
    _annotationDragAccum = 0;
    _annotationDragConsumed = false;
  }

  void _startAssistantDataRotation() {
    _assistantDataTimer?.cancel();
    _assistantDataTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted) return;
      _nextAssistantDataTile();
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
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.low,
            ),
          ).timeout(const Duration(seconds: 4));

          final viaReverse = await _reverseGeocodeLocation(
            pos.latitude,
            pos.longitude,
          );
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
    HttpClient? client;
    try {
      final uri = Uri.parse(
        'https://geocode.maps.co/reverse?lat=$lat&lon=$lon',
      );
      client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, 'easync-assistant/1.0');
      final res = await req.close().timeout(const Duration(seconds: 4));
      final raw = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 4));
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return '';
      final address = decoded['address'];
      if (address is! Map) return '';
      final city =
          (address['city'] ?? address['town'] ?? address['village'] ?? '')
              .toString();
      final country = (address['country_code'] ?? '').toString().toUpperCase();
      if (city.isEmpty) return '';
      return country.isEmpty ? city : '$city,$country';
    } catch (_) {
      return '';
    } finally {
      client?.close(force: true);
    }
  }

  Future<String> _resolveLocationFromNetwork() async {
    HttpClient? client;
    try {
      final uri = Uri.parse('https://ipwho.is/');
      client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, 'easync-assistant/1.0');
      final res = await req.close().timeout(const Duration(seconds: 4));
      final raw = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 4));
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return '';
      final city = (decoded['city'] ?? '').toString();
      final country = (decoded['country_code'] ?? '').toString().toUpperCase();
      if (city.isEmpty) return '';
      return country.isEmpty ? city : '$city,$country';
    } catch (_) {
      return '';
    } finally {
      client?.close(force: true);
    }
  }

  Future<void> _fetchOutsideTemperature() async {
    if (!_useWeatherData) return;
    if (_locationQuery.trim().isEmpty) return;
    setState(() => _weatherLoading = true);
    HttpClient? client;
    try {
      final encoded = Uri.encodeComponent(_locationQuery.trim());
      final uri = Uri.parse('https://wttr.in/$encoded?format=j1');
      client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, 'easync-assistant/1.0');
      final res = await req.close().timeout(const Duration(seconds: 4));
      final raw = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 4));

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
      client?.close(force: true);
      if (mounted) setState(() => _weatherLoading = false);
    }
  }

  Future<void> _applyClimateSuggestion() async {
    if (!_allowDeviceControl) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Device control is disabled in Assistant Data.'),
        ),
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
      final preferred = _preferredTemperature() ?? 23;
      Bridge.setTemperature(target.uuid, preferred);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Suggestion applied to ${target.name} (${preferred.toStringAsFixed(0)}°C).',
          ),
        ),
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

  double? _preferredTemperature() {
    if (_tempSetCount < 2) return null;
    return (_tempSetSum / _tempSetCount).clamp(16, 30);
  }

  double? _preferredBrightness() {
    if (_brightnessSetCount < 2) return null;
    return (_brightnessSetSum / _brightnessSetCount).clamp(0, 100);
  }

  double? _preferredPosition() {
    if (_positionSetCount < 2) return null;
    return (_positionSetSum / _positionSetCount).clamp(0, 100);
  }

  String _topActiveDeviceName(List<DeviceInfo> list) {
    if (_deviceActivityById.isEmpty) return 'none yet';
    String? bestId;
    var best = -1;
    for (final e in _deviceActivityById.entries) {
      if (e.value > best) {
        best = e.value;
        bestId = e.key;
      }
    }
    if (bestId == null) return 'none yet';
    for (final d in list) {
      if (d.uuid == bestId) return d.name;
    }
    return 'recent device';
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
    final learnedTemp = _preferredTemperature();
    final targetTemp = (learnedTemp ?? desiredTemp).clamp(16.0, 30.0);

    try {
      Bridge.setPower(target.uuid, true);
      Bridge.setTemperature(target.uuid, targetTemp);

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
                : 'Arrival routine applied on ${target.name} (${targetTemp.toStringAsFixed(0)}°C).',
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
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
        ],
      ),
    );
  }

  List<Widget> _assistantDataTiles() {
    const temperamentLabels = <int, String>{
      0: 'Minimalist',
      1: 'Cheerful',
      2: 'Direct',
      3: 'Professional',
    };

    return [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.tune_rounded, color: EaColor.fore),
        title: Text('Assistant temperament', style: EaText.secondary),
        subtitle: Text(
          'Controls tone of generated answers.',
          style: EaText.secondaryTranslucent,
        ),
        trailing: DropdownButton<int>(
          value: _temperament.clamp(0, 3).toInt(),
          dropdownColor: EaColor.back,
          style: EaText.secondary,
          items: temperamentLabels.entries
              .map(
                (entry) => DropdownMenuItem<int>(
                  value: entry.key,
                  child: Text(entry.value),
                ),
              )
              .toList(),
          onChanged: (v) async {
            if (v == null) return;
            setState(() => _temperament = v);
            await _persistState();
          },
        ),
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: _useLocationData,
        activeColor: EaColor.fore,
        onChanged: (v) async {
          if (v == null) return;
          setState(() => _useLocationData = v);
          if (v) {
            await _resolveLocationFromDeviceOrNetwork();
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
          await _persistState();
          if (_shouldAutoRefreshNow()) {
            await _fetchOutsideTemperature();
          }
        },
        title: Text(
          'Allow AI to consume weather data',
          style: EaText.secondary,
        ),
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
        title: Text(
          'Allow AI to consume usage history',
          style: EaText.secondary,
        ),
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
        title: Text(
          'Allow AI to run automatic routines',
          style: EaText.secondary,
        ),
        subtitle: Text(
          'Allows periodic auto-arrival automation near learned time.',
          style: EaText.secondaryTranslucent,
        ),
        controlAffinity: ListTileControlAffinity.leading,
      ),
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
    ];
  }

  List<_AnnotationModel> _annotationModels() {
    List<String> backend;
    try {
      backend = Bridge.aiAnnotations();
    } catch (_) {
      backend = const [];
    }
    if (backend.isEmpty) {
      return const [
        _AnnotationModel(
          icon: Icons.auto_awesome_outlined,
          title: 'Learning in progress',
          description:
              'Assistant backend is still collecting behavior signals from app usage, commands and profiles.',
        ),
      ];
    }

    final mapped = <_AnnotationModel>[];
    final canRun = _allowDeviceControl && _allowAutoRoutines;
    final lines = backend.take(8).toList();
    for (var i = 0; i < lines.length; i++) {
      mapped.add(
        _AnnotationModel(
          icon: Icons.psychology_outlined,
          title: 'Behavior insight',
          description: lines[i],
          onApply: (i == 0 && canRun) ? _runArrivalRoutine : null,
          actionLabel: (i == 0 && canRun) ? 'Run now' : null,
        ),
      );
    }
    return mapped;
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
                    Text(
                      'All annotations',
                      style: EaText.primary.copyWith(fontSize: 17),
                    ),
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
                    separatorBuilder: (_, i) => const SizedBox(height: 8),
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
                                child: Text(
                                  a.actionLabel ?? 'Apply',
                                  style: EaText.accent,
                                ),
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

  Future<void> _runQuickPrompt(String prompt) async {
    _commandController.text = prompt;
    await _submitCurrentCommand();
  }

  Future<void> _submitCurrentCommand() async {
    final cmd = _commandController.text.trim();
    if (cmd.isEmpty) return;
    _commandController.clear();
    await _executeAssistantCommand(cmd);
  }

  void _startChatTopSweepOnce() {
    if (_chatBorderStarted) return;
    _chatBorderStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _chatBorderPulse
        ..stop()
        ..reset()
        ..forward();
    });
  }

  Widget _buildChatTopSweepBorder() {
    return IgnorePointer(
      child: SizedBox(
        height: 10,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final inset = 9.0;
            final radiusCut = 8.0;
            final left = inset + radiusCut;
            final right = constraints.maxWidth - inset - radiusCut;
            final track = (right - left).clamp(0.0, constraints.maxWidth);
            final segment = track * 0.24;

            return Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                Positioned(
                  left: left,
                  right: constraints.maxWidth - right,
                  top: 0.8,
                  child: Container(
                    height: 2.4,
                    decoration: BoxDecoration(
                      color: EaColor.back,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                AnimatedBuilder(
                  animation: _chatBorderPulse,
                  builder: (context, child) {
                    if (track <= 0) return const SizedBox.shrink();
                    final p = Curves.easeOutCubic.transform(
                      _chatBorderPulse.value.clamp(0.0, 1.0),
                    );
                    if (p >= 1) return const SizedBox.shrink();

                    final grow = (p / 0.14).clamp(0.0, 1.0);
                    final shrink = ((1.0 - p) / 0.18).clamp(0.0, 1.0);
                    final sizeFactor = (grow < shrink ? grow : shrink)
                        .toDouble();
                    final dynamicSegment = (segment * sizeFactor)
                        .clamp(0.0, segment)
                        .toDouble();
                    if (dynamicSegment <= 0.8) return const SizedBox.shrink();

                    final head = p * track;
                    final segLeft = (head - dynamicSegment).clamp(
                      0.0,
                      track - dynamicSegment,
                    );

                    return Positioned(
                      left: left + segLeft,
                      top: 0.3,
                      child: Container(
                        width: dynamicSegment,
                        height: 2.0,
                        decoration: BoxDecoration(
                          color: EaColor.fore,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            BoxShadow(
                              color: EaColor.fore,
                              blurRadius: 6,
                              spreadRadius: .2,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildChatPanel(double panelHeight) {
    const filteredPrompts = <String>[];
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      height: panelHeight,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: BoxDecoration(
                color: EaColor.back.withValues(alpha: .95),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.transparent),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 22,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Chat',
                        style: EaText.primary.copyWith(fontSize: 17),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: _assistantThinking
                            ? RotationTransition(
                                turns: _thinkingController,
                                child: const Icon(
                                  Icons.autorenew,
                                  size: 15,
                                  color: EaColor.fore,
                                ),
                              )
                            : AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                width: _isRecordingAudio ? 9 : 7,
                                height: _isRecordingAudio ? 9 : 7,
                                decoration: BoxDecoration(
                                  color: _isRecordingAudio
                                      ? Colors.redAccent
                                      : EaColor.fore,
                                  shape: BoxShape.circle,
                                ),
                              ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _assistantThinking
                            ? 'Thinking...'
                            : (_isRecordingAudio ? 'Listening...' : 'Online'),
                        style: EaText.secondaryTranslucent,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: filteredPrompts.isEmpty
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: filteredPrompts
                                    .map(
                                      (p) => Padding(
                                        padding: const EdgeInsets.only(
                                          right: 6,
                                        ),
                                        child: ActionChip(
                                          label: Text(
                                            p,
                                            style: EaText.secondaryTranslucent,
                                          ),
                                          onPressed: () => _runQuickPrompt(p),
                                          side: const BorderSide(
                                            color: EaColor.border,
                                          ),
                                          backgroundColor:
                                              EaColor.secondaryBack,
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          ),
                  ),
                  TextField(
                    controller: _commandController,
                    minLines: 1,
                    maxLines: 1,
                    textInputAction: TextInputAction.send,
                    cursorColor: EaColor.fore,
                    onSubmitted: (_) => _submitCurrentCommand(),
                    style: EaText.secondary.copyWith(
                      color: EaColor.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: _isRecordingAudio
                          ? 'Listening... speak now'
                          : 'Ask anything about your home…',
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
                        child: EaGradientButtonFrame(
                          borderRadius: BorderRadius.circular(12),
                          child: ElevatedButton.icon(
                            onPressed: _submitCurrentCommand,
                            icon: const Icon(Icons.send_rounded),
                            label: const Text('Send'),
                            style: EaButtonStyle.gradientFilled(
                              context: context,
                              borderRadius: BorderRadius.circular(12),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _toggleAudioCapture,
                        icon: Icon(
                          _isRecordingAudio ? Icons.stop_circle : Icons.mic,
                        ),
                        label: Text(_isRecordingAudio ? 'Stop' : 'Rec'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: EaColor.fore,
                          side: const BorderSide(color: EaColor.fore),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                      decoration: BoxDecoration(
                        color: EaColor.secondaryBack,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: EaColor.border),
                      ),
                      child: ListView.builder(
                        controller: _chatScrollController,
                        itemCount: _chatMessages.length,
                        itemBuilder: (_, i) {
                          final m = _chatMessages[i];
                          final isUser = m.role == _ChatRole.user;
                          final isTypingTail =
                              !isUser &&
                              i == _chatMessages.length - 1 &&
                              (_chatTypingTimer?.isActive ?? false);

                          return Align(
                            alignment: isUser
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              constraints: const BoxConstraints(maxWidth: 290),
                              decoration: BoxDecoration(
                                color: isUser
                                    ? EaColor.fore.withValues(alpha: .88)
                                    : EaColor.back.withValues(alpha: .85),
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(12),
                                  topRight: const Radius.circular(12),
                                  bottomLeft: Radius.circular(isUser ? 12 : 4),
                                  bottomRight: Radius.circular(isUser ? 4 : 12),
                                ),
                              ),
                              child: RichText(
                                text: TextSpan(
                                  style: EaText.secondary.copyWith(
                                    color: isUser
                                        ? Colors.black
                                        : EaColor.textSecondary,
                                    fontSize: 12,
                                  ),
                                  children: [
                                    TextSpan(text: m.text),
                                    if (isTypingTail)
                                      TextSpan(
                                        text: ' ▌',
                                        style: EaText.secondary.copyWith(
                                          color: EaColor.fore,
                                          fontSize: 12,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: _buildChatTopSweepBorder(),
            ),
          ],
        ),
      ),
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
              const Icon(
                Icons.error_outline,
                color: Colors.redAccent,
                size: 34,
              ),
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

    _startChatTopSweepOnce();

    final dataTiles = _assistantDataTiles();
    final annotations = _annotationModels();
    final screenHeight = MediaQuery.sizeOf(context).height;
    final chatPanelHeight = (screenHeight * 0.34)
        .clamp(270.0, 420.0)
        .toDouble();

    return SafeArea(
      child: Stack(
        children: [
          SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 10, 16, chatPanelHeight + 44),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Assistant Data',
                  style: EaText.primary.copyWith(fontSize: 18),
                ),
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
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Outside temperature',
                              style: EaText.secondary,
                            ),
                          ),
                          Spacer(),
                          IconButton(
                            onPressed:
                                (_useWeatherData &&
                                    _locationQuery.trim().isNotEmpty)
                                ? _fetchOutsideTemperature
                                : null,
                            icon: const Icon(Icons.refresh_rounded, size: 25),
                            color: EaColor.fore,
                          ),
                        ],
                      ),

                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(width: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _weatherIconForTemp(),
                                color: EaColor.fore,
                                size: 20,
                              ),
                              const SizedBox(width: 6),
                              if (_weatherLoading)
                                const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: EaColor.fore,
                                  ),
                                )
                              else
                                Text(
                                  '${_outsideTemp.toStringAsFixed(0)}°C',
                                  style: EaText.primary.copyWith(
                                    fontSize: 25,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                            ],
                          ),
                          SizedBox(width: 18),
                          Flexible(
                            fit: FlexFit.loose,
                            child: TextButton.icon(
                              onPressed: _useLocationData
                                  ? _promptForLocation
                                  : null,
                              icon: const Icon(Icons.place_outlined, size: 18),
                              label: Text(
                                _locationQuery.trim().isEmpty
                                    ? 'Set location'
                                    : _locationQuery,
                                overflow: TextOverflow.ellipsis,
                                style: EaText.secondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(
                        height: 132,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onHorizontalDragStart: _onAssistantDataDragStart,
                          onHorizontalDragUpdate: _onAssistantDataDragUpdate,
                          onHorizontalDragEnd: _onAssistantDataDragEnd,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeIn,
                            transitionBuilder: (child, anim) {
                              return FadeTransition(
                                opacity: CurvedAnimation(
                                  parent: anim,
                                  curve: Curves.easeOut,
                                ),
                                child: child,
                              );
                            },
                            child: KeyedSubtree(
                              key: ValueKey(
                                'assistant-data-${_assistantDataIndex % dataTiles.length}',
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                child:
                                    dataTiles[_assistantDataIndex %
                                        dataTiles.length],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(dataTiles.length, (i) {
                          final active =
                              i == (_assistantDataIndex % dataTiles.length);
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
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Annotations',
                        style: EaText.primary.copyWith(fontSize: 18),
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          _showAllAnnotationsBottomSheet(annotations),
                      child: Text(
                        'View details',
                        style: EaText.secondary.copyWith(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 114,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragStart: _onAnnotationDragStart,
                    onHorizontalDragUpdate: _onAnnotationDragUpdate,
                    onHorizontalDragEnd: _onAnnotationDragEnd,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, anim) {
                        final fromRight = _annotationSlideDir > 0;
                        final begin = Offset(fromRight ? 0.18 : -0.18, 0);
                        return FadeTransition(
                          opacity: CurvedAnimation(
                            parent: anim,
                            curve: Curves.easeOut,
                          ),
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: begin,
                              end: Offset.zero,
                            ).animate(anim),
                            child: child,
                          ),
                        );
                      },
                      child: KeyedSubtree(
                        key: ValueKey(
                          'annotation-${_annotationIndex % annotations.length}',
                        ),
                        child: Builder(
                          builder: (_) {
                            final a =
                                annotations[_annotationIndex %
                                    annotations.length];
                            return _card(
                              icon: a.icon,
                              title: a.title,
                              description: a.description,
                              trailing: a.onApply == null
                                  ? null
                                  : TextButton(
                                      onPressed: a.onApply,
                                      child: Text(
                                        a.actionLabel ?? 'Apply',
                                        style: EaText.accent,
                                      ),
                                    ),
                            );
                          },
                        ),
                      ),
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
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                  child: Container(
                    height: (chatPanelHeight * 0.62)
                        .clamp(140.0, 230.0)
                        .toDouble(),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          EaColor.back.withValues(alpha: 0.0),
                          EaColor.back.withValues(alpha: 0.72),
                          EaColor.back.withValues(alpha: 0.96),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 10,
            child: _buildChatPanel(chatPanelHeight),
          ),
        ],
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

enum _ChatRole { user, assistant }

class _ChatMessage {
  final _ChatRole role;
  final String text;

  const _ChatMessage({required this.role, required this.text});
}
