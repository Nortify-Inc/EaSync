/*
!
 * @file assistant_chat.dart
 * @brief EaSync assistant page focused only on chat.
 * @param No external parameters.
 * @return Stateful chat interface with persisted chat history and sidebar.
 * @author Erick Radmann
 */

import 'dart:async';
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

class AgentState extends State<Agent> with TickerProviderStateMixin {
  bool get _aiEnabled => EaAppSettings.instance.aiEnabled;
  String _revealingText = '';
  StreamSubscription<String>? _aiStreamSub;
  bool _aiCancelled = false;
  String _assistantTargetText = '';
  bool _revealLoopRunning = false;
  Timer? _thinkingGateTimer;
  int _thinkingTokenEstimate = 0;
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

  static const double _chatDrawerWidth = 252;
  static const Duration _thinkingMinDuration = Duration(milliseconds: 80);
  static const int _thinkingTokenThreshold = 8;
  static const Duration _typingFrameDelay = Duration(milliseconds: 28);
  static const int _typingLeadCharsWhileStreaming = 10;
  static const int _maxAssistantChars = 220;

  late final AnimationController _thinkingPulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  bool _isInTree = true;

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
    _loadState();
  }

  @override
  void dispose() {
    _thinkingGateTimer?.cancel();
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
    super.deactivate();
  }

  @override
  void activate() {
    super.activate();
    _isInTree = true;
    if (_typingIndicator) {
      _startThinkingPulse();
    }
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
      _revealingText = '';
      _assistantTargetText = '';
      _revealLoopRunning = false;
      _thinkingTokenEstimate = 0;
    });

    final modelPrompt = _buildModelPrompt(session, raw);

    _thinkingGateTimer?.cancel();
    _thinkingGateTimer = Timer(_thinkingMinDuration, () {
      if (!mounted || _aiCancelled) return;
      if (_assistantTargetText.isNotEmpty) {
        _revealAssistantText(session);
      }
    });
    _startThinkingPulse();
    await _persistState();
    _scrollToBottom();

    _aiCancelled = false;

    if (!mounted) return;

    if (!_isInTree) {
      _stopThinkingPulse();
      _typingIndicator = false;
      _sending = false;
      await _persistState();
      return;
    }

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
          assistantText += text;
          _assistantTargetText = _sanitizeAssistantText(assistantText);
          _thinkingTokenEstimate = _estimateTokenCount(_assistantTargetText);
          if (_canStartReveal()) {
            _revealAssistantText(session);
          }
        },
        onDone: () {
          if (_assistantTargetText.trim().isEmpty) {
            _assistantTargetText = noResponseText;
          }

          _assistantTargetText = _sanitizeAssistantText(_assistantTargetText);
          _stopThinkingPulse();
          _thinkingGateTimer?.cancel();
          setState(() {
            _typingIndicator = false;
            _sending = false;
          });
          _revealAssistantText(session);
          _aiStreamSub = null;
          _persistState();
          _scrollToBottom();
        },
        onError: (_) {
          setState(() {
            final fallbackText = assistantText.trim().isNotEmpty
                ? assistantText
                : noResponseText;
            for (int i = session.messages.length - 1; i >= 0; --i) {
              if (session.messages[i].role == _Role.assistant) {
                session.messages[i] = _ChatMessage(
                  role: _Role.assistant,
                  text: fallbackText,
                );
                break;
              }
            }
            _typingIndicator = false;
            _sending = false;
            _revealingText = '';
            _assistantTargetText = '';
            _revealLoopRunning = false;
            _thinkingTokenEstimate = 0;
          });
          _aiStreamSub = null;
          _thinkingGateTimer?.cancel();
          _stopThinkingPulse();
          _persistState();
        },
      );
    } catch (_) {
      setState(() {
        for (int i = session.messages.length - 1; i >= 0; --i) {
          if (session.messages[i].role == _Role.assistant) {
            session.messages[i] = _ChatMessage(
              role: _Role.assistant,
              text: noResponseText,
            );
            break;
          }
        }
        _typingIndicator = false;
        _sending = false;
        _revealingText = '';
        _assistantTargetText = '';
        _revealLoopRunning = false;
        _thinkingTokenEstimate = 0;
      });
      _aiStreamSub = null;
      _thinkingGateTimer?.cancel();
      _stopThinkingPulse();
      _persistState();
    }
  }

  int _estimateTokenCount(String text) {
    final clean = text.trim();
    if (clean.isEmpty) return 0;
    return clean.split(RegExp(r'\s+')).length;
  }

  bool _canStartReveal() {
    if (!_sending) return _assistantTargetText.isNotEmpty;
    return _thinkingTokenEstimate >= _thinkingTokenThreshold;
  }

  String _buildModelPrompt(_ChatSession session, String rawUserMessage) {
    // Keep prompt plain and direct. Native tokenizer already wraps roles.
    return rawUserMessage.trim();
  }

  String _sanitizeAssistantText(String text) {
    if (text.isEmpty) return text;

    var out = text;
    const markers = <String>[
      'Human:',
      'User:',
      'Assistant:',
      '<|im_start|>',
      '<|im_end|>',
      '<|endoftext|>',
    ];

    for (final marker in markers) {
      final idx = out.indexOf(marker);
      if (idx >= 0) {
        out = out.substring(0, idx);
      }
    }

    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Keep answers concise and stable across long turns.
    final sentenceEnd = RegExp(r'[.!?]');
    var seenEnd = 0;
    for (var i = 0; i < out.length; i++) {
      if (sentenceEnd.hasMatch(out[i])) {
        seenEnd++;
        if (seenEnd >= 2) {
          out = out.substring(0, i + 1).trim();
          break;
        }
      }
    }

    if (out.length > _maxAssistantChars) {
      out = out.substring(0, _maxAssistantChars).trimRight();
      final lastSpace = out.lastIndexOf(' ');
      if (lastSpace > 120) {
        out = out.substring(0, lastSpace);
      }
      out = '$out...';
    }

    return out;
  }

  void _revealAssistantText(_ChatSession session) {
    if (!_canStartReveal()) return;
    if (_revealLoopRunning) return;
    _revealLoopRunning = true;

    Future<void>(() async {
      while (mounted && !_aiCancelled) {
        final currentLen = _revealingText.length;
        final targetLen = _assistantTargetText.length;

        if (currentLen >= targetLen) {
          if (_sending) {
            await Future.delayed(const Duration(milliseconds: 10));
            continue;
          }
          break;
        }

        if (_sending && (targetLen - currentLen) <= _typingLeadCharsWhileStreaming) {
          await Future.delayed(const Duration(milliseconds: 10));
          continue;
        }

        final nextLen = min(targetLen, currentLen + 1);

        if (!mounted) break;
        setState(() {
          _revealingText = _assistantTargetText.substring(0, nextLen);
          for (int i = session.messages.length - 1; i >= 0; --i) {
            if (session.messages[i].role == _Role.assistant) {
              session.messages[i] = _ChatMessage(
                role: _Role.assistant,
                text: _revealingText,
              );
              break;
            }
          }
        });
        _scrollToBottom();

        await Future.delayed(_typingFrameDelay);
      }

      _revealLoopRunning = false;

      if (mounted &&
          !_aiCancelled &&
          _revealingText.length < _assistantTargetText.length) {
        _revealAssistantText(session);
        return;
      }

      if (mounted && !_sending) {
        setState(() {
          _revealingText = '';
          _assistantTargetText = '';
          _thinkingTokenEstimate = 0;
        });
      }
    });
  }

  void _stopAiGeneration() {
    _aiCancelled = true;
    _aiStreamSub?.cancel();
    _aiStreamSub = null;
    _stopThinkingPulse();

    setState(() {
      _typingIndicator = false;
      _sending = false;
      _assistantTargetText = '';
      _revealLoopRunning = false;
      _thinkingTokenEstimate = 0;
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
        final showThinking =
            isLastAssistant && _typingIndicator && _revealingText.isEmpty;

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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showThinking)
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 6,
                              top: 2,
                              bottom: 8,
                            ),
                            child: _thinkingShimmerLabel(),
                          ),
                        if (!showThinking)
                          Container(
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
                            child: Text(
                              msg.text,
                              style: EaText.small.copyWith(
                                color: EaAdaptiveColor.bodyText(context),
                              ),
                            ),
                          ),
                      ],
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
    final provider = photo.isEmpty
        ? null
        : (photo.startsWith('http')
              ? NetworkImage(photo)
              : FileImage(File(photo)) as ImageProvider);

    return CircleAvatar(
      radius: 13,
      backgroundColor: EaColor.fore.withValues(alpha: 0.16),
      backgroundImage: provider,
      child: provider == null
          ? const Icon(Icons.person, size: 13, color: EaColor.fore)
          : null,
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
