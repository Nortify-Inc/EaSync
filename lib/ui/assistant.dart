/*!
 * @file assistant.dart
 * @brief AI-style assistant page with local pattern learning and recommendations.
 * @param No external parameters.
 * @return Stateful page with insights and smart suggestion actions.
 * @author Erick Radmann
 */

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

class _AssistantState extends State<Assistant> with SingleTickerProviderStateMixin {
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
  int _assistantDataIndex = 0;
  int _annotationIndex = 0;
  String _typedCommand = '';
  String _lastRoundRefreshKey = '';
  final Random _rng = Random();

  final Map<int, int> _powerOnByHour = {};
  final Map<int, int> _appOpenByHour = {};
  final Map<String, bool> _lastPowerByDevice = {};
  List<DeviceInfo> _pendingTargets = [];
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
  late final AnimationController _thinkingController;
  final TextEditingController _commandController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  bool _isRecordingAudio = false;
  final List<String> _commandLog = [];
  final List<_ChatMessage> _chatMessages = [
    const _ChatMessage(role: _ChatRole.assistant, text: 'Hello! I can automate your devices from text commands.'),
  ];

  @override
  void initState() {
    super.initState();
    _thinkingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
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

    _appendUserChat(input);
    _setAssistantThinking(true);

    final text = _normalizeInput(input);
    final hasAction = _containsActionKeyword(text);
    final greeted = _isGreeting(text);
    final general = _generalResponse(text);

    if (_pendingClause != null && _pendingTargets.isNotEmpty) {
      final chosen = _resolvePendingChoice(text);
      if (chosen != null) {
        final actions = _applyClause(chosen, _pendingClause!);
        _pendingClause = null;
        _pendingTargets = [];
        if (actions.isNotEmpty) {
          _appendAssistantChat('${_friendlyPrefix()} Applied to ${chosen.name}: ${actions.join(', ')}.');
        } else {
          _appendAssistantChat('I got your selection, but this action is not supported by ${chosen.name}.');
        }
        return;
      }
    }

    if (greeted && !hasAction) {
      _appendAssistantChat(_greetingResponse());
      return;
    }

    if (!hasAction && general != null) {
      _appendAssistantChat(general);
      return;
    }

    final devices = Bridge.listDevices();
    final informational = _informationalDevicesResponse(text, devices);
    if (!hasAction && informational != null) {
      _appendAssistantChat(informational);
      return;
    }

    if (devices.isEmpty) {
      _appendAssistantChat('I could not find devices to automate right now.');
      return;
    }

    if (!_allowDeviceControl) {
      _appendAssistantChat(
        'Device control is disabled. Enable it in Assistant Data to run automation commands.',
      );
      return;
    }

    try {
      final clauses = text
          .split(RegExp(r',|;|\band\b|\bthen\b|\bafter\b'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final allActions = <String>[];
      final unresolved = <String>[];
      for (final clause in clauses) {
        final targets = _resolveTargetsForClause(clause, devices);
        final wantsAll = clause.contains('all ') || clause.contains('every ');
        if (targets.isEmpty) {
          unresolved.add('I could not find a ${_targetHint(clause)} for "$clause"');
          continue;
        }

        if (!wantsAll && targets.length > 1) {
          final names = targets.take(4).map((e) => e.name).join(', ');
          _pendingTargets = targets;
          _pendingClause = clause;
          _appendAssistantChat(
            '${_friendlyPrefix()} I found multiple matches for "$clause": $names. Which one should I use?',
          );
          return;
        }

        for (final t in targets) {
          allActions.addAll(_applyClause(t, clause));
        }
      }

      if (allActions.isEmpty) {
        _appendAssistantChat(
          '${_friendlyPrefix()} I could not map this command safely. Try: "turn on AC and set temperature 23", "set brightness 80 and color blue".',
        );
        return;
      }

      final greetingPrefix = greeted ? '${_greetingResponse()} ' : '';
      final unresolvedSuffix = unresolved.isEmpty
          ? ''
          : ' I skipped ${unresolved.length} request(s): ${unresolved.take(2).join('. ')}${unresolved.length > 2 ? '...' : ''}.';
      _appendAssistantChat(
        '$greetingPrefix${_friendlyPrefix()} I executed ${allActions.length} action(s): ${allActions.take(3).join(', ')}${allActions.length > 3 ? '...' : ''}.$unresolvedSuffix',
      );
    } catch (_) {
      _appendAssistantChat('${_friendlyPrefix()} I failed to apply the command. Please try again.');
    }
  }

  Future<void> _toggleAudioCapture() async {
    if (!_isVoiceSupportedPlatform) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Voice recognition is only available on Android for now.'),
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

      // Baseline state for edge detection (power OFF -> ON)
      for (final d in Bridge.listDevices()) {
        try {
          _lastPowerByDevice[d.uuid] = Bridge.getState(d.uuid).power;
        } catch (_) {
          _lastPowerByDevice[d.uuid] = false;
        }
      }

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
  }

  void _nextAnnotationTile() {
    final total = _annotationModels().length;
    if (total <= 1) return;
    setState(() => _annotationIndex = (_annotationIndex + 1) % total);
  }

  void _prevAnnotationTile() {
    final total = _annotationModels().length;
    if (total <= 1) return;
    setState(() => _annotationIndex = (_annotationIndex - 1 + total) % total);
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
    setState(() => _assistantDataIndex = (_assistantDataIndex + 1) % total);
  }

  void _prevAssistantDataTile() {
    final total = _assistantDataTiles().length;
    if (total <= 1) return;
    setState(() => _assistantDataIndex = (_assistantDataIndex - 1 + total) % total);
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
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: EaColor.back.withValues(alpha: .95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: EaColor.border),
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
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: EaColor.fore.withValues(alpha: .45),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 8),
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
            maxLines: 2,
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

    final dataTiles = _assistantDataTiles();
    final currentDataTile = dataTiles[_assistantDataIndex % dataTiles.length];
    final annotations = _annotationModels();
    final currentAnnotation = annotations[_annotationIndex % annotations.length];
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
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Outside temperature', style: EaText.secondary),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Flexible(
                        fit: FlexFit.tight,
                        child: TextButton.icon(
                          onPressed: _useLocationData ? _promptForLocation : null,
                          icon: const Icon(Icons.place_outlined, size: 18),
                          label: Text(
                            _locationQuery.trim().isEmpty ? 'Set location' : _locationQuery,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Row(
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
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: (_useWeatherData && _locationQuery.trim().isNotEmpty)
                            ? _fetchOutsideTemperature
                            : null,
                        icon: const Icon(Icons.refresh, size: 20),
                        color: EaColor.fore,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _nextAssistantDataTile,
                    onHorizontalDragEnd: (details) {
                      final vx = details.primaryVelocity ?? 0;
                      if (vx < 0) {
                        _nextAssistantDataTile();
                      } else if (vx > 0) {
                        _prevAssistantDataTile();
                      }
                    },
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child: KeyedSubtree(
                        key: ValueKey('assistant-data-${_assistantDataIndex % dataTiles.length}'),
                        child: currentDataTile,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
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
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _nextAnnotationTile,
                  onHorizontalDragEnd: (details) {
                    final vx = details.primaryVelocity ?? 0;
                    if (vx < 0) {
                      _nextAnnotationTile();
                    } else if (vx > 0) {
                      _prevAnnotationTile();
                    }
                  },
                  child: SizedBox(
                    height: 122,
                    child: _card(
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
