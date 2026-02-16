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
      if (!mounted && !Bridge.isReady) return;

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
        Icon(Icons.blur_on, color: EaColor.fore, size: 28),

        const SizedBox(width: 8),

        Text("EaSync", style: EaText.primary),

        const SizedBox(width: 8),

        Padding(
          padding: const EdgeInsets.only(top: 18),

          child: Text("Powered by Nortify", style: EaText.secondaryTranslucent),
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
                  "Smart\nControl",
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
