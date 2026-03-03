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

class _SplashState extends State<Splash> {
  @override
  void initState() {
    super.initState();
    _startSplash();
  }

  void _startSplash() {
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted || !Bridge.isReady) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const Home()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EaColor.background,

      body: Stack(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,

                children: [
                  _brand(),

                  const SizedBox(height: 48),

                  _headline(),

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
        Text("Powered by", style: EaText.secondaryTranslucent),
        SizedBox(width: 10),
        Image(image: const AssetImage("assets/images/logo.png"), width: 32, height: 32),
        SizedBox(width: 6),
        Text("Nortify", style: EaText.primary),
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
                    fontSize: 48,
                    height: 1.05,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 16),

                Text(
                  "Everything connected.\nOne interface.",
                  style: EaText.secondary.copyWith(
                    color: EaColor.textSecondary,
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
