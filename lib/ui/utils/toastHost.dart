import '../handler.dart';

class RecommendationToastHost extends StatefulWidget {
  final Widget child;

  const RecommendationToastHost({super.key, required this.child});

  @override
  State<RecommendationToastHost> createState() =>
      _RecommendationToastHostState();
}

class _RecommendationToastHostState extends State<RecommendationToastHost>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const Duration _dismissAnimDuration = Duration(milliseconds: 260);

  UsageRecommendation? _active;
  EaPlanTier _planTier = EaPlanTier.free;
  Timer? _pollTimer;
  bool _visible = false;
  double _life = 1.0;
  Timer? _lifeTimer;
  DateTime? _shownAt;
  StreamSubscription<HostTransferRequestNotice>? _hostRequestSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initPlanAndPolling();
    _hostRequestSub = TrustedPresenceService.instance.onHostTransferRequest
        .listen(_showHostRequestSnack);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _lifeTimer?.cancel();
    _hostRequestSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPlanAndPolling();
    }
  }

  void _showHostRequestSnack(HostTransferRequestNotice notice) {
    if (!mounted) return;

    final name = notice.requesterName.trim().isEmpty
        ? EaI18n.t(context, 'Unknown session')
        : notice.requesterName.trim();

    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 14),
          duration: const Duration(seconds: 7),
          content: Row(
            children: [
              const Icon(Icons.swap_horizontal_circle_outlined, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  EaI18n.t(
                    context,
                    'Host transfer request from {name}',
                    {'name': name},
                  ),
                  style: EaText.secondary.copyWith(
                    color: EaColor.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () {
                    messenger.hideCurrentSnackBar();
                    final nav = eaNavigatorKey.currentState;
                    if (nav == null) return;
                    nav.push(
                      MaterialPageRoute(
                        builder: (_) => const TrustedDevicesPage(),
                      ),
                    );
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.chevron_right_rounded, size: 32),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }

  Future<void> _initPlanAndPolling() async {
    _planTier = await EaPlanService.instance.readTier();
    if (!mounted) return;
    _restartPolling();
    _tryFetchAndShowRecommendation();
  }

  Future<void> _refreshPlanAndPolling() async {
    final next = await EaPlanService.instance.readTier();
    if (!mounted) return;
    if (next != _planTier) {
      setState(() => _planTier = next);
      _restartPolling();
    }
    _tryFetchAndShowRecommendation();
  }

  void _restartPolling() {
    _pollTimer?.cancel();

    if (_planTier == EaPlanTier.free) return;

    final period = _planTier == EaPlanTier.pro
        ? const Duration(seconds: 25)
        : const Duration(minutes: 4);

    _pollTimer =
        Timer.periodic(period, (_) => _tryFetchAndShowRecommendation());
  }

  Duration _lifeDurationForTier() {
    return _planTier == EaPlanTier.pro
        ? const Duration(seconds: 10)
        : const Duration(seconds: 8);
  }

  void _startLifeTimer() {
    _lifeTimer?.cancel();
    final total = _lifeDurationForTier();
    final started = DateTime.now();
    _shownAt = started;

    _lifeTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted || _shownAt == null) return;
      final elapsed = DateTime.now().difference(started);
      final ratio = 1 - (elapsed.inMilliseconds / total.inMilliseconds);
      final next = ratio.clamp(0.0, 1.0);

      if (next <= 0.0) {
        _dismissToast(reason: 'timeout');
        return;
      }

      setState(() => _life = next);
    });
  }

  void _emitLearningEvent(String type, {Map<String, dynamic>? payload}) {
    final event = <String, dynamic>{
      'type': type,
      'atMs': DateTime.now().millisecondsSinceEpoch,
    };

    final current = _active;
    if (current != null) {
      event['recommendation'] = {
        'title': current.title,
        'message': current.message,
        'uuid': current.uuid,
        'recommendedHour': current.recommendedHour,
        'confidence': current.confidence,
      };
    }

    if (payload != null) {
      event['payload'] = payload;
    }

    Bridge.sendFrontendLearningEvent(event);
  }

  void _tryFetchAndShowRecommendation() {
    if (!mounted || _planTier == EaPlanTier.free || _visible) return;

    UsageRecommendation? recommendation;
    try {
      recommendation = Bridge.usageRecommendation();
    } catch (_) {
      return;
    }
    if (recommendation == null) return;

    setState(() {
      _active = recommendation;
      _visible = true;
      _life = 1.0;
    });

    _emitLearningEvent('recommendation_shown');
    _startLifeTimer();
  }

  Future<void> _dismissToast({required String reason}) async {
    _lifeTimer?.cancel();
    if (!_visible) return;

    _emitLearningEvent('recommendation_dismissed', payload: {'reason': reason});

    setState(() => _visible = false);
    await Future.delayed(_dismissAnimDuration);

    if (!mounted) return;
    setState(() {
      _active = null;
      _life = 1.0;
    });
  }

  Future<void> _acceptRecommendation() async {
    _emitLearningEvent('recommendation_accepted');
    await _dismissToast(reason: 'accept');
  }

  @override
  Widget build(BuildContext context) {
    final recommendation = _active;

    return Stack(
      children: [
        widget.child,
        if (recommendation != null)
          Positioned(
            right: 12,
            top: MediaQuery.of(context).padding.top + 12,
            child: AnimatedSlide(
              duration: _dismissAnimDuration,
              curve: Curves.easeOutCubic,
              offset: _visible ? Offset.zero : const Offset(1.08, 0),
              child: Material(
                color: Colors.transparent,
                child: CustomPaint(
                  painter: _BorderLifePainter(progress: _life),
                  child: Container(
                    width: 320,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    decoration: BoxDecoration(
                      color: EaAdaptiveColor.surface(context),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: EaAdaptiveColor.border(context)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                recommendation.title,
                                style: EaText.secondary.copyWith(
                                  color: EaAdaptiveColor.bodyText(context),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () => _dismissToast(reason: 'close'),
                              borderRadius: BorderRadius.circular(999),
                              child: const Padding(
                                padding: EdgeInsets.all(2),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 16,
                                  color: EaColor.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          recommendation.message,
                          style: EaText.small.copyWith(
                            color: EaAdaptiveColor.secondaryText(context),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Colors.green),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                            ),
                            onPressed: _acceptRecommendation,
                            child: Text(
                              EaI18n.t(context, 'Accept'),
                              style: EaText.small.copyWith(
                                color: Colors.green,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _BorderLifePainter extends CustomPainter {
  final double progress;

  const _BorderLifePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final safe = progress.clamp(0.0, 1.0);
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
      const Radius.circular(14),
    );

    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = EaColor.fore.withValues(alpha: 0.16);
    canvas.drawRRect(rrect, base);

    final metric = (Path()..addRRect(rrect)).computeMetrics().first;
    final len = metric.length;
    final drawLen = len * safe;

    if (drawLen <= 0) return;

    final active = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = EaColor.fore;

    canvas.drawPath(metric.extractPath(0, drawLen), active);
  }

  @override
  bool shouldRepaint(covariant _BorderLifePainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
