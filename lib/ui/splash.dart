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

    // While still on the splash screen, await the native AI model/tokenizer
    // preload so its logs appear during splash. Don't block indefinitely;
    // timeout after 30s and continue to Home.
    try {
      await Bridge.modelReady.timeout(const Duration(seconds: 30));
      debugPrint('[splash] AI model preloaded during splash');
    } catch (e) {
      debugPrint('[splash] AI model preload timed out/failed: $e');
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const Home()),
    );
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
                ],
              ),
            ),
          ),
        ],
      ),
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
