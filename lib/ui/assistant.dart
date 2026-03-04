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

  String? _generalResponse(String text) {
    final q = text.toLowerCase();

    if (_containsAny(q, ['thanks', 'thank you', 'thx', 'appreciate it'])) {
      const replies = [
        'You\'re very welcome!',
        'Anytime — happy to help.',
        'My pleasure. Want me to optimize something else?',
        'Of course! Always here for you.',
      ];
      return '${_friendlyPrefix()} ${replies[_rng.nextInt(replies.length)]}';
    }
    if (_containsAny(q, ['how are you', 'how is it going', 'how\'s it going', 'you good'])) {
      const replies = [
        'I\'m doing great and ready to help.',
        'I\'m excellent — systems online and focused.',
        'All good here. Want a quick status of your home?',
      ];
      return replies[_rng.nextInt(replies.length)];
    }
    if (_containsAny(q, ['good morning', 'good afternoon', 'good evening', 'hello', 'hi'])) {
      return _greetingResponse();
    }
    if (_containsAny(q, ['bye', 'good night', 'see you', 'talk later'])) {
      return 'See you soon. I\'ll keep learning your routines in the meantime.';
    }
    if (_containsAny(q, ['who are you', 'what are you'])) {
      return 'I\'m your EaSync Assistant. I can automate devices, apply scenes, and learn your routine patterns.';
    }
    if (_containsAny(q, ['what can you do', 'help', 'capabilities'])) {
      return 'I can control power, temperature, brightness, color, mode and position. Example: "turn on AC and set temperature 23".';
    }
    if (_containsAny(q, ['what time', 'time now'])) {
      final now = DateTime.now();
      return 'Current time is ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}.';
    }
    if (_containsAny(q, ['what day', 'today date', 'date today'])) {
      final now = DateTime.now();
      return 'Today is ${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}.';
    }
    if (_containsAny(q, ['outside temperature', 'weather', 'how hot'])) {
      return 'Outside is around ${_outsideTemp.toStringAsFixed(0)}°C near ${_locationQuery.isEmpty ? 'your saved area' : _locationQuery}.';
    }
    if (_containsAny(q, ['what should i do', 'any suggestion', 'recommend something'])) {
      return 'I suggest enabling Auto-arrival and running a comfort profile before your usual arrival hour.';
    }
    if (_containsAny(q, ['what did you learn', 'what have you learned', 'learning summary'])) {
      return 'I\'m learning that your activity peaks around ${_hourLabel(_topHour(_appOpenByHour))} and arrival-like usage is around ${_hourLabel(_topHour(_powerOnByHour))}.';
    }
    if (_containsAny(q, ['good job', 'nice', 'great'])) {
      return 'That\'s great! I appreciate it. Want me to run a quick home optimization?';
    }
    if (q.endsWith('?')) {
      return 'Of course! I can help with that. If this is about devices, tell me the room/device and what you want to change.';
    }
    return null;
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
      _chatMessages.add(const _ChatMessage(role: _ChatRole.assistant, text: ''));
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

  bool _containsAny(String text, List<String> words) {
    for (final w in words) {
      if (text.contains(w)) return true;
    }
    return false;
  }

  bool _containsAnyPhrase(String text, List<String> phrases) {
    for (final p in phrases) {
      if (text.contains(p)) return true;
      final tokens = p.split(' ').where((e) => e.trim().isNotEmpty).toList();
      if (tokens.length >= 2 && tokens.every(text.contains)) return true;
    }
    return false;
  }

  bool _isLikelyStateQuestion(String text) {
    final q = _normalizeInput(text);
    final questionLike = q.contains('?') ||
        _containsAnyPhrase(q, [
          'is ',
          'are ',
          'what ',
          'which ',
          'qual ',
          'quais ',
          'como ',
          'quanto ',
          'que ',
          'ela ',
          'ele ',
        ]);
    if (!questionLike) return false;

    final explicitAction = _containsAnyPhrase(q, [
      'turn on',
      'turn off',
      'set ',
      'ligar ',
      'desligar ',
      'liga ',
      'desliga ',
      'ajuste ',
      'defina ',
      'mude ',
    ]);
    if (explicitAction) return false;

    return _containsAnyPhrase(q, [
      'status',
      'state',
      'on',
      'off',
      'temperature',
      'temp',
      'color',
      'brightness',
      'position',
      'opened',
      'closed',
      'online',
      'mode',
      'lock',
      'ligado',
      'desligado',
      'temperatura',
      'cor',
      'brilho',
      'posicao',
      'aberto',
      'fechado',
      'trancado',
      'destrancado',
    ]);
  }

  DeviceInfo? _findDeviceFromText(String text, List<DeviceInfo> devices) {
    if (devices.isEmpty) return null;
    final q = _normalizeInput(text);

    DeviceInfo? best;
    var bestScore = 0;
    for (final d in devices) {
      final name = _normalizeInput(d.name);
      final brand = _normalizeInput(d.brand);
      final model = _normalizeInput(d.model);
      final hay = '$name $brand $model';

      if (q.contains(name) && name.trim().isNotEmpty) {
        _lastReferencedDeviceId = d.uuid;
        return d;
      }

      final words = q.split(RegExp(r'\s+')).where((w) => w.length > 2).toList();
      var score = 0;
      for (final w in words) {
        if (hay.contains(w)) score++;
      }
      if (score > bestScore) {
        best = d;
        bestScore = score;
      }
    }

    if (best != null && bestScore >= 2) {
      _lastReferencedDeviceId = best.uuid;
      return best;
    }

    List<DeviceInfo> byType(List<String> hints, List<int> caps) {
      return devices.where((d) {
        final hay = _normalizeInput('${d.name} ${d.brand} ${d.model}');
        final hintMatch = hints.any((h) => hay.contains(h));
        final capMatch = caps.any(d.capabilities.contains);
        return hintMatch || capMatch;
      }).toList();
    }

    if (_containsAnyPhrase(q, [
      'lamp',
      'light',
      'lights',
      'luz',
      'lampada',
      'luminaire',
    ])) {
      final lamps = byType(
        ['lamp', 'light', 'luz', 'lampada'],
        [CoreCapability.CORE_CAP_BRIGHTNESS, CoreCapability.CORE_CAP_COLOR],
      );
      if (lamps.length == 1) {
        _lastReferencedDeviceId = lamps.first.uuid;
        return lamps.first;
      }
    }

    if (_containsAnyPhrase(q, [
      'ac',
      'air conditioner',
      'climate',
      'hvac',
      'ar condicionado',
    ])) {
      final acs = byType(
        ['ac', 'air', 'climate', 'hvac', 'ar condicionado'],
        [CoreCapability.CORE_CAP_TEMPERATURE, CoreCapability.CORE_CAP_MODE],
      );
      if (acs.length == 1) {
        _lastReferencedDeviceId = acs.first.uuid;
        return acs.first;
      }
    }

    if (_containsAnyPhrase(q, [
      'curtain',
      'blind',
      'shade',
      'cortina',
      'persiana',
    ])) {
      final curtains = byType(
        ['curtain', 'blind', 'shade', 'cortina', 'persiana'],
        [CoreCapability.CORE_CAP_POSITION],
      );
      if (curtains.length == 1) {
        _lastReferencedDeviceId = curtains.first.uuid;
        return curtains.first;
      }
    }

    if (_containsAnyPhrase(q, [
      'ela esta ligada',
      'ele esta ligado',
      'it is on',
      'is it on',
      'this device',
      'that device',
      'esse dispositivo',
      'essa lampada',
      'este aparelho',
    ])) {
      final remembered = _lastReferencedDeviceId;
      if (remembered != null) {
        for (final d in devices) {
          if (d.uuid == remembered) return d;
        }
      }
    }

    return null;
  }

  bool _isDeviceLikelyOnline(DeviceInfo d) {
    final h = Bridge.health(d.uuid);
    if (h.lastSeen == null) return false;
    if (h.consecutiveFailures >= 4) return false;
    final age = DateTime.now().difference(h.lastSeen!).inMinutes;
    return age <= 20;
  }

  String _colorName(int color) {
    final rgb = color & 0x00FFFFFF;
    final known = <String, int>{
      'white': 0x00F5F5F5,
      'blue': 0x000066FF,
      'light blue': 0x0000FFFF,
      'dark blue': 0x000000FF,
      'green': 0x0000C853,
      'light green': 0x0090EE90,
      'dark green': 0x00008700,
      'red': 0x00E53935,
      'light red': 0x00FF6E64,
      'dark red': 0x00B71C1C,
      'purple': 0x009C27B0,
      'light purple': 0x009932CC,
      'dark purple': 0x0065117A,
      'pink': 0x00EC407A,
      'light pink': 0x00FF80AB,
      'dark pink': 0x00B0003A,
      'violet': 0x008A2BE2,
      'indigo': 0x004B0082,
      'brown': 0x008B4513,
      'black': 0x00000000,
      'gray': 0x00808080,
      'silver': 0x00C0C0C0,
      'gold': 0x00FFD700,
      'yellow': 0x00FFD600,
      'light yellow': 0x00FFFF99,
      'dark yellow': 0x00B2A100,
      'orange': 0x00FB8C00,
      'light orange': 0x00FFA500,
      'dark orange': 0x00B26A00,
      'cyan': 0x0000BCD4,
    };

    String nearest = 'custom';
    var bestDist = 1 << 30;
    for (final e in known.entries) {
      final c = e.value;
      final dr = ((rgb >> 16) & 0xFF) - ((c >> 16) & 0xFF);
      final dg = ((rgb >> 8) & 0xFF) - ((c >> 8) & 0xFF);
      final db = (rgb & 0xFF) - (c & 0xFF);
      final dist = dr * dr + dg * dg + db * db;
      if (dist < bestDist) {
        bestDist = dist;
        nearest = e.key;
      }
    }
    return nearest;
  }

  String _positionLabel(double position) {
    if (position <= 1) return 'closed (0%)';
    if (position >= 99) return 'opened (100%)';
    return '${position.toStringAsFixed(0)}%';
  }

  String _deviceStateSnapshot(DeviceInfo target, DeviceState state) {
    final parts = <String>[];

    if (target.capabilities.contains(CoreCapability.CORE_CAP_POWER)) {
      parts.add('power ${state.power ? 'ON' : 'OFF'}');
    }
    if (target.capabilities.contains(CoreCapability.CORE_CAP_TEMPERATURE)) {
      parts.add('temperature ${state.temperature.toStringAsFixed(0)}°C');
    }
    if (target.capabilities.contains(CoreCapability.CORE_CAP_BRIGHTNESS)) {
      parts.add('brightness ${state.brightness}%');
    }
    if (target.capabilities.contains(CoreCapability.CORE_CAP_COLOR)) {
      final raw = state.color & 0x00FFFFFF;
      final hex = raw.toRadixString(16).padLeft(6, '0').toUpperCase();
      parts.add('color ${_colorName(state.color)} (#$hex)');
    }
    if (target.capabilities.contains(CoreCapability.CORE_CAP_POSITION)) {
      parts.add('position ${_positionLabel(state.position)}');
    }
    if (target.capabilities.contains(CoreCapability.CORE_CAP_MODE)) {
      final modeName = Bridge.modeName(target.uuid, state.mode);
      parts.add('mode $modeName');
    }
    if (target.capabilities.contains(CoreCapability.CORE_CAP_LOCK)) {
      parts.add('lock ${state.lock ? 'locked' : 'unlocked'}');
    }

    if (parts.isEmpty) return '${target.name} has no readable state.';
    return '${target.name}: ${parts.join(' • ')}.';
  }

  Set<int> _requiredCapabilitiesForClause(String clause) {
    final caps = <int>{};
    if (clause.contains('brightness')) caps.add(CoreCapability.CORE_CAP_BRIGHTNESS);
    if (clause.contains('color')) caps.add(CoreCapability.CORE_CAP_COLOR);
    if (clause.contains('temperature') || clause.contains('temp')) {
      caps.add(CoreCapability.CORE_CAP_TEMPERATURE);
    }
    if (clause.contains('mode')) caps.add(CoreCapability.CORE_CAP_MODE);
    if (clause.contains('position') || clause.contains('open') || clause.contains('close')) {
      caps.add(CoreCapability.CORE_CAP_POSITION);
    }
    if (clause.contains('turn on') || clause.contains('turn off')) {
      caps.add(CoreCapability.CORE_CAP_POWER);
    }
    return caps;
  }

  List<DeviceInfo> _resolveTargetsForClause(String clause, List<DeviceInfo> devices) {
    final q = clause.toLowerCase();
    final wantsAll = q.contains('all ') || q.contains('every ');
    final mentionsAc = _containsAny(q, [' ac', 'air conditioner', 'climate', 'hvac', 'cooling']);
    final mentionsLight = _containsAny(q, ['lamp', 'light', 'lights']);
    final mentionsCurtain = _containsAny(q, ['curtain', 'curtains', 'blind', 'blinds', 'shade']);

    final explicitByName = devices.where((d) {
      final hay = '${d.name} ${d.brand} ${d.model}'.toLowerCase();
      if (q.contains(d.name.toLowerCase())) return true;
      final words = q.split(RegExp(r'\s+')).where((e) => e.length > 2);
      final score = words.where((w) => hay.contains(w)).length;
      return score >= 2;
    }).toList();

    if (explicitByName.isNotEmpty) {
      return wantsAll ? explicitByName : [explicitByName.first];
    }

    if (mentionsAc) {
      final acs = devices.where((d) {
        final hay = '${d.name} ${d.brand} ${d.model}'.toLowerCase();
        final capOk = d.capabilities.contains(CoreCapability.CORE_CAP_TEMPERATURE) ||
            d.capabilities.contains(CoreCapability.CORE_CAP_MODE);
        return capOk || hay.contains('ac') || hay.contains('air') || hay.contains('climate');
      }).toList();
      return acs;
    }

    if (mentionsLight) {
      final lights = devices.where((d) {
        final hay = '${d.name} ${d.brand} ${d.model}'.toLowerCase();
        return d.capabilities.contains(CoreCapability.CORE_CAP_BRIGHTNESS) ||
            d.capabilities.contains(CoreCapability.CORE_CAP_COLOR) ||
            hay.contains('lamp') ||
            hay.contains('light');
      }).toList();
      return lights;
    }

    if (mentionsCurtain) {
      final curtains = devices
          .where((d) => d.capabilities.contains(CoreCapability.CORE_CAP_POSITION))
          .toList();
      return curtains;
    }

    final required = _requiredCapabilitiesForClause(q);
    if (required.isNotEmpty) {
      final matches = devices.where((d) {
        for (final cap in required) {
          if (!d.capabilities.contains(cap)) return false;
        }
        return true;
      }).toList();
      if (matches.isNotEmpty) return matches;

      // Relax when no full match exists.
      final soft = devices.where((d) {
        for (final cap in required) {
          if (d.capabilities.contains(cap)) return true;
        }
        return false;
      }).toList();
      if (soft.isNotEmpty) return soft;

      return [];
    }

    if (wantsAll) {
      final powerDevices = devices
          .where((d) => d.capabilities.contains(CoreCapability.CORE_CAP_POWER))
          .toList();
      return powerDevices;
    }

    return devices.isEmpty ? [] : [devices.first];
  }

  String _friendlyPrefix() {
    const options = [
      'Of course!',
      'That\'s great!',
      'Absolutely!',
      'Done nicely!',
      'Perfect, on it!',
    ];
    return options[_rng.nextInt(options.length)];
  }

  String _targetHint(String clause) {
    final q = clause.toLowerCase();
    if (_containsAny(q, [' ac', 'air conditioner', 'climate', 'hvac'])) return 'AC';
    if (_containsAny(q, ['lamp', 'light', 'lights'])) return 'light';
    if (_containsAny(q, ['curtain', 'blind', 'shade'])) return 'curtain';
    return 'matching device';
  }

  DeviceInfo? _resolvePendingChoice(String text) {
    if (_pendingTargets.isEmpty) return null;
    final q = text.toLowerCase();

    for (final d in _pendingTargets) {
      if (q.contains(d.name.toLowerCase())) return d;
    }

    if (_containsAny(q, ['first', '1st', 'one', '1'])) {
      return _pendingTargets.first;
    }
    if (_pendingTargets.length > 1 && _containsAny(q, ['second', '2nd', 'two', '2'])) {
      return _pendingTargets[1];
    }
    if (_pendingTargets.length > 2 && _containsAny(q, ['third', '3rd', 'three', '3'])) {
      return _pendingTargets[2];
    }

    return null;
  }

  IconData _weatherIconForTemp() {
    if (_outsideTemp >= 31) return Icons.wb_sunny;
    if (_outsideTemp >= 26) return Icons.wb_sunny_outlined;
    if (_outsideTemp >= 20) return Icons.cloud_outlined;
    return Icons.ac_unit;
  }

  List<int> _capabilitiesFromQuery(String q) {
    final out = <int>[];
    if (_containsAny(q, ['power', 'on/off', 'turn on', 'turn off'])) {
      out.add(CoreCapability.CORE_CAP_POWER);
    }
    if (_containsAny(q, ['temperature', 'temp', 'climate'])) {
      out.add(CoreCapability.CORE_CAP_TEMPERATURE);
    }
    if (_containsAny(q, ['brightness', 'dimmer'])) {
      out.add(CoreCapability.CORE_CAP_BRIGHTNESS);
    }
    if (_containsAny(q, ['color', 'colour'])) {
      out.add(CoreCapability.CORE_CAP_COLOR);
    }
    if (_containsAny(q, ['mode'])) {
      out.add(CoreCapability.CORE_CAP_MODE);
    }
    if (_containsAny(q, ['position', 'open', 'close', 'curtain', 'blind'])) {
      out.add(CoreCapability.CORE_CAP_POSITION);
    }
    return out;
  }

  String _capabilityName(int cap) {
    if (cap == CoreCapability.CORE_CAP_POWER) return 'power';
    if (cap == CoreCapability.CORE_CAP_TEMPERATURE) return 'temperature';
    if (cap == CoreCapability.CORE_CAP_BRIGHTNESS) return 'brightness';
    if (cap == CoreCapability.CORE_CAP_COLOR) return 'color';
    if (cap == CoreCapability.CORE_CAP_MODE) return 'mode';
    if (cap == CoreCapability.CORE_CAP_POSITION) return 'position';
    return 'unknown';
  }

  String? _informationalDevicesResponse(String text, List<DeviceInfo> devices) {
    final q = text.toLowerCase();

    final asksInventory = _containsAnyPhrase(q, [
      'what devices',
      'list devices',
      'which devices',
      'devices available',
      'what devices do i have',
      'which devices do i have',
      'show my devices',
      'quais devices',
      'quais dispositivos',
      'que dispositivos eu tenho',
      'quais aparelhos eu tenho',
      'devices tem',
      'devices tenho',
      'lista de dispositivos',
      'meus devices',
      'meus dispositivos',
      'o que eu tenho conectado',
    ]);

    if (asksInventory) {
      if (devices.isEmpty) return 'No devices are registered right now.';
      final names = devices.take(12).map((d) => d.name).join(', ');
      return 'You currently have ${devices.length} device(s): $names${devices.length > 12 ? '...' : ''}.';
    }

    final asksOnline = _containsAnyPhrase(q, [
      'online devices',
      'which devices are online',
      'who is online',
      'what is online',
      'quais devices estao online',
      'quais dispositivos estao online',
      'dispositivos online',
      'aparelhos online',
      'quem esta online',
      'o que esta online',
    ]);

    if (asksOnline) {
      if (devices.isEmpty) return 'No devices are registered right now.';
      final online = devices.where(_isDeviceLikelyOnline).toList();
      if (online.isEmpty) {
        return 'I cannot confirm online devices right now. Try again after device activity refresh.';
      }
      final names = online.take(12).map((d) => d.name).join(', ');
      return 'Online now (${online.length}/${devices.length}): $names${online.length > 12 ? '...' : ''}.';
    }

    final asksPowerState = _containsAnyPhrase(q, [
      'is it on',
      'is it off',
      'is on',
      'is off',
      'turned on',
      'turned off',
      'power status',
      'status of',
      'ela esta ligada',
      'ele esta ligado',
      'esta ligado',
      'esta ligada',
      'esta desligado',
      'esta desligada',
      'ligado ou desligado',
      'estado de energia',
      'status da lampada',
      'status do device',
      'status do dispositivo',
      'device status',
      'state of',
    ]);

    final asksColorState = _containsAnyPhrase(q, [
      'what color',
      'which color',
      'current color',
      'color of',
      'que cor',
      'qual cor',
      'cor atual',
      'de que cor',
      'cor da',
      'cor do',
    ]);

    final asksTempState = _containsAnyPhrase(q, [
      'temperature',
      'temp',
      'current temp',
      'temperatura',
      'qual a temperatura',
      'quanto esta a temperatura',
      'em c',
      'em °c',
      'celsius',
      'graus',
      '°c',
    ]);

    final asksBrightnessState = _containsAnyPhrase(q, [
      'brightness',
      'brilho',
      'dimmer',
      'intensity',
      'intensidade',
      'percent',
      'porcentagem',
      '%',
    ]);

    final asksPositionState = _containsAnyPhrase(q, [
      'position',
      'opened',
      'closed',
      'aberta',
      'fechada',
      'aberto',
      'fechado',
      'percentual',
      'posição',
      'posicao',
      '%',
    ]);

    final asksModeState = _containsAnyPhrase(q, [
      'mode',
      'modo',
      'which mode',
      'qual modo',
    ]);

    final asksLockState = _containsAnyPhrase(q, [
      'lock status',
      'locked',
      'unlocked',
      'trancada',
      'destrancada',
      'fechadura',
    ]);

    final asksGenericState = _containsAnyPhrase(q, [
      'status',
      'state',
      'estado',
      'como esta',
      'como está',
      'situation of',
    ]);

    if (asksPowerState ||
        asksColorState ||
        asksTempState ||
        asksBrightnessState ||
        asksPositionState ||
        asksModeState ||
        asksLockState ||
        asksGenericState) {
      final target = _findDeviceFromText(q, devices);
      if (target == null) {
        return 'Tell me the device/type, for example: "is Living Room Lamp on?", "what is AC temperature?", or "curtain position?".';
      }
      _lastReferencedDeviceId = target.uuid;

      DeviceState state;
      try {
        state = Bridge.getState(target.uuid);
      } catch (_) {
        return 'I could not read the current state for ${target.name} right now.';
      }

      if (asksColorState) {
        if (!target.capabilities.contains(CoreCapability.CORE_CAP_COLOR)) {
          return '${target.name} does not support color control.';
        }
        final raw = state.color & 0x00FFFFFF;
        final hex = raw.toRadixString(16).padLeft(6, '0').toUpperCase();
        return '${target.name} is currently ${_colorName(state.color)} (#$hex).';
      }

      if (asksTempState) {
        if (!target.capabilities.contains(CoreCapability.CORE_CAP_TEMPERATURE)) {
          return '${target.name} does not expose temperature.';
        }
        return '${target.name} temperature is ${state.temperature.toStringAsFixed(0)}°C.';
      }

      if (asksBrightnessState) {
        if (!target.capabilities.contains(CoreCapability.CORE_CAP_BRIGHTNESS)) {
          return '${target.name} does not expose brightness percentage.';
        }
        return '${target.name} brightness is ${state.brightness}%.';
      }

      if (asksPositionState) {
        if (!target.capabilities.contains(CoreCapability.CORE_CAP_POSITION)) {
          return '${target.name} does not expose position state.';
        }
        return '${target.name} position is ${_positionLabel(state.position)}.';
      }

      if (asksModeState) {
        if (!target.capabilities.contains(CoreCapability.CORE_CAP_MODE)) {
          return '${target.name} does not expose mode.';
        }
        return '${target.name} mode is ${Bridge.modeName(target.uuid, state.mode)}.';
      }

      if (asksLockState) {
        if (!target.capabilities.contains(CoreCapability.CORE_CAP_LOCK)) {
          return '${target.name} does not expose lock state.';
        }
        return '${target.name} is currently ${state.lock ? 'locked' : 'unlocked'}.';
      }

      if (asksGenericState) {
        return _deviceStateSnapshot(target, state);
      }

      if (!target.capabilities.contains(CoreCapability.CORE_CAP_POWER)) {
        return '${target.name} does not expose power state.';
      }
      return '${target.name} is currently ${state.power ? 'ON' : 'OFF'}.';
    }

    if (_containsAny(q, ['what devices', 'list devices', 'which devices', 'devices available'])) {
      if (devices.isEmpty) return 'No devices are registered right now.';
      final names = devices.take(8).map((d) => d.name).join(', ');
      return 'You currently have ${devices.length} device(s): $names${devices.length > 8 ? '...' : ''}.';
    }

    if (_containsAny(q, ['capability', 'capabilities', 'which supports', 'which have'])) {
      final askedCaps = _capabilitiesFromQuery(q);
      if (askedCaps.isEmpty) {
        return 'Ask me like: "which devices support temperature" or "which devices have brightness".';
      }
      final cap = askedCaps.first;
      final matches = devices
          .where((d) => d.capabilities.contains(cap))
          .map((d) => d.name)
          .toList();
      if (matches.isEmpty) {
        return 'No device with ${_capabilityName(cap)} capability was found.';
      }
      return 'Devices with ${_capabilityName(cap)}: ${matches.join(', ')}.';
    }

    return null;
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
    _lastReferencedDeviceId = target.uuid;
    DeviceState? currentState;
    try {
      currentState = Bridge.getState(target.uuid);
    } catch (_) {}

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
      actions.add('set brightness to $pct% on ${target.name}');
      _pushCommandLog('Brightness $pct% → ${target.name}');
    }

    if ((clause.contains('temperature') || clause.contains('temp')) &&
        target.capabilities.contains(CoreCapability.CORE_CAP_TEMPERATURE)) {
      if (target.capabilities.contains(CoreCapability.CORE_CAP_POWER) &&
          currentState != null &&
          !currentState.power) {
        Bridge.setPower(target.uuid, true);
        actions.add('turned on ${target.name}');
        _pushCommandLog('Auto power ON for temperature → ${target.name}');
      }
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

  DeviceInfo? _temperatureTargetFromText(String input, List<DeviceInfo> devices) {
    if (devices.isEmpty) return null;

    bool hasAnyTempCap(DeviceInfo d) {
      return d.capabilities.contains(CoreCapability.CORE_CAP_TEMPERATURE) ||
          d.capabilities.contains(CoreCapability.CORE_CAP_TEMPERATURE_FRIDGE) ||
          d.capabilities.contains(CoreCapability.CORE_CAP_TEMPERATURE_FREEZER);
    }

    final byName = _findDeviceFromText(input, devices);
    if (byName != null && hasAnyTempCap(byName)) {
      return byName;
    }

    final q = _normalizeInput(input);
    final asksColdDevice = _containsAny(q, [
      'fridge',
      'freezer',
      'geladeira',
      'congelador',
      'refrigerator',
    ]);

    final tempDevices = devices
      .where(hasAnyTempCap)
        .toList();
    if (tempDevices.isEmpty) return null;

    if (asksColdDevice) {
      for (final d in tempDevices) {
        final n = d.name.toLowerCase();
        if (n.contains('fridge') ||
            n.contains('freezer') ||
            n.contains('geladeira') ||
            n.contains('congelador') ||
            n.contains('refrigerator')) {
          return d;
        }
      }
    }

    return tempDevices.first;
  }

  String? _localNlpFallback(String input) {
    final q = _normalizeInput(input);
    final devices = Bridge.listDevices();

    final asksInventory = _containsAnyPhrase(q, [
      'what are my devices',
      'what devices do i have',
      'list my devices',
      'list devices',
      'which devices',
      'devices available',
      'my devices',
      'quais dispositivos',
      'listar dispositivos',
    ]);

    if (asksInventory) {
      if (devices.isEmpty) return 'No devices are currently available.';
      final names = devices.map((d) => d.name).toList();
      return 'Devices (${names.length}): ${names.join(', ')}';
    }

    final asksPosition = _containsAny(q, [
      'position',
      'posicao',
      'curtain',
      'curtains',
      'blind',
      'blinds',
      'shade',
      'open',
      'close',
    ]);

    if (asksPosition) {
      final rows = <String>[];
      for (final d in devices) {
        if (!d.capabilities.contains(CoreCapability.CORE_CAP_POSITION)) continue;
        final s = Bridge.getState(d.uuid);
        rows.add('${d.name} ${s.position.toStringAsFixed(0)}%');
      }
      if (rows.isNotEmpty) {
        return 'Position: ${rows.join(', ')}';
      }
    }

    final asksBrightness = _containsAny(q, ['brightness', 'brilho']);
    if (asksBrightness) {
      final rows = <String>[];
      for (final d in devices) {
        if (!d.capabilities.contains(CoreCapability.CORE_CAP_BRIGHTNESS)) continue;
        final s = Bridge.getState(d.uuid);
        rows.add('${d.name} ${s.brightness}%');
      }
      if (rows.isNotEmpty) {
        return 'Brightness: ${rows.join(', ')}';
      }
    }

    final asksPower = _containsAny(q, [' power', 'turned on', 'is on', 'is off', 'ligado', 'desligado']);
    if (asksPower) {
      final target = _findDeviceFromText(q, devices);
      if (target != null && target.capabilities.contains(CoreCapability.CORE_CAP_POWER)) {
        final s = Bridge.getState(target.uuid);
        return s.power
            ? 'Yes. ${target.name} is ON.'
            : 'No. ${target.name} is OFF at this moment.';
      }
      int onCount = 0;
      for (final d in devices) {
        if (!d.capabilities.contains(CoreCapability.CORE_CAP_POWER)) continue;
        if (Bridge.getState(d.uuid).power) onCount++;
      }
      if (devices.isNotEmpty) {
        return '$onCount of ${devices.length} devices are ON.';
      }
    }

    final asksLock = _containsAny(q, ['lock', 'unlock', 'fechadura', 'tranca']);
    if (asksLock) {
      final rows = <String>[];
      for (final d in devices) {
        if (!d.capabilities.contains(CoreCapability.CORE_CAP_LOCK)) continue;
        final s = Bridge.getState(d.uuid);
        rows.add('${d.name} ${s.lock ? 'locked' : 'unlocked'}');
      }
      if (rows.isNotEmpty) {
        return 'Lock state: ${rows.join(', ')}';
      }
    }

    final asksTemperature = _containsAny(q, [
      'temperature',
      'temperatura',
      'temp',
      'tempeature',
      '°c',
    ]);

    if (!asksTemperature) return null;

    final target = _temperatureTargetFromText(q, devices);
    if (target == null) {
      return 'I could not find a temperature-capable device.';
    }

    final setIntent = _containsAnyPhrase(q, [
      'set ',
      'can you set',
      'adjust',
      'change',
      'defina',
      'ajusta',
      'mude',
    ]);

    final value = _extractFirstInt(q);
    if (setIntent && value != null) {
      final n = target.name.toLowerCase();
      final coldDevice = n.contains('fridge') ||
          n.contains('freezer') ||
          n.contains('geladeira') ||
          n.contains('congelador') ||
          n.contains('refrigerator');
      final asksFreezer = _containsAny(q, ['freezer', 'congelador']);
      final asksFridge = _containsAny(q, ['fridge', 'geladeira', 'refrigerator']);

      double temp;
      if ((asksFreezer &&
              target.capabilities
                  .contains(CoreCapability.CORE_CAP_TEMPERATURE_FREEZER)) ||
          (!target.capabilities.contains(CoreCapability.CORE_CAP_TEMPERATURE) &&
              !target.capabilities
                  .contains(CoreCapability.CORE_CAP_TEMPERATURE_FRIDGE) &&
              target.capabilities
                  .contains(CoreCapability.CORE_CAP_TEMPERATURE_FREEZER))) {
        temp = value.clamp(-24, -14).toDouble();
      } else if ((asksFridge &&
              target.capabilities
                  .contains(CoreCapability.CORE_CAP_TEMPERATURE_FRIDGE)) ||
          (!target.capabilities.contains(CoreCapability.CORE_CAP_TEMPERATURE) &&
              target.capabilities
                  .contains(CoreCapability.CORE_CAP_TEMPERATURE_FRIDGE))) {
        temp = value.clamp(1, 8).toDouble();
      } else {
        final minT = coldDevice ? -20 : 16;
        final maxT = coldDevice ? 12 : 30;
        temp = value.clamp(minT, maxT).toDouble();
      }

      if (target.capabilities.contains(CoreCapability.CORE_CAP_POWER)) {
        final before = Bridge.getState(target.uuid);
        if (!before.power) {
          Bridge.setPower(target.uuid, true);
        }
      }

      if (asksFreezer &&
          target.capabilities.contains(CoreCapability.CORE_CAP_TEMPERATURE_FREEZER)) {
        Bridge.setTemperatureFreezer(target.uuid, temp);
      } else if (asksFridge &&
          target.capabilities.contains(CoreCapability.CORE_CAP_TEMPERATURE_FRIDGE)) {
        Bridge.setTemperatureFridge(target.uuid, temp);
      } else if (target.capabilities.contains(CoreCapability.CORE_CAP_TEMPERATURE)) {
        Bridge.setTemperature(target.uuid, temp);
      } else if (target.capabilities
          .contains(CoreCapability.CORE_CAP_TEMPERATURE_FRIDGE)) {
        Bridge.setTemperatureFridge(target.uuid, temp);
      } else if (target.capabilities
          .contains(CoreCapability.CORE_CAP_TEMPERATURE_FREEZER)) {
        Bridge.setTemperatureFreezer(target.uuid, temp);
      }
      return 'Sure! Now ${target.name} is running at ${temp.toStringAsFixed(0)}°C.';
    }

    final state = Bridge.getState(target.uuid);
    if (_containsAny(q, ['freezer', 'congelador']) &&
        target.capabilities.contains(CoreCapability.CORE_CAP_TEMPERATURE_FREEZER)) {
      return '${target.name} freezer temperature is ${state.temperatureFreezer.toStringAsFixed(0)}°C.';
    }
    if (_containsAny(q, ['fridge', 'geladeira', 'refrigerator']) &&
        target.capabilities.contains(CoreCapability.CORE_CAP_TEMPERATURE_FRIDGE)) {
      return '${target.name} fridge temperature is ${state.temperatureFridge.toStringAsFixed(0)}°C.';
    }
    if (target.capabilities.contains(CoreCapability.CORE_CAP_TEMPERATURE)) {
      return '${target.name} temperature is ${state.temperature.toStringAsFixed(0)}°C.';
    }
    if (target.capabilities.contains(CoreCapability.CORE_CAP_TEMPERATURE_FRIDGE)) {
      return '${target.name} fridge temperature is ${state.temperatureFridge.toStringAsFixed(0)}°C.';
    }
    if (target.capabilities.contains(CoreCapability.CORE_CAP_TEMPERATURE_FREEZER)) {
      return '${target.name} freezer temperature is ${state.temperatureFreezer.toStringAsFixed(0)}°C.';
    }
    return '${target.name} temperature is unavailable right now.';
  }

  Future<void> _executeAssistantCommand(String raw) async {
    final input = raw.trim();
    if (input.isEmpty) return;

    _appendUserChat(input);
    _setAssistantThinking(true);

    try {
      final backendReply = Bridge.aiExecuteCommand(input).trim();
      final lower = backendReply.toLowerCase();
      final genericOrStale = backendReply.isEmpty ||
          lower.contains('i can report status, online devices and possible behavior insights') ||
          lower.contains('i could not identify the target device') ||
          lower.contains('mention the device name');

      if (genericOrStale) {
        final backendChat = Bridge.aiProcessChat(input).trim();
        if (backendChat.isNotEmpty) {
          _appendAssistantChat(backendChat);
        } else if (backendReply.isNotEmpty) {
          _appendAssistantChat(backendReply);
        } else {
          _appendAssistantChat('${_friendlyPrefix()} I could not process this request right now.');
        }
      } else {
        _appendAssistantChat(backendReply);
      }
    } catch (_) {
      _appendAssistantChat('${_friendlyPrefix()} I failed to process the command. Please try again.');
    }
  }

  Future<void> _toggleAudioCapture() async {
    if (!_isVoiceSupportedPlatform) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: Duration(seconds: 2),
          animation: Animation.fromValueListenable( CurvedAnimation(parent: AlwaysStoppedAnimation(1), curve: Curves.easeOutSine)),
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
      _voiceEventSub = VoiceRecognitionPlatform.instance.listenResult().listen((event) {
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
        const SnackBar(content: Text('Voice recognition is not available right now.')),
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
        } catch (_) {
          _lastPowerByDevice[d.uuid] = false;
        }
      }

      _eventSub = Bridge.onEvents.listen((event) {
        if (event.type != CoreEventType.CORE_EVENT_STATE_CHANGED) return;

        final prev = _lastPowerByDevice[event.uuid] ?? false;
        final next = event.state.power;
        _lastPowerByDevice[event.uuid] = next;

        _recordStatePattern(event.uuid, _lastStateByDevice[event.uuid], event.state);
        _lastStateByDevice[event.uuid] = _copyState(event.state);

        if (!prev && next) {
          _recordPowerOnSignal();
        }
      });

      _startAutomationLoop();
      _startAssistantDataRotation();
      _startAnnotationRotation();
      _startRoundHourWeatherLoop();

      if (mounted) {
        setState(() => _loading = false);
      }

      _recordAppOpenSignal();
      _bootstrapLocationAndWeather();
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
    _roundHourWeatherTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
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
    await prefs.setString(_kDeviceActivityById, jsonEncode(_deviceActivityById));
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
            locationSettings: const LocationSettings(accuracy: LocationAccuracy.low),
          ).timeout(const Duration(seconds: 4));

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
    HttpClient? client;
    try {
      final uri = Uri.parse('https://geocode.maps.co/reverse?lat=$lat&lon=$lon');
      client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.userAgentHeader, 'easync-assistant/1.0');
      final res = await req.close().timeout(const Duration(seconds: 4));
      final raw = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 4));
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
      final raw = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 4));
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
      final raw = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 4));

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
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing,
          ],
        ],
      ),
    );
  }

  List<Widget> _assistantDataTiles() {
    return [
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
                    final p = Curves.easeOutCubic.transform(_chatBorderPulse.value.clamp(0.0, 1.0));
                    if (p >= 1) return const SizedBox.shrink();

                    final grow = (p / 0.14).clamp(0.0, 1.0);
                    final shrink = ((1.0 - p) / 0.18).clamp(0.0, 1.0);
                    final sizeFactor = (grow < shrink ? grow : shrink).toDouble();
                    final dynamicSegment = (segment * sizeFactor).clamp(0.0, segment).toDouble();
                    if (dynamicSegment <= 0.8) return const SizedBox.shrink();

                    final head = p * track;
                    final segLeft = (head - dynamicSegment).clamp(0.0, track - dynamicSegment);

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
    final quickPrompts = <String>[
      'Turn on AC and set temperature 23',
      'Set brightness 65 and color blue',
      'Turn off all lights',
      'Set curtains position 40',
      'Turn on living room lamp',
    ];
    final query = _typedCommand.trim().toLowerCase();
    final filteredPrompts = query.isEmpty
        ? const <String>[]
        : quickPrompts.where((p) => p.toLowerCase().contains(query)).take(4).toList();
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
              Text('Chat', style: EaText.primary.copyWith(fontSize: 17)),
              const SizedBox(width: 8),
              SizedBox(
                width: 16,
                height: 16,
                child: _assistantThinking
                    ? RotationTransition(
                        turns: _thinkingController,
                        child: const Icon(Icons.autorenew, size: 15, color: EaColor.fore),
                      )
                    : AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: _isRecordingAudio ? 9 : 7,
                        height: _isRecordingAudio ? 9 : 7,
                        decoration: BoxDecoration(
                          color: _isRecordingAudio ? Colors.redAccent : EaColor.fore,
                          shape: BoxShape.circle,
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              Text(
                _assistantThinking
                    ? 'Thinking...'
                    : (_isRecordingAudio ? 'Listening...' : 'Ready'),
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
                                padding: const EdgeInsets.only(right: 6),
                                child: ActionChip(
                                  label: Text(p, style: EaText.secondaryTranslucent),
                                  onPressed: () => _runQuickPrompt(p),
                                  side: const BorderSide(color: EaColor.border),
                                  backgroundColor: EaColor.secondaryBack,
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
            style: EaText.secondary.copyWith(color: EaColor.textPrimary),
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
                child: ElevatedButton.icon(
                  onPressed: _submitCurrentCommand,
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Send'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: EaColor.fore,
                    foregroundColor: Colors.black,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _toggleAudioCapture,
                icon: Icon(_isRecordingAudio ? Icons.stop_circle : Icons.mic),
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
                  final isTypingTail = !isUser &&
                      i == _chatMessages.length - 1 &&
                      (_chatTypingTimer?.isActive ?? false);

                  return Align(
                    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                            color: isUser ? Colors.black : EaColor.textSecondary,
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

    _startChatTopSweepOnce();

    final dataTiles = _assistantDataTiles();
    final annotations = _annotationModels();
    final screenHeight = MediaQuery.sizeOf(context).height;
    final chatPanelHeight = (screenHeight * 0.34).clamp(270.0, 420.0).toDouble();

    return SafeArea(
      child: Stack(
        children: [
          SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(16, 10, 16, chatPanelHeight + 44),
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
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Outside temperature', style: EaText.secondary),
                      ),
                      Spacer(),
                      IconButton(
                        onPressed: (_useWeatherData && _locationQuery.trim().isNotEmpty)
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
                          Icon(_weatherIconForTemp(), color: EaColor.fore, size: 20),
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
                          onPressed: _useLocationData ? _promptForLocation : null,
                          icon: const Icon(Icons.place_outlined, size: 18),
                          label: Text(
                            _locationQuery.trim().isEmpty ? 'Set location' : _locationQuery,
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
                            opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
                            child: child,
                          );
                        },
                        child: KeyedSubtree(
                          key: ValueKey('assistant-data-${_assistantDataIndex % dataTiles.length}'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: dataTiles[_assistantDataIndex % dataTiles.length],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(dataTiles.length, (i) {
                      final active = i == (_assistantDataIndex % dataTiles.length);
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        width: active ? 18 : 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: active ? EaColor.fore : EaColor.fore.withValues(alpha: .22),
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
                  child: Text('Annotations', style: EaText.primary.copyWith(fontSize: 18)),
                ),
                TextButton(
                  onPressed: () => _showAllAnnotationsBottomSheet(annotations),
                  child: Text('View details', style: EaText.secondary.copyWith(fontSize: 12)),
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
                          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
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
                        key: ValueKey('annotation-${_annotationIndex % annotations.length}'),
                        child: Builder(
                          builder: (_) {
                            final a = annotations[_annotationIndex % annotations.length];
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
                        color: active ? EaColor.fore : EaColor.fore.withValues(alpha: .22),
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
                    height: (chatPanelHeight * 0.62).clamp(140.0, 230.0).toDouble(),
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
