/*!
 * @file splash.dart
 * @brief Initial loading screen and transition flow to home.
 * @param context Flutter context used for route navigation.
 * @return Splash widget and redirection flow.
 * @author Erick Radmann
 */

import 'handler.dart';

class Splash extends StatefulWidget {
  const Splash({super.key});

  @override
  State<Splash> createState() => _SplashState();
}

class _SplashState extends State<Splash> with SingleTickerProviderStateMixin {
  bool _aiAllowed = false;
  late final AnimationController _fadeController;
  late final Animation<double> _fade;
  Timer? _tipTimer;
  DateTime _splashStartedAt = DateTime.now();
  int _activeStepIndex = 0;

  final List<_BootStepItem> _bootSteps = [
    _BootStepItem(id: 'core', title: 'Checking modules'),
    _BootStepItem(id: 'drivers', title: 'Initializing drivers'),
    _BootStepItem(id: 'aiRuntime', title: 'Loading AI runtime'),
    _BootStepItem(id: 'modelCache', title: 'Checking local model'),
    _BootStepItem(id: 'modelDownload', title: 'Downloading AI model'),
    _BootStepItem(id: 'aiInit', title: 'Initializing AI engine'),
    _BootStepItem(id: 'finalize', title: 'Finalizing startup'),
  ];

  final List<String> _tips = const [
    'Use shorter prompts first. They warm up generation and reduce initial latency.',
    'If AI setup fails, you can still control devices normally and retry later.',
    'A stable Wi-Fi connection makes first model download significantly faster.',
    'Keeping at least 1.5GB free storage avoids model write interruptions.',
    'The assistant improves when prompts are explicit: device + action + intent.',
    'If responses feel vague, add context like room, device name, and desired outcome.',
    'During first run, keep the app open so model initialization can finish cleanly.',
    'You can keep using device controls while AI remains disabled.',
  ];
  int _tipIndex = 0;

  static const Duration _tipSwapInterval = Duration(seconds: 5);
  static const Duration _stepCharmDelay = Duration(milliseconds: 380);
  static const Duration _minSplashDuration = Duration(seconds: 6);
  static const Duration _finalCharmDelay = Duration(milliseconds: 700);

  // AI download state
  DownloadStatus _aiStatus = DownloadStatus.checking;
  double _aiProgress = 0.0;
  String _aiMessage = '';
  bool _showAiProgress = false;

  @override
  void initState() {
    super.initState();
    _splashStartedAt = DateTime.now();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _fade = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();
    _tipTimer = Timer.periodic(_tipSwapInterval, (_) {
      if (!mounted) return;
      setState(() {
        _tipIndex = (_tipIndex + 1) % _tips.length;
      });
    });
    _startSplash();
  }

  @override
  void dispose() {
    _tipTimer?.cancel();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _startSplash() async {
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;

    await _runStartupChecks();

    if (Platform.isAndroid) {
      final allow = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(EaI18n.t(context, 'Complete experience?')),
          content: Text(
            EaI18n.t(
              context,
              'To use the AI assistant, you need to download the model (~700MB). This may be heavy on some devices. Do you want to download and enable the assistant?',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(EaI18n.t(context, 'No, skip')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(EaI18n.t(context, 'Yes, I want AI')),
            ),
          ],
        ),
      );

      _aiAllowed = allow == true;
      EaAppSettings.instance.aiEnabled = _aiAllowed;
      _showAiProgress = _aiAllowed;
      if (mounted) setState(() {});

      if (_aiAllowed) {
        _markStepRunning('modelDownload', detail: 'Waiting for model stream…');
        final ok = await _runAndroidModelSetup();
        if (!ok) {
          _aiAllowed = false;
          EaAppSettings.instance.aiEnabled = false;
          _markStepFailed('aiInit', detail: 'AI disabled for this session');
          debugPrint('[splash] AI setup failed, continuing with AI disabled');
        }
      } else {
        _markStepSkipped('modelDownload', detail: 'Skipped by user');
        _markStepSkipped('aiInit', detail: 'Skipped by user');
      }
    } else {
      _markStepRunning('aiInit', detail: 'Waiting for runtime preload…');
      Future<void>(() async {
        try {
          await Bridge.modelReady.timeout(const Duration(seconds: 30));
          _markStepDone('aiInit', detail: 'Runtime preloaded');
          debugPrint('[splash] AI model preloaded in background');
        } catch (e) {
          _markStepFailed('aiInit', detail: 'Preload failed: $e');
          debugPrint('[splash] AI model preload timed out/failed: $e');
        }
      });
      EaAppSettings.instance.aiEnabled = true;
    }

    _markStepDone('finalize', detail: 'Opening home');
    await Future.delayed(_finalCharmDelay);

    final elapsed = DateTime.now().difference(_splashStartedAt);
    if (elapsed < _minSplashDuration) {
      await Future.delayed(_minSplashDuration - elapsed);
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const Home()),
    );
  }

  Future<bool> _runAndroidModelSetup() async {
    final ready = await Downloader.isReady();
    if (ready) {
      // Model is already local; just configure data dir and initialize runtime.
      _markStepDone('modelCache', detail: 'Model found locally');
      _markStepSkipped('modelDownload', detail: 'Download not required');
      _markStepRunning('aiInit', detail: 'Configuring runtime…');
      setState(() {
        _showAiProgress = true;
        _aiMessage = 'Loading model…';
        _aiStatus = DownloadStatus.initializing;
      });
    } else {
      _markStepDone('modelCache', detail: 'Model not found locally');
      _markStepRunning('modelDownload', detail: 'Starting download…');
      setState(() => _showAiProgress = true);
    }

    await for (final state in Downloader().ensure()) {
      if (!mounted) return false;
      setState(() {
        _aiStatus = state.status;
        _aiProgress = state.progress;
        _aiMessage = state.message;
      });

      if (state.status == DownloadStatus.downloading) {
        _markStepRunning(
          'modelDownload',
          detail: '${(state.progress * 100).toStringAsFixed(1)}% downloaded',
        );
      } else if (state.status == DownloadStatus.initializing) {
        _markStepDone('modelDownload', detail: 'Model downloaded');
        _markStepRunning('aiInit', detail: 'Initializing AI runtime…');
      }

      if (state.isError) {
        if (_aiStatus == DownloadStatus.downloading ||
            state.status == DownloadStatus.downloading) {
          _markStepFailed('modelDownload', detail: state.message);
        } else {
          _markStepFailed('aiInit', detail: state.message);
        }
        await Future.delayed(const Duration(seconds: 2));
        return false;
      }

      if (state.isDone) {
        _markStepDone('aiInit', detail: 'AI ready');
        return true;
      }
    }

    return false;
  }

  Future<void> _runStartupChecks() async {
    _markStepRunning('core', detail: 'Loading native core…');
    try {
      if (!Bridge.isReady) {
        await Bridge.init().timeout(const Duration(seconds: 5));
      }
      _markStepDone('core', detail: 'Core modules online');
    } catch (e) {
      _markStepFailed('core', detail: 'Core init failed: $e');
    }
    await Future.delayed(_stepCharmDelay);

    _markStepRunning('drivers', detail: 'Checking registered drivers…');
    try {
      if (Bridge.isReady) {
        final devices = Bridge.listDevices();
        var online = 0;
        for (final d in devices) {
          try {
            if (Bridge.isDeviceAvailable(d.uuid)) online++;
          } catch (_) {}
        }
        _markStepDone(
          'drivers',
          detail: devices.isEmpty
              ? 'No devices registered'
              : '$online/${devices.length} reachable',
        );
      } else {
        _markStepSkipped('drivers', detail: 'Core unavailable');
      }
    } catch (e) {
      _markStepFailed('drivers', detail: 'Driver check failed: $e');
    }
    await Future.delayed(_stepCharmDelay);

    _markStepRunning('aiRuntime', detail: 'Inspecting AI runtime symbols…');
    final hasRuntimeSymbols = aiInitialize != null && aiSetDataDir != null;
    if (hasRuntimeSymbols) {
      _markStepDone('aiRuntime', detail: 'AI runtime symbols available');
    } else {
      _markStepFailed('aiRuntime', detail: 'AI runtime symbols missing');
    }
    await Future.delayed(_stepCharmDelay);

    _markStepRunning('modelCache', detail: 'Scanning local cache…');
    try {
      final ready = await Downloader.isReady();
      _markStepDone(
        'modelCache',
        detail: ready ? 'Cached model found' : 'Model will be downloaded',
      );
    } catch (e) {
      _markStepFailed('modelCache', detail: 'Cache check failed: $e');
    }
    await Future.delayed(_stepCharmDelay);
  }

  void _markStepRunning(String id, {String? detail}) {
    _updateStep(id, _BootStepState.running, detail: detail);
  }

  void _markStepDone(String id, {String? detail}) {
    _updateStep(id, _BootStepState.done, detail: detail);
  }

  void _markStepFailed(String id, {String? detail}) {
    _updateStep(id, _BootStepState.failed, detail: detail);
  }

  void _markStepSkipped(String id, {String? detail}) {
    _updateStep(id, _BootStepState.skipped, detail: detail);
  }

  void _updateStep(String id, _BootStepState state, {String? detail}) {
    final index = _bootSteps.indexWhere((s) => s.id == id);
    if (index < 0) return;

    if (!mounted) return;
    setState(() {
      _activeStepIndex = index;
      _bootSteps[index].state = state;
      if (detail != null && detail.isNotEmpty) {
        _bootSteps[index].detail = detail;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FadeTransition(opacity: _fade, child: _brand()),
                  const SizedBox(height: 48),
                  FadeTransition(opacity: _fade, child: _headline()),
                  const SizedBox(height: 26),
                  FadeTransition(opacity: _fade, child: _bootChecklist()),
                  const Spacer(),
                  FadeTransition(opacity: _fade, child: _tipTile()),
                  const SizedBox(height: 12),
                  if (_showAiProgress)
                    FadeTransition(opacity: _fade, child: _aiProgressWidget()),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _aiProgressWidget() {
    final isDownloading = _aiStatus == DownloadStatus.downloading;
    final isError = _aiStatus == DownloadStatus.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (!isError)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: EaColor.fore,
                ),
              ),
            if (isError)
              Icon(Icons.error_outline, size: 14, color: Colors.redAccent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _aiMessage,
                style: EaText.secondary.copyWith(
                  color: isError
                      ? Colors.redAccent
                      : EaAdaptiveColor.secondaryText(context),
                  fontSize: 12,
                ),
              ),
            ),
            if (isDownloading)
              Text(
                '${(_aiProgress * 100).toStringAsFixed(1)}%',
                style: EaText.secondary.copyWith(
                  color: EaAdaptiveColor.secondaryText(context),
                  fontSize: 12,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: isDownloading ? _aiProgress : null,
            minHeight: 3,
            backgroundColor: EaAdaptiveColor.secondaryText(
              context,
            ).withValues(alpha: 0.15),
            valueColor: AlwaysStoppedAnimation<Color>(
              isError ? Colors.redAccent : EaColor.fore,
            ),
          ),
        ),
      ],
    );
  }

  Widget _bootChecklist() {
    final safeIndex = _activeStepIndex.clamp(0, _bootSteps.length - 1);
    final step = _bootSteps[safeIndex];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: EaAdaptiveColor.field(context).withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: EaAdaptiveColor.border(context)),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: Column(
          key: ValueKey<String>('${step.id}-${step.state.name}-${step.detail}'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _stepIcon(step.state),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    step.title,
                    style: EaText.secondary.copyWith(
                      color: EaAdaptiveColor.bodyText(context),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: EaColor.fore.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${safeIndex + 1}/${_bootSteps.length}',
                    style: EaText.secondary.copyWith(
                      color: EaAdaptiveColor.bodyText(context),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              step.detail.isNotEmpty ? step.detail : 'Working…',
              style: EaText.secondary.copyWith(
                color: EaAdaptiveColor.secondaryText(context),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: step.state == _BootStepState.running
                    ? null
                    : ((safeIndex + 1) / _bootSteps.length),
                minHeight: 4,
                backgroundColor: EaAdaptiveColor.secondaryText(
                  context,
                ).withValues(alpha: 0.14),
                valueColor: AlwaysStoppedAnimation<Color>(
                  step.state == _BootStepState.failed
                      ? Colors.redAccent
                      : EaColor.fore,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tipTile() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            EaColor.fore.withValues(alpha: 0.22),
            EaAdaptiveColor.field(context).withValues(alpha: 0.75),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: EaAdaptiveColor.border(context)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lightbulb_outline, size: 16, color: EaColor.fore),
          const SizedBox(width: 8),
          Text(
            'Tip:',
            style: EaText.secondary.copyWith(
              color: EaAdaptiveColor.bodyText(context),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              child: Text(
                _tips[_tipIndex],
                key: ValueKey<int>(_tipIndex),
                style: EaText.secondary.copyWith(
                  color: EaAdaptiveColor.secondaryText(context),
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepIcon(_BootStepState state) {
    switch (state) {
      case _BootStepState.running:
        return const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case _BootStepState.done:
        return const Icon(Icons.check_circle, size: 14, color: Colors.green);
      case _BootStepState.failed:
        return const Icon(Icons.error_outline, size: 14, color: Colors.redAccent);
      case _BootStepState.skipped:
        return Icon(
          Icons.remove_circle_outline,
          size: 14,
          color: EaAdaptiveColor.secondaryText(context),
        );
      case _BootStepState.pending:
        return Icon(
          Icons.radio_button_unchecked,
          size: 14,
          color: EaAdaptiveColor.secondaryText(context),
        );
    }
  }

  Widget _brand() {
    return Row(
      children: [
        Text(
          EaI18n.t(context, 'Powered by'),
          style: EaText.secondary.copyWith(
            color: EaAdaptiveColor.secondaryText(context),
          ),
        ),
        SizedBox(width: 10),
        Image(
          image: const AssetImage("assets/images/logo.png"),
          width: 32,
          height: 32,
        ),
        SizedBox(width: 6),
        Text(
          "Nortify",
          style: EaText.primary.copyWith(
            color: EaAdaptiveColor.bodyText(context),
          ),
        ),
      ],
    );
  }

  Widget _headline() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: -120,
              top: -100,
              child: Container(
                width: 360,
                height: 360,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      EaColor.fore.withValues(alpha: 0.35),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Image(
                      image: const AssetImage("assets/images/easyncLogo.png"),
                      width: 50,
                      height: 50,
                    ),
                    Text(
                      "EaSync",
                      style: EaText.primary.copyWith(
                        color: EaAdaptiveColor.bodyText(context),
                        fontSize: 48,
                        height: 1.05,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  EaI18n.t(context, 'Everything connected.\nOne interface.'),
                  style: EaText.secondary.copyWith(
                    color: EaAdaptiveColor.secondaryText(context),
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

enum _BootStepState { pending, running, done, failed, skipped }

class _BootStepItem {
  final String id;
  final String title;
  _BootStepState state = _BootStepState.pending;
  String detail = '';

  _BootStepItem({
    required this.id,
    required this.title,
  });
}
