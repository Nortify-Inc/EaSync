/*!
 * @file splash.dart
 * @brief Initial loading screen and transition flow to home.
 * @param context Flutter context used for route navigation.
 * @return Splash widget and redirection flow.
 * @author Erick Radmann
 */

import 'handler.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';

import 'auth/security.dart';
import 'auth/service.dart';

class Splash extends StatefulWidget {
  const Splash({super.key});

  @override
  State<Splash> createState() => _SplashState();
}

class _SplashState extends State<Splash> with SingleTickerProviderStateMixin {
  final LocalAuthentication _localAuth = LocalAuthentication();
  late final AnimationController _fadeController;
  late final Animation<double> _fade;
  Timer? _tipTimer;
  DateTime _splashStartedAt = DateTime.now();
  int _activeStepIndex = 0;

  final List<_BootStepItem> _bootSteps = [
    _BootStepItem(id: 'core', title: 'Checking modules'),
    _BootStepItem(id: 'drivers', title: 'Initializing drivers'),
    _BootStepItem(id: 'identity', title: 'Validating identity'),
    _BootStepItem(id: 'aiRuntime', title: 'Loading AI runtime'),
    _BootStepItem(id: 'modelDownload', title: 'Downloading resources'),
    _BootStepItem(id: 'aiInit', title: 'Initializing engine'),
    _BootStepItem(id: 'finalize', title: 'Finalizing startup'),
  ];

  final List<String> _tips = const [
    'You can use the Profiles page to create profiles for auto apply states and grouping your devices by room, behavior and more.',
    'Use the Dashboard page to monitore your place, control devices and view statistics.',
    "If you're using EaSync in multiple devices, you can list the sessions opened and manage their permissions",
    'In the Account page, you can enable additional security with biometrics to protect who can access EaSync on this device.',
    'AI will observe and learn your patterns and provide personalized suggestions. You can disable it anytime in the Account page if you change your mind.',
    'Use the Manage page to register new devices, check their status and create custom names.',
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
    await _runStartupIdentityCheck();
    if (!mounted) return;

    if (Platform.isAndroid) {
      EaAppSettings.instance.aiEnabled = true;
      _showAiProgress = true;
      if (mounted) setState(() {});

      _markStepRunning('modelDownload', detail: 'Waiting for model stream…');
      final ok = await _runAndroidModelSetup();
      if (!ok) {
        EaAppSettings.instance.aiEnabled = false;
        _markStepFailed('aiInit', detail: 'AI disabled for this session');
        debugPrint('[splash] AI setup failed, continuing with AI disabled');
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

    _markStepRunning('finalize', detail: 'Final startup checks');
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
      _markStepSkipped('modelDownload', detail: 'Download not required');
      _markStepRunning('aiInit', detail: 'Configuring runtime…');
      setState(() {
        _showAiProgress = true;
        _aiMessage = 'Loading model…';
        _aiStatus = DownloadStatus.initializing;
      });
    } else {
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
          detail: '${(state.progress * 100).toStringAsFixed(1)}% Downloaded',
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

    _markStepSkipped('identity', detail: 'Waiting for login/session checks');
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

  Future<void> _runStartupIdentityCheck() async {
    _markStepRunning('identity', detail: 'Checking session state…');

    // Reset cached session gate so splash always evaluates current security state.
    await AppSecurityService.instance.clearSessionValidation();

    final loggedIn = await OAuthService.instance.isLoggedIn;
    if (!loggedIn) {
      _markStepSkipped('identity', detail: 'No authenticated session');
      return;
    }

    final security = await AppSecurityService.instance
        .readStartupSecurityState();
    if (!security.requiresBiometric) {
      _markStepDone('identity', detail: 'Identity gate not required');
      return;
    }

    final biometricOk = await _authenticateWithBiometrics();
    if (!biometricOk) {
      await OAuthService.instance.logout();
      _markStepFailed('identity', detail: 'Biometric validation failed');
      return;
    }

    _markStepDone('identity', detail: 'Identity validated');
  }

  Future<bool> _authenticateWithBiometrics() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      if (!supported || !canCheck) {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
              EaI18n.t(
                context,
                'Biometrics are enabled but unavailable on this device.',
              ),
            ),
          ),
        );
        return false;
      }

      return await _localAuth.authenticate(
        localizedReason: EaI18n.t(
          context,
          'Confirm your identity to unlock EaSync',
        ),
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } on PlatformException {
      return false;
    }
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
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
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
                value: ((safeIndex + 1) / _bootSteps.length),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 360;
        final labelSize = isCompact ? 11.5 : 12.0;
        final bodySize = isCompact ? 11.5 : 12.0;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 10 : 12,
            vertical: isCompact ? 9 : 10,
          ),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.lightbulb_outline,
                    size: 16,
                    color: EaColor.fore,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Tip:',
                    style: EaText.secondary.copyWith(
                      color: EaAdaptiveColor.bodyText(context),
                      fontWeight: FontWeight.w700,
                      fontSize: labelSize,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                child: Text(
                  EaI18n.t(context, _tips[_tipIndex]),
                  key: ValueKey<int>(_tipIndex),
                  softWrap: true,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: EaText.secondary.copyWith(
                    color: EaAdaptiveColor.secondaryText(context),
                    fontSize: bodySize,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
        return const Icon(
          Icons.error_outline,
          size: 14,
          color: Colors.redAccent,
        );
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
                Text(
                  "EaSync",
                  style: EaText.primary.copyWith(
                    color: EaAdaptiveColor.bodyText(context),
                    fontSize: 48,
                    height: 1.05,
                    fontWeight: FontWeight.w700,
                  ),
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

  _BootStepItem({required this.id, required this.title});
}
