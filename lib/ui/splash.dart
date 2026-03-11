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
  late final AnimationController _fadeController;
  late final Animation<double> _fade;

  // AI download state
  DownloadStatus _aiStatus = DownloadStatus.checking;
  double _aiProgress = 0.0;
  String _aiMessage = '';
  bool _showAiProgress = false;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _fade = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();
    _startSplash();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _startSplash() async {
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    if (!Bridge.isReady) {
      try {
        await Bridge.init().timeout(const Duration(seconds: 5));
      } catch (_) {}
    }

    // On Android, run the downloader flow instead of waiting on modelReady
    if (Platform.isAndroid) {
      await _runAndroidModelSetup();
    } else {
      // Desktop/iOS: model is bundled, just wait for preload
      try {
        await Bridge.modelReady.timeout(const Duration(seconds: 30));
        debugPrint('[splash] AI model preloaded during splash');
      } catch (e) {
        debugPrint('[splash] AI model preload timed out/failed: $e');
      }
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const Home()),
    );
  }

  Future<void> _runAndroidModelSetup() async {
    // Check if model already downloaded — skip progress UI if so
    final ready = await Downloader.isReady();
    if (ready) {
      // Still need to set data dir + initialize
      setState(() {
        _showAiProgress = true;
        _aiMessage = 'Loading model…';
        _aiStatus = DownloadStatus.initializing;
      });
    } else {
      setState(() => _showAiProgress = true);
    }

    await for (final state in Downloader().ensure()) {
      if (!mounted) return;
      setState(() {
        _aiStatus = state.status;
        _aiProgress = state.progress;
        _aiMessage = state.message;
      });

      if (state.isError) {
        // Show error briefly then proceed anyway (graceful degradation)
        await Future.delayed(const Duration(seconds: 2));
        return;
      }

      if (state.isDone) return;
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
                  const Spacer(),
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
