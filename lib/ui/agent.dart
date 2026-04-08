/*
!
 * @file assistant_chat.dart
 * @brief EaSync assistant page focused only on chat.
 * @param No external parameters.
 * @return Stateful chat interface with persisted chat history and sidebar.
 * @author Erick Radmann
 */

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'handler.dart';

class Agent extends StatefulWidget {
  const Agent({super.key});

  @override
  State<Agent> createState() => AgentState();
}

class AgentState extends State<Agent>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  bool get _aiEnabled => EaAppSettings.instance.aiEnabled;
  StreamSubscription<String>? _aiStreamSub;
  bool _aiCancelled = false;
  String _assistantTargetText = '';
  String _assistantRenderedText = '';
  final Queue<String> _typingQueue = Queue<String>();
  Timer? _typingTimer;
  int _typingCharIndex = 0;
  bool _streamFinished = false;
  Timer? _thinkingGateTimer;
  Timer? _persistDebounce;
  static const String _kChats = 'assistant.chats.v1';
  static const String _kActiveChatId = 'assistant.active_chat_id';
  static const String _kAuthName = 'account.auth.name';
  static const String _kAuthPhoto = 'account.auth.photo';

  final EaAppSettings _settings = EaAppSettings.instance;
  final TextEditingController _commandController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<_ChatSession> _sessions = [];
  String? _activeChatId;
  bool _sending = false;
  bool _typingIndicator = false;
  bool _sidebarOpen = false;
  String _profileName = '';
  String? _profilePhoto;
  EaPlanTier _planTier = EaPlanTier.free;

  static const double _chatDrawerWidth = 252;
  static const Duration _thinkingMinDuration = Duration(milliseconds: 80);

  late final AnimationController _thinkingPulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  bool _isInTree = true;

  @override
  bool get wantKeepAlive => true;

  bool get _canUpdateUi => mounted && _isInTree;

  void _startThinkingPulse() {
    if (!_thinkingPulse.isAnimating) {
      _thinkingPulse.repeat(reverse: true);
    }
  }

  void _stopThinkingPulse() {
    if (_thinkingPulse.isAnimating) {
      _thinkingPulse.stop();
    }
    _thinkingPulse.value = 0;
  }

  _ChatSession? get _activeSession {
    if (_activeChatId == null) return null;
    for (final s in _sessions) {
      if (s.id == _activeChatId) return s;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadPlanTier();
    _loadState();
  }

  Future<void> _loadPlanTier() async {
    final next = await EaPlanService.instance.readTier();
    if (!mounted) return;
    setState(() => _planTier = next);
  }

  bool get _assistantAllowed => EaPlanService.instance.allowsAssistant(_planTier);

  void _openPlanOptions() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SubscriptionPage()),
    ).then((_) => _loadPlanTier());
  }

  @override
  void dispose() {
    _thinkingGateTimer?.cancel();
    _persistDebounce?.cancel();
    _typingTimer?.cancel();
    _aiStreamSub?.cancel();
    _stopThinkingPulse();
    _thinkingPulse.dispose();
    _commandController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void deactivate() {
    _isInTree = false;
    _stopThinkingPulse();
    _persistState();
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _isInTree = true;
    _reloadProfileIdentity();
    if (_typingIndicator) {
      _startThinkingPulse();
    }
  }

  Future<void> _reloadProfileIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_kAuthName)?.trim() ?? '';
    final photo = (prefs.getString(_kAuthPhoto) ?? '').trim();
    if (!mounted) return;
    setState(() {
      _profileName = name;
      _profilePhoto = photo;
    });
  }

  Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();

    final raw = prefs.getString(_kChats);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = await compute(_decodeChatSessionsRaw, raw);
        if (decoded.isNotEmpty) {
          _sessions
            ..clear()
            ..addAll(decoded.map((e) => _ChatSession.fromJson(e)));
        }
      } catch (_) {}
    }

    _activeChatId = prefs.getString(_kActiveChatId);
    _profileName = prefs.getString(_kAuthName)?.trim().isNotEmpty == true
        ? prefs.getString(_kAuthName)!.trim()
        : '';
    _profilePhoto = prefs.getString(_kAuthPhoto);

    if (_activeSession == null && _sessions.isNotEmpty) {
      _activeChatId = _sessions.first.id;
    }

    if (_canUpdateUi) setState(() {});
  }

  Future<void> _persistState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kChats,
      jsonEncode(_sessions.map((e) => e.toJson()).toList()),
    );
    if (_activeChatId != null) {
      await prefs.setString(_kActiveChatId, _activeChatId!);
    }
  }

  void _schedulePersistState() {
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 420), () {
      _persistState();
    });
  }

  Future<void> _createNewChat({String? fromText, String? fallbackTitle}) async {
    final title = (fromText ?? '').trim().isEmpty
        ? (fallbackTitle ?? 'New chat')
        : fromText!.trim().split('\n').first;

    final session = _ChatSession(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title.length > 48 ? '${title.substring(0, 48)}…' : title,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
      messages: [],
    );

    _sessions.insert(0, session);
    _activeChatId = session.id;
    await _persistState();
    if (_canUpdateUi) setState(() {});
  }

  Future<void> _send() async {
    final raw = _commandController.text.trim();
    if (raw.isEmpty || _sending) return;
    if (!_assistantAllowed) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              EaI18n.t(context, 'Assistant is available from Plus plan.'),
            ),
            action: SnackBarAction(
              label: EaI18n.t(context, 'Go to plan'),
              onPressed: _openPlanOptions,
            ),
          ),
        );
      return;
    }

    final newChatText = EaI18n.t(context, 'New chat');
    final noResponseText = EaI18n.t(context, 'No response generated.');

    if (_settings.hapticsEnabled) {
      HapticFeedback.lightImpact();
    }

    if (_activeSession == null) {
      await _createNewChat(fromText: raw, fallbackTitle: newChatText);
    }

    final session = _activeSession;
    if (session == null) return;

    _commandController.clear();

    setState(() {
      session.messages.add(_ChatMessage(role: _Role.user, text: raw));
      session.messages.add(_ChatMessage(role: _Role.assistant, text: ''));
      _sending = true;
      _typingIndicator = true;
      _assistantTargetText = '';
      _assistantRenderedText = '';
      _typingQueue.clear();
      _typingCharIndex = 0;
      _streamFinished = false;
    });

    final modelPrompt = _buildModelPrompt(session, raw);

    _thinkingGateTimer?.cancel();
    _thinkingGateTimer = Timer(_thinkingMinDuration, () {
      if (!mounted || _aiCancelled) return;
    });
    _startThinkingPulse();
    await _persistState();
    _scrollToBottom();

    _aiCancelled = false;

    if (!mounted) return;

    try {
      final stream = aiQueryStream(modelPrompt);

      String assistantText = '';
      _aiStreamSub = stream.listen(
        (chunk) {
          if (_aiCancelled) return;
          var text = chunk.toString();
          if (text.startsWith('[AI error]')) {
            return;
          }
          text = text.replaceFirst(RegExp(r'^[\uFFFD\x00-\x1F]+'), '');
          if (text.isEmpty) return;
          final streamChunk = _sanitizeStreamingChunk(text);
          if (streamChunk.isEmpty) return;
          assistantText += streamChunk;
          _assistantTargetText += streamChunk;
          if (!mounted) return;
          setState(() {
            _typingIndicator = false;
            _typingQueue.add(streamChunk);
          });
          _startTypingPump(session);
          _stopThinkingPulse();
          _thinkingGateTimer?.cancel();
        },
        onDone: () {
          _streamFinished = true;
          if (_assistantTargetText.trim().isEmpty && _typingQueue.isEmpty) {
            _assistantTargetText = noResponseText;
            _assistantRenderedText = noResponseText;
            _setLastAssistantMessage(session, _assistantRenderedText);
            _finalizeSendState();
            _persistState();
            _scrollToBottom();
            return;
          }

          if (_typingQueue.isEmpty && _typingTimer == null) {
            _assistantRenderedText = _sanitizeAssistantText(
              _assistantRenderedText,
            );
            _setLastAssistantMessage(session, _assistantRenderedText);
            _finalizeSendState();
            _persistState();
            _scrollToBottom();
          }
        },
        onError: (_) {
          _typingTimer?.cancel();
          _typingTimer = null;
          _typingQueue.clear();
          setState(() {
            final fallbackText = assistantText.trim().isNotEmpty
                ? assistantText
                : noResponseText;
            _assistantRenderedText = _sanitizeAssistantText(fallbackText);
            _setLastAssistantMessage(session, _assistantRenderedText);
            _typingIndicator = false;
            _sending = false;
            _assistantTargetText = '';
            _typingCharIndex = 0;
            _streamFinished = false;
          });
          _aiStreamSub = null;
          _thinkingGateTimer?.cancel();
          _stopThinkingPulse();
          _persistState();
        },
      );
    } catch (_) {
      _typingTimer?.cancel();
      _typingTimer = null;
      _typingQueue.clear();
      setState(() {
        _assistantRenderedText = noResponseText;
        _setLastAssistantMessage(session, _assistantRenderedText);
        _typingIndicator = false;
        _sending = false;
        _assistantTargetText = '';
        _typingCharIndex = 0;
        _streamFinished = false;
      });
      _aiStreamSub = null;
      _thinkingGateTimer?.cancel();
      _stopThinkingPulse();
      _persistState();
    }
  }

  String _buildModelPrompt(_ChatSession session, String rawUserMessage) {
    // Keep prompt plain and direct. Native tokenizer already wraps roles.
    return rawUserMessage.trim();
  }

  String _sanitizeAssistantText(String text) {
    if (text.isEmpty) return text;

    var out = text;

    // Remove role prefixes only when they appear at the beginning.
    out = out.replaceFirst(
      RegExp(r'^\s*(human|user|assistant)\s*:\s*', caseSensitive: false),
      '',
    );

    // Drop known special tokens without truncating the rest of the answer.
    out = out
        .replaceAll('<|im_start|>', ' ')
        .replaceAll('<|im_end|>', ' ')
        .replaceAll('<|endoftext|>', ' ');

    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();

    return out;
  }

  String _sanitizeStreamingChunk(String text) {
    if (text.isEmpty) return text;

    return text
        .replaceAll('<|im_start|>', '')
        .replaceAll('<|im_end|>', '')
        .replaceAll('<|endoftext|>', '');
  }

  void _startTypingPump(_ChatSession session) {
    if (_typingTimer != null) return;

    _typingTimer = Timer.periodic(const Duration(milliseconds: 12), (_) {
      if (!_canUpdateUi || _aiCancelled) {
        _typingTimer?.cancel();
        _typingTimer = null;
        return;
      }

      if (_typingQueue.isEmpty) {
        _typingTimer?.cancel();
        _typingTimer = null;

        if (_streamFinished) {
          _assistantRenderedText = _sanitizeAssistantText(_assistantRenderedText);
          setState(() {
            _setLastAssistantMessage(session, _assistantRenderedText);
          });
          _finalizeSendState();
          _persistState();
          _scrollToBottom();
        }
        return;
      }

      final currentChunk = _typingQueue.first;
      if (_typingCharIndex >= currentChunk.length) {
        _typingQueue.removeFirst();
        _typingCharIndex = 0;
        _schedulePersistState();
        return;
      }

      final nextChar = currentChunk[_typingCharIndex];
      _typingCharIndex += 1;

      setState(() {
        _assistantRenderedText += nextChar;
        _setLastAssistantMessage(session, _assistantRenderedText);
      });

      if (_typingCharIndex % 3 == 0) {
        _scrollToBottom();
      }
    });
  }

  void _setLastAssistantMessage(_ChatSession session, String text) {
    for (int i = session.messages.length - 1; i >= 0; --i) {
      if (session.messages[i].role == _Role.assistant) {
        session.messages[i] = _ChatMessage(role: _Role.assistant, text: text);
        break;
      }
    }
  }

  void _finalizeSendState() {
    _stopThinkingPulse();
    _thinkingGateTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _typingIndicator = false;
      _sending = false;
      _assistantTargetText = '';
      _typingCharIndex = 0;
      _streamFinished = false;
    });
    _aiStreamSub = null;
  }

  void _stopAiGeneration() {
    _aiCancelled = true;
    _aiStreamSub?.cancel();
    _aiStreamSub = null;
    _typingTimer?.cancel();
    _typingTimer = null;
    _typingQueue.clear();
    _stopThinkingPulse();

    setState(() {
      _typingIndicator = false;
      _sending = false;
      _assistantTargetText = '';
      _typingCharIndex = 0;
      _streamFinished = false;
    });
    _thinkingGateTimer?.cancel();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isInTree || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final compact = _settings.compactMode;

    if (!_aiEnabled) {
      return Scaffold(
        appBar: AppBar(title: const Text('Assistant')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'The AI assistant is disabled on this device. Enable it on the home screen to use.',
              textAlign: TextAlign.center,
              style: EaText.secondary.copyWith(fontSize: 18),
            ),
          ),
        ),
      );
    }

    if (!_assistantAllowed) {
      return Scaffold(
        appBar: AppBar(title: Text(EaI18n.t(context, 'Assistant'))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.workspace_premium_outlined,
                  size: 38,
                  color: EaColor.fore,
                ),
                const SizedBox(height: 10),
                Text(
                  EaI18n.t(context, 'Assistant is available from Plus plan.'),
                  textAlign: TextAlign.center,
                  style: EaText.secondary.copyWith(fontSize: 16),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _openPlanOptions,
                  child: Text(EaI18n.t(context, 'Open plan options')),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 14 : 20,
          8,
          compact ? 14 : 20,
          12,
        ),
        child: EaFadeSlideIn(
          begin: const Offset(0, 0.015),
          duration: _settings.animationsEnabled
              ? EaMotion.normal
              : Duration.zero,
          child: Container(
            decoration: BoxDecoration(
              color: EaAdaptiveColor.surface(context),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: EaAdaptiveColor.border(context)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 10, 12, 8),
                        child: Row(
                          children: [
                            EaBlurFadeSwitcher(
                              marker: _sidebarOpen,
                              duration: const Duration(milliseconds: 150),
                              beginBlur: 4,
                              child: IconButton(
                                tooltip: _sidebarOpen
                                    ? EaI18n.t(context, 'Hide chats')
                                    : EaI18n.t(context, 'Show chats'),
                                onPressed: () => setState(
                                  () => _sidebarOpen = !_sidebarOpen,
                                ),
                                icon: Icon(
                                  _sidebarOpen
                                      ? Icons.menu_open_rounded
                                      : Icons.menu_rounded,
                                  color: EaColor.fore,
                                ),
                              ),
                            ),
                            const Spacer(),
                          ],
                        ),
                      ),
                      Divider(
                        height: 1,
                        color: EaAdaptiveColor.border(context),
                      ),
                      Expanded(child: _buildMessageList()),
                      _composer(),
                    ],
                  ),
                  if (_sidebarOpen)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _sidebarOpen = false),
                        child: Container(color: EaAdaptiveColor.scrim(context)),
                      ),
                    ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    top: 0,
                    bottom: 0,
                    left: _sidebarOpen ? 0 : -(_chatDrawerWidth + 8),
                    child: IgnorePointer(
                      ignoring: !_sidebarOpen,
                      child: Container(
                        width: _chatDrawerWidth,
                        decoration: BoxDecoration(
                          color: EaAdaptiveColor.surface(context),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: EaAdaptiveColor.border(context),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.16),
                              blurRadius: 20,
                              offset: const Offset(4, 0),
                            ),
                          ],
                        ),
                        child: _buildSidebar(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          child: Row(
            children: [
              Expanded(
                child: _railActionButton(
                  icon: Icons.add_comment_rounded,
                  label: EaI18n.t(context, 'New chat'),
                  onTap: () => _createNewChat(
                    fallbackTitle: EaI18n.t(context, 'New chat'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _railIconButton(
                tooltip: EaI18n.t(context, 'Close chats'),
                icon: Icons.close_rounded,
                onTap: () => setState(() => _sidebarOpen = false),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: EaAdaptiveColor.border(context)),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 6),
            itemCount: _sessions.length,
            itemBuilder: (context, i) {
              final s = _sessions[i];
              final active = s.id == _activeChatId;
              return Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                child: ListTile(
                  dense: true,
                  tileColor: active
                      ? EaColor.fore.withValues(alpha: 0.15)
                      : Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  title: Text(
                    s.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: EaText.small.copyWith(
                      color: EaAdaptiveColor.bodyText(context),
                    ),
                  ),
                  onTap: () async {
                    setState(() => _activeChatId = s.id);
                    await _persistState();
                    if (_canUpdateUi) {
                      setState(() => _sidebarOpen = false);
                    }
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _railIconButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return EaBlurFadeIn(
      duration: const Duration(milliseconds: 140),
      beginBlur: 4,
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: EaAdaptiveColor.field(context),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: SizedBox(
              width: 38,
              height: 38,
              child: Icon(icon, size: 20, color: EaColor.fore),
            ),
          ),
        ),
      ),
    );
  }

  Widget _railActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return EaBlurFadeIn(
      duration: const Duration(milliseconds: 140),
      beginBlur: 4,
      child: Material(
        color: EaAdaptiveColor.field(context),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                Icon(icon, size: 18, color: EaColor.fore),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: EaText.small.copyWith(
                      color: EaAdaptiveColor.bodyText(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageList() {
    final messages = _activeSession?.messages ?? const <_ChatMessage>[];
    if (messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22),
          child: EaBlurFadeIn(
            duration: const Duration(milliseconds: 180),
            beginBlur: 6,
            child: Text(
              EaI18n.t(context, 'How can I help you, {_profileName}?', {
                '_profileName': _profileName,
              }),
              textAlign: TextAlign.center,
              style: EaText.secondary.copyWith(
                fontSize: 18,
                color: EaAdaptiveColor.secondaryText(context),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: messages.length,
      itemBuilder: (context, i) {
        final msg = messages[i];
        final user = msg.role == _Role.user;

        final isLastAssistant = !user && i == messages.length - 1;
        final showThinking = isLastAssistant && _typingIndicator;

        return LayoutBuilder(
          builder: (context, constraints) {
            final bubbleMax = max(120.0, constraints.maxWidth - 82);

            return Align(
              alignment: user ? Alignment.centerRight : Alignment.centerLeft,
              child: Row(
                mainAxisAlignment: user
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (!user) _assistantAvatar(),
                  if (!user) const SizedBox(width: 8),
                  Flexible(
                    child: Align(
                      alignment: user
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        constraints: BoxConstraints(maxWidth: bubbleMax),
                        decoration: BoxDecoration(
                          color: user
                              ? EaColor.fore.withValues(alpha: 0.18)
                              : EaAdaptiveColor.field(context),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: EaAdaptiveColor.border(context),
                          ),
                        ),
                        child: showThinking
                            ? _thinkingShimmerLabel()
                            : Text(
                                msg.text,
                                style: EaText.small.copyWith(
                                  color: EaAdaptiveColor.bodyText(context),
                                  height: 1.35,
                                ),
                              ),
                      ),
                    ),
                  ),
                  if (user) const SizedBox(width: 8),
                  if (user) _userAvatar(),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _thinkingShimmerLabel() {
    return AnimatedBuilder(
      animation: _thinkingPulse,
      builder: (context, _) {
        return _thinkingFlyingText(fontSize: 15);
      },
    );
  }

  Widget _thinkingFlyingText({required double fontSize}) {
    final glowSweep = LinearGradient(
      colors: [
        Colors.transparent,
        EaColor.fore.withValues(alpha: 0.95),
        Colors.transparent,
      ],
      stops: const [0.0, 0.5, 1.0],
      begin: Alignment(-1.3 + 2.6 * _thinkingPulse.value, 0),
      end: Alignment(-0.3 + 2.6 * _thinkingPulse.value, 0),
    );

    return Transform.translate(
      offset: Offset(-4 + 2 * _thinkingPulse.value, 0),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Text(
            'Thinking',
            style: EaText.secondary.copyWith(
              color: EaAdaptiveColor.bodyText(context),
              fontSize: 12,
            ),
          ),
          ShaderMask(
            shaderCallback: (rect) => glowSweep.createShader(rect),
            blendMode: BlendMode.srcATop,
            child: Text(
              'Thinking',
              style: EaText.secondary.copyWith(
                color: EaAdaptiveColor.bodyText(context),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _assistantAvatar() {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: EaColor.fore.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Icon(
        Icons.auto_awesome_rounded,
        size: 15,
        color: EaColor.fore,
      ),
    );
  }

  Widget _userAvatar() {
    final photo = (_profilePhoto ?? '').trim();
    Widget fallbackIcon() =>
        const Icon(Icons.person, size: 13, color: EaColor.fore);

    if (photo.isEmpty) {
      return CircleAvatar(
        radius: 13,
        backgroundColor: EaColor.fore.withValues(alpha: 0.16),
        child: fallbackIcon(),
      );
    }

    final image = photo.startsWith('http')
        ? Image.network(
            photo,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallbackIcon(),
          )
        : Image.file(
            File(photo),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallbackIcon(),
          );

    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: EaColor.fore.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      clipBehavior: Clip.antiAlias,
      child: image,
    );
  }

  Widget _composer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _commandController,
              style: EaText.secondary.copyWith(
                color: EaAdaptiveColor.bodyText(context),
              ),
              minLines: 1,
              maxLines: 4,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: EaI18n.t(
                  context,
                  'Type a command or ask a question...',
                ),
                hintStyle: EaText.small.copyWith(
                  color: EaAdaptiveColor.secondaryText(context),
                ),
                filled: true,
                fillColor: EaAdaptiveColor.field(context),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: EaAdaptiveColor.border(context),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: EaAdaptiveColor.border(context),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: EaColor.fore),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          EaBlurFadeSwitcher(
            marker: _sending,
            duration: const Duration(milliseconds: 150),
            beginBlur: 5,
            child: AnimatedContainer(
              duration: EaMotion.fast,
              curve: Curves.easeOut,
              decoration: BoxDecoration(
                color: _sending ? EaColor.secondaryFore : EaColor.fore,
                borderRadius: BorderRadius.circular(14),
              ),
              child: IconButton(
                onPressed: _sending ? _stopAiGeneration : _send,
                icon: _sending
                    ? const Icon(Icons.stop_rounded, color: EaColor.back)
                    : const Icon(Icons.send_rounded, color: EaColor.back),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

List<Map<String, dynamic>> _decodeChatSessionsRaw(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! List) return const <Map<String, dynamic>>[];
  return decoded
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList(growable: false);
}

enum _Role { user, assistant }

class _ChatMessage {
  final _Role role;
  final String text;

  const _ChatMessage({required this.role, required this.text});

  Map<String, dynamic> toJson() => {'role': role.name, 'text': text};

  factory _ChatMessage.fromJson(Map<String, dynamic> json) {
    final roleRaw = (json['role'] ?? 'assistant').toString();
    return _ChatMessage(
      role: roleRaw == 'user' ? _Role.user : _Role.assistant,
      text: (json['text'] ?? '').toString(),
    );
  }
}

class _ChatSession {
  final String id;
  final String title;
  final int createdAtMs;
  final List<_ChatMessage> messages;

  _ChatSession({
    required this.id,
    required this.title,
    required this.createdAtMs,
    required this.messages,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'createdAtMs': createdAtMs,
    'messages': messages.map((e) => e.toJson()).toList(),
  };

  factory _ChatSession.fromJson(Map<String, dynamic> json) {
    final list = json['messages'];
    return _ChatSession(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? 'Chat').toString(),
      createdAtMs: int.tryParse((json['createdAtMs'] ?? '0').toString()) ?? 0,
      messages: list is List
          ? list
                .whereType<Map>()
                .map((e) => _ChatMessage.fromJson(e.cast<String, dynamic>()))
                .toList()
          : [],
    );
  }
}
