/*!
 * @file home.dart
 * @brief Main screen with horizontal navigation across application modules.
 * @param index Virtual index of the current page in the `PageView`.
 * @return Navigation widgets and visual composition for the home screen.
 * @author Erick Radmann
 */

import 'dart:ui';

import 'package:easync/ui/agent.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth/security.dart';
import 'auth/service.dart';
import 'handler.dart';

List<DeviceInfo> devices = [];

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver {
  static const String _kAuthPhoto = 'account.auth.photo';
  static const int _kLoopItemCount = 1000000;
  static const int _kLoopSeed = 500000;
  static const double _kDragMinDistance = 14.0;

  final List<String> tabs = const [
    'Dashboard',
    'Profiles',
    'Manage',
    'Agent',
    'Account',
  ];

  final List<Widget> pages = const [
    Dashboard(),
    Profiles(),
    Manage(),
    Agent(),
    Account(),
  ];

  int selectedIndex = 0;
  late final PageController _pageController;
  late int _virtualPage;

  // Title offset removed: title will render at left during transitions.

  bool _pageAnimating = false;
  double _dragDistanceX = 0;
  String? _profilePhoto;

  final EaAppSettings _settings = EaAppSettings.instance;
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _wasBackgrounded = false;
  bool _securityPromptOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final int alignedSeed = _kLoopSeed - (_kLoopSeed % pages.length);
    _virtualPage = alignedSeed;
    _pageController = PageController(initialPage: _virtualPage);
    _loadProfilePhoto();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _wasBackgrounded = true;
      return;
    }

    if (state == AppLifecycleState.resumed && _wasBackgrounded) {
      _wasBackgrounded = false;
      Future<void>(() async {
        await _runResumeSecurityCheck();
      });
    }
  }

  Future<void> _runResumeSecurityCheck() async {
    if (!mounted || _securityPromptOpen) return;

    final loggedIn = await OAuthService.instance.isLoggedIn;
    if (!loggedIn || !mounted) return;

    final state = await AppSecurityService.instance.readStartupSecurityState();
    if (!state.hasAnyGate || !mounted) return;

    _securityPromptOpen = true;
    try {
      while (mounted) {
        if (state.requiresBiometric) {
          final biometricOk = await _authenticateWithBiometrics();
          if (!biometricOk) {
            final retry = await _showSecurityRetryDialog(
              title: 'Biometric authentication required',
              message: 'We could not verify your identity using biometrics.',
            );
            if (!retry) {
              await _signOutAndRestart();
              return;
            }
            continue;
          }
        }

        if (state.requiresAuthenticatorCode) {
          final otpOk = await _promptAndValidateAuthenticatorCode();
          if (!otpOk) {
            final retry = await _showSecurityRetryDialog(
              title: 'Authenticator app code required',
              message:
                  'A valid 6-digit code is required to continue to the dashboard.',
            );
            if (!retry) {
              await _signOutAndRestart();
              return;
            }
            continue;
          }
        }

        return;
      }
    } finally {
      _securityPromptOpen = false;
    }
  }

  Future<bool> _authenticateWithBiometrics() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      if (!supported || !canCheck) {
        if (!mounted) return false;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Biometrics are enabled but unavailable on this device.',
            ),
          ),
        );
        return false;
      }

      return await _localAuth.authenticate(
        localizedReason: 'Confirm your identity to unlock EaSync',
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

  Future<bool> _promptAndValidateAuthenticatorCode() async {
    var attempts = 0;
    while (mounted && attempts < 5) {
      attempts++;

      final normalized = await _askAuthenticatorCodeSheet();
      if (!mounted || normalized == null) return false;

      final ok = await AppSecurityService.instance.verifyAuthenticatorCode(
        normalized,
      );
      if (ok) return true;

      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(EaI18n.t(context, 'Invalid code. Try again.')),
        ),
      );
    }
    return false;
  }

  Future<String?> _askAuthenticatorCodeSheet() async {
    final controller = TextEditingController();
    var invalid = false;

    try {
      return await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setLocalState) {
              final bodyTextColor = EaAdaptiveColor.bodyText(context);
              final secondaryTextColor = EaAdaptiveColor.secondaryText(context);
              final borderColor = EaAdaptiveColor.border(context);

              return SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16,
                    16,
                    16 + MediaQuery.of(ctx).viewInsets.bottom,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: EaAdaptiveColor.surface(context),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: borderColor),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: EaColor.fore.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.security_rounded,
                                  color: EaColor.fore,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  EaI18n.t(context, 'Authenticator app'),
                                  style: EaText.primary.copyWith(
                                    color: bodyTextColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            EaI18n.t(
                              context,
                              'Enter your 6-digit verification code to continue.',
                            ),
                            style: EaText.small.copyWith(
                              color: secondaryTextColor,
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: controller,
                            autofocus: true,
                            keyboardType: TextInputType.number,
                            style: EaText.primary.copyWith(
                              color: bodyTextColor,
                              letterSpacing: 5,
                              fontWeight: FontWeight.w700,
                            ),
                            decoration: InputDecoration(
                              hintText: '123456',
                              hintStyle: EaText.primary.copyWith(
                                color: secondaryTextColor.withValues(alpha: 0.7),
                                letterSpacing: 5,
                              ),
                              filled: true,
                              fillColor: EaAdaptiveColor.field(context),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: borderColor),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(color: borderColor),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide: BorderSide(
                                  color: EaColor.fore.withValues(alpha: 0.85),
                                  width: 1.2,
                                ),
                              ),
                            ),
                          ),
                          if (invalid) ...[
                            const SizedBox(height: 8),
                            Text(
                              EaI18n.t(context, 'Invalid code.'),
                              style: EaText.small.copyWith(
                                color: Colors.redAccent,
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  child: Text(EaI18n.t(context, 'Cancel')),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: EaColor.fore,
                                    foregroundColor: EaColor.back,
                                  ),
                                  onPressed: () {
                                    final normalized = controller.text
                                        .replaceAll(RegExp(r'[^0-9]'), '');
                                    if (normalized.length != 6) {
                                      setLocalState(() => invalid = true);
                                      return;
                                    }
                                    Navigator.of(ctx).pop(normalized);
                                  },
                                  child: Text(EaI18n.t(context, 'Verify')),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  Future<bool> _showSecurityRetryDialog({
    required String title,
    required String message,
  }) async {
    final retry = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final borderColor = EaAdaptiveColor.border(context);
        final bodyTextColor = EaAdaptiveColor.bodyText(context);
        final secondaryTextColor = EaAdaptiveColor.secondaryText(context);

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: BorderSide(color: borderColor),
          ),
          backgroundColor: EaAdaptiveColor.surface(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.lock_clock_outlined,
                        color: Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        EaI18n.t(context, title),
                        style: EaText.primary.copyWith(
                          color: bodyTextColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  EaI18n.t(context, message),
                  style: EaText.secondary.copyWith(color: secondaryTextColor),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: Text(EaI18n.t(context, 'Sign out')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: EaColor.fore,
                          foregroundColor: EaColor.back,
                        ),
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: Text(EaI18n.t(context, 'Retry')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    return retry == true;
  }

  Future<void> _signOutAndRestart() async {
    await OAuthService.instance.logout();
    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const Splash()),
      (_) => false,
    );
  }

  Future<void> _loadProfilePhoto() async {
    final prefs = await SharedPreferences.getInstance();
    final photo = prefs.getString(_kAuthPhoto);
    if (!mounted) return;
    setState(() {
      _profilePhoto = photo;
    });
  }

  int _safeSelectedIndex() {
    if (pages.isEmpty) return 0;
    final len = pages.length;
    return ((selectedIndex % len) + len) % len;
  }

  int _realIndexFromVirtual(int virtualIndex) {
    if (pages.isEmpty) return 0;
    final len = pages.length;
    return ((virtualIndex % len) + len) % len;
  }

  Future<void> _goToIndex(int index) async {
    if (_pageAnimating || pages.isEmpty) return;

    final int current = _safeSelectedIndex();
    final int target = ((index % pages.length) + pages.length) % pages.length;
    if (target == current) return;

    int delta = target - current;
    if (delta.abs() > 1) {
      final forwardWrap = (target - current + pages.length) % pages.length;
      final backwardWrap = (current - target + pages.length) % pages.length;
      delta = forwardWrap <= backwardWrap ? 1 : -1;
    }

    _pageAnimating = true;
    final int nextVirtual = _virtualPage + delta;
    await _pageController.animateToPage(
      nextVirtual,
      duration: _settings.animationsEnabled
          ? const Duration(milliseconds: 220)
          : Duration.zero,
      curve: Curves.easeInOutSine,
    );

    if (!mounted) return;
    setState(() {
      _virtualPage = nextVirtual;
      selectedIndex = _realIndexFromVirtual(nextVirtual);
    });
    _pageAnimating = false;
  }

  void goNext() {
    _goToIndex(_safeSelectedIndex() + 1);
  }

  void goPrev() {
    _goToIndex(_safeSelectedIndex() - 1);
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    _dragDistanceX = 0;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    _dragDistanceX += details.delta.dx;
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_pageAnimating) return;
    if (_dragDistanceX.abs() < _kDragMinDistance) return;

    if (_dragDistanceX < 0) {
      goNext();
    } else {
      goPrev();
    }
  }

  Widget _buildTitle() {
    final idx = _safeSelectedIndex();
    final title = EaI18n.t(context, tabs[idx]);
    return AnimatedSwitcher(
      duration: _settings.animationsEnabled
          ? const Duration(milliseconds: 220)
          : Duration.zero,
      switchInCurve: Curves.easeInOutSine,
      switchOutCurve: Curves.easeInOutSine,
      layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
        final children = <Widget>[];
        children.addAll(previousChildren);
        if (currentChild != null) children.add(currentChild);
        return Stack(alignment: Alignment.centerLeft, children: children);
      },
      transitionBuilder: (child, animation) {
        final slide = Tween<Offset>(
          begin: const Offset(0, 0.08),
          end: Offset.zero,
        ).animate(animation);

        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: slide, child: child),
        );
      },
      child: Text(
        title,
        key: ValueKey(title),
        style: EaText.primary.copyWith(
          color: EaAdaptiveColor.bodyText(context),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    final idx = _safeSelectedIndex();
    final photoPath = (_profilePhoto ?? '').trim();

    ImageProvider? image;
    if (photoPath.isNotEmpty) {
      image = photoPath.startsWith('http')
          ? NetworkImage(photoPath)
          : FileImage(File(photoPath));
    }

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.only(left: 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _buildTitle(),
                    ),
                  ),
                ),
                Spacer(),
                if (idx == 4)
                  IconButton(
                    tooltip: EaI18n.t(context, 'Settings'),
                    icon: const Icon(
                      Icons.settings_outlined,
                      color: EaColor.fore,
                    ),
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const Settings()),
                      );
                      _loadProfilePhoto();
                    },
                  )
                else
                  GestureDetector(
                    onTap: () {
                      _goToIndex(4);
                    },
                    child: CircleAvatar(
                      radius: 14,
                      backgroundColor: EaColor.fore.withValues(alpha: 0.18),
                      backgroundImage: image,
                      child: image == null
                          ? const Icon(
                              Icons.person_outline_rounded,
                              size: 14,
                              color: EaColor.fore,
                            )
                          : null,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIndicator() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SizedBox(
        height: 36,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(pages.length, _buildDot),
        ),
      ),
    );
  }

  Widget _buildDot(int index) {
    final bool active = index == _safeSelectedIndex();
    return AnimatedContainer(
      duration: _settings.animationsEnabled
          ? const Duration(milliseconds: 220)
          : Duration.zero,
      curve: Curves.easeInOutSine,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      width: active ? 20 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: active
            ? EaColor.secondaryFore
            : EaAdaptiveColor.secondaryText(context),
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top + 56;
    const double bottomPadding = 52;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragStart: _onHorizontalDragStart,
              onHorizontalDragUpdate: _onHorizontalDragUpdate,
              onHorizontalDragEnd: _onHorizontalDragEnd,
              child: PageView.builder(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _kLoopItemCount,
                onPageChanged: (virtualIndex) {
                  if (!mounted) return;
                  setState(() {
                    _virtualPage = virtualIndex;
                    selectedIndex = _realIndexFromVirtual(virtualIndex);
                  });
                },
                itemBuilder: (context, virtualIndex) {
                  final realIndex = _realIndexFromVirtual(virtualIndex);
                  final content = TickerMode(
                    enabled: realIndex == _safeSelectedIndex(),
                    child: pages[realIndex],
                  );

                  if (!_settings.animationsEnabled) {
                    return RepaintBoundary(child: content);
                  }

                  return RepaintBoundary(
                    child: AnimatedBuilder(
                      animation: _pageController,
                      builder: (context, child) {
                        double page = _virtualPage.toDouble();
                        if (_pageController.hasClients &&
                            _pageController.position.hasPixels) {
                          page =
                              _pageController.page ?? _virtualPage.toDouble();
                        }
                        final distance = (virtualIndex - page).abs().clamp(
                          0.0,
                          1.0,
                        );
                        final t =
                            1.0 - Curves.easeInOutSine.transform(distance);
                        final scale = 0.985 + (0.015 * t);
                        final opacity = 0.9 + (0.1 * t);

                        const double pageMaxBlur = 3.0;
                        final double blurSigma = _settings.animationsEnabled
                            ? (pageMaxBlur * distance)
                            : 0.0;

                        return ImageFiltered(
                          imageFilter: ImageFilter.blur(
                            sigmaX: blurSigma,
                            sigmaY: blurSigma,
                          ),
                          child: Opacity(
                            opacity: opacity,
                            child: Transform.scale(scale: scale, child: child),
                          ),
                        );
                      },
                      child: content,
                    ),
                  );
                },
              ),
            ),
          ),
          _buildAppBar(),
          _buildIndicator(),
        ],
      ),
    );
  }
}
