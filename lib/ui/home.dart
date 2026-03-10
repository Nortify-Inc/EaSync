/*!
 * @file home.dart
 * @brief Main screen with horizontal navigation across application modules.
 * @param index Virtual index of the current page in the `PageView`.
 * @return Navigation widgets and visual composition for the home screen.
 * @author Erick Radmann
 */

import 'dart:ui';

import 'package:easync/ui/assistant_chat.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'handler.dart';

List<DeviceInfo> devices = [];

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  static const String _kAuthPhoto = 'account.auth.photo';
  static const int _kLoopItemCount = 1000000;
  static const int _kLoopSeed = 500000;
  static const double _kDragMinDistance = 14.0;

  final List<String> tabs = const [
    'Dashboard',
    'Profiles',
    'Manage',
    'Assistant',
    'Account',
  ];

  final List<Widget> pages = const [
    Dashboard(),
    Profiles(),
    Manage(),
    AssistantChat(),
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

  @override
  void initState() {
    super.initState();
    final int alignedSeed = _kLoopSeed - (_kLoopSeed % pages.length);
    _virtualPage = alignedSeed;
    _pageController = PageController(initialPage: _virtualPage);
    _loadProfilePhoto();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
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
                    child: Align(alignment: Alignment.centerLeft, child: _buildTitle()),
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
                                imageFilter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
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
