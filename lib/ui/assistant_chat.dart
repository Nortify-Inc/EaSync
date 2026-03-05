/*!
 * @file assistant_chat.dart
 * @brief EaSync assistant page focused on chat and outside temperature only.
 * @param No external parameters.
 * @return Stateful chat interface with quick weather context.
 * @author Erick Radmann
 */

import 'dart:math';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'handler.dart';
import 'widgets/skeleton.dart';

class AssistantChat extends StatefulWidget {
  const AssistantChat({super.key});

  @override
  State<AssistantChat> createState() => _AssistantChatState();
}

class _AssistantChatState extends State<AssistantChat>
    with TickerProviderStateMixin {
  static const String _kOutsideTempCache = 'assistant.outside_temp_cache';
  static const String _kOutsideTempUpdatedAt =
      'assistant.outside_temp_updated_at';

  final EaAppSettings _settings = EaAppSettings.instance;
  final TextEditingController _commandController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  final List<_ChatMessage> _messages = [];

  bool _loadingOutside = true;
  bool _sending = false;
  bool _typingIndicator = false;
  double _outsideTemp = 25.0;
  DateTime? _outsideUpdatedAt;

  late final AnimationController _thinkingPulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _thinkingPulse.dispose();
    _commandController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _loadOutsideTemperature();
    _appendAssistant(
      'Olá! Sou o EaSync Assistant. Posso te ajudar com comandos para seus dispositivos.',
    );
  }

  Future<void> _loadOutsideTemperature() async {
    setState(() => _loadingOutside = true);

    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getDouble(_kOutsideTempCache);
    final cachedAtMs = prefs.getInt(_kOutsideTempUpdatedAt);

    if (cached != null) {
      _outsideTemp = cached;
      if (cachedAtMs != null) {
        _outsideUpdatedAt = DateTime.fromMillisecondsSinceEpoch(cachedAtMs);
      }
    }

    await Future.delayed(
      Duration(milliseconds: _settings.animationsEnabled ? 450 : 0),
    );

    final inferred = _inferOutsideTemperature();

    _outsideTemp = inferred;
    _outsideUpdatedAt = DateTime.now();

    await prefs.setDouble(_kOutsideTempCache, _outsideTemp);
    await prefs.setInt(
      _kOutsideTempUpdatedAt,
      _outsideUpdatedAt!.millisecondsSinceEpoch,
    );

    if (!mounted) return;
    setState(() => _loadingOutside = false);
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

    final base = _outsideTemp;
    final drift = (Random().nextDouble() * 1.6) - 0.8;
    return (base + drift).clamp(-10, 48);
  }

  Future<void> _send() async {
    final raw = _commandController.text.trim();
    if (raw.isEmpty || _sending) return;

    if (_settings.hapticsEnabled) {
      HapticFeedback.lightImpact();
    }

    _commandController.clear();
    _appendUser(raw);

    setState(() {
      _sending = true;
      _typingIndicator = true;
    });

    String reply;
    try {
      reply = (await Bridge.aiExecuteCommandAsync(raw)).trim();
      if (reply.isEmpty) {
        reply =
            'Recebi sua mensagem, mas não consegui gerar uma resposta agora.';
      }
    } catch (_) {
      reply =
          'Falha ao processar no backend de IA. Tente novamente em instantes.';
    }

    if (!mounted) return;
    setState(() {
      _typingIndicator = false;
      _sending = false;
    });

    _appendAssistant(reply);
  }

  void _appendUser(String text) {
    setState(() {
      _messages.add(_ChatMessage(role: _Role.user, text: text));
    });
    _scrollToBottom();
  }

  void _appendAssistant(String text) {
    setState(() {
      _messages.add(_ChatMessage(role: _Role.assistant, text: text));
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  IconData _outsideIcon() {
    if (_outsideTemp >= 31) return Icons.wb_sunny_rounded;
    if (_outsideTemp >= 25) return Icons.wb_sunny_outlined;
    if (_outsideTemp >= 18) return Icons.cloud_outlined;
    return Icons.ac_unit_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final compact = _settings.compactMode;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 14 : 20,
          8,
          compact ? 14 : 20,
          12,
        ),
        child: Column(
          children: [
            _outsideTemperatureTile(),
            const SizedBox(height: 10),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: EaAdaptiveColor.surface(context),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: EaAdaptiveColor.border(context)),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.chat_bubble_outline_rounded,
                            color: EaColor.fore,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Assistant chat',
                            style: EaText.secondary.copyWith(
                              fontWeight: FontWeight.w700,
                              color: EaAdaptiveColor.bodyText(context),
                            ),
                          ),
                          const Spacer(),
                          if (_typingIndicator)
                            FadeTransition(
                              opacity: CurvedAnimation(
                                parent: _thinkingPulse,
                                curve: Curves.easeInOut,
                              ),
                              child: Text(
                                'Thinking...',
                                style: EaText.small.copyWith(
                                  color: EaAdaptiveColor.secondaryText(context),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: EaAdaptiveColor.border(context)),
                    Expanded(child: _buildMessageList()),
                    _composer(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _outsideTemperatureTile() {
    return Container(
      decoration: BoxDecoration(
        color: EaAdaptiveColor.surface(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: EaAdaptiveColor.border(context)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: EaColor.fore.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(_outsideIcon(), color: EaColor.fore, size: 18),
        ),
        title: Text(
          'Outside temperature',
          style: EaText.secondary.copyWith(
            color: EaAdaptiveColor.bodyText(context),
          ),
        ),
        subtitle: _loadingOutside && _settings.skeletonEnabled
            ? const Padding(
                padding: EdgeInsets.only(top: 4),
                child: EaSkeleton(width: 140, height: 12),
              )
            : Text(
                '${_outsideTemp.toStringAsFixed(1)} °C'
                '${_outsideUpdatedAt == null ? '' : ' • updated ${_outsideUpdatedAt!.hour.toString().padLeft(2, '0')}:${_outsideUpdatedAt!.minute.toString().padLeft(2, '0')}'}',
                style: EaText.small.copyWith(
                  color: EaAdaptiveColor.secondaryText(context),
                ),
              ),
        trailing: IconButton(
          onPressed: _loadingOutside ? null : _loadOutsideTemperature,
          icon: const Icon(Icons.refresh_rounded, color: EaColor.fore),
        ),
      ),
    );
  }

  Widget _buildMessageList() {
    if (_messages.isEmpty && _settings.skeletonEnabled) {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: const [
          Align(
            alignment: Alignment.centerLeft,
            child: EaSkeleton(width: 190, height: 34),
          ),
          SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: EaSkeleton(width: 140, height: 34),
          ),
        ],
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: _messages.length,
      itemBuilder: (context, i) {
        final msg = _messages[i];
        final user = msg.role == _Role.user;

        return EaFadeSlideIn(
          duration: _settings.animationsEnabled
              ? EaMotion.normal
              : Duration.zero,
          begin: user ? const Offset(0.03, 0) : const Offset(-0.03, 0),
          child: Align(
            alignment: user ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              constraints: const BoxConstraints(maxWidth: 480),
              decoration: BoxDecoration(
                color: user
                    ? EaColor.fore.withValues(alpha: 0.18)
                    : EaAdaptiveColor.field(context),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: EaAdaptiveColor.border(context)),
              ),
              child: Text(
                msg.text,
                style: EaText.small.copyWith(
                  color: EaAdaptiveColor.bodyText(context),
                ),
              ),
            ),
          ),
        );
      },
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
                hintText: 'Type a command or ask a question...',
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
          AnimatedContainer(
            duration: EaMotion.fast,
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              color: _sending ? EaColor.secondaryFore : EaColor.fore,
              borderRadius: BorderRadius.circular(14),
            ),
            child: IconButton(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: EaColor.back,
                      ),
                    )
                  : const Icon(Icons.send_rounded, color: EaColor.back),
            ),
          ),
        ],
      ),
    );
  }
}

enum _Role { user, assistant }

class _ChatMessage {
  final _Role role;
  final String text;

  const _ChatMessage({required this.role, required this.text});
}
