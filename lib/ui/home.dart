/*!
 * @file home.dart
 * @brief Main screen with horizontal navigation across application modules.
 * @param index Virtual index of the current page in the `PageView`.
 * @return Navigation widgets and visual composition for the home screen.
 * @author Erick Radmann
 */

import 'dart:ui';
import 'package:flutter/material.dart';
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

  int selectedIndex = 0;
  int _transitionDirection = 1;
  int _transitionDurationMs = 300;
  double _dragVisualOffset = 0;
  StreamSubscription<CoreEventData>? _eventSub;

  late double screenWidth;
  String? _profilePhoto;
  double dragStartX = 0;
  double dragDelta = 0;
  double _dragPeakDelta = 0;

  final List<Widget> pages = [
    const Dashboard(),
    const Profiles(),
    const AssistantChat(),
    const Manage(),
    const Account(),
  ];

  final List<String> tabs = [
    'Dashboard',
    'Profiles',
    'Assistant',
    'Manage',
    'Account',
  ];

  @override
  void initState() {
    super.initState();
    _loadProfilePhoto();
    _eventSub = Bridge.onEvents.listen((_) {
      setState(() {});
    });
  }

  Future<void> _loadProfilePhoto() async {
    final prefs = await SharedPreferences.getInstance();
    _profilePhoto = prefs.getString(_kAuthPhoto);
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    screenWidth = MediaQuery.of(context).size.width;
  }

  void goNext() {
    _commitTransition((selectedIndex + 1) % pages.length, direction: 1);
  }

  void goPrev() {
    _commitTransition(
      (selectedIndex - 1 + pages.length) % pages.length,
      direction: -1,
    );
  }

  void _goToIndex(int index) {
    if (index == selectedIndex) return;
    _commitTransition(index, direction: index > selectedIndex ? 1 : -1);
    _loadProfilePhoto();
  }

  void _commitTransition(
    int nextIndex, {
    required int direction,
    double velocity = 0,
  }) {
    final absV = velocity.abs();
    final ms = absV > 2200
        ? 180
        : absV > 1400
        ? 220
        : absV > 700
        ? 260
        : 320;

    _transitionDirection = direction;
    setState(() {
      _transitionDurationMs = ms;
      _dragVisualOffset = 0;
      selectedIndex = nextIndex;
    });
    _loadProfilePhoto();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }

  Widget _buildBlurTitle() {
    final title = EaI18n.t(context, tabs[selectedIndex]);

    return TweenAnimationBuilder<double>(
      key: ValueKey(title),
      tween: Tween<double>(begin: 3, end: 0),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      builder: (context, blur, _) {
        return ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Text(
            title,
            style: EaText.primary.copyWith(
              color: EaAdaptiveColor.bodyText(context),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAppBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            height: 56,
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                const Spacer(flex: 1),
                _buildBlurTitle(),
                const Spacer(flex: 100),
                if (selectedIndex == 4)
                  IconButton(
                    tooltip: EaI18n.t(context, 'Settings'),
                    icon: const Icon(
                      Icons.settings_outlined,
                      color: EaColor.fore,
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const Settings()),
                      );
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
                      backgroundImage: (_profilePhoto ?? '').trim().isEmpty
                          ? null
                          : (_profilePhoto!.startsWith('http')
                                ? NetworkImage(_profilePhoto!)
                                : FileImage(File(_profilePhoto!))
                                      as ImageProvider),
                      child: (_profilePhoto ?? '').trim().isEmpty
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
      bottom: 0,
      left: 0,
      right: 0,
      child: SizedBox(
        height: 36,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(pages.length, (index) => _buildDot(index)),
        ),
      ),
    );
  }

  Widget _buildDot(int index) {
    final bool active = index == selectedIndex;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      width: active ? 20 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: active
            ? EaColor.secondaryFore
            : EaAdaptiveColor.secondaryText(context),
        borderRadius: BorderRadius.circular(20),
        boxShadow: active
            ? [
                BoxShadow(
                  color: EaColor.fore,
                  blurRadius: 6,
                  offset: const Offset(0, 0),
                ),
              ]
            : [
                BoxShadow(
                  color: EaAdaptiveColor.border(context),
                  blurRadius: 2,
                ),
              ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top + 56;
    final double bottomPadding = 36 + 16;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (d) {
              dragStartX = d.globalPosition.dx;
              dragDelta = 0;
              _dragPeakDelta = 0;
            },
            onHorizontalDragUpdate: (d) {
              dragDelta = d.globalPosition.dx - dragStartX;
              if (dragDelta.abs() > _dragPeakDelta.abs()) {
                _dragPeakDelta = dragDelta;
              }
              setState(() => _dragVisualOffset = dragDelta.clamp(-86, 86));
            },
            onHorizontalDragEnd: (d) {
              final vx = d.primaryVelocity ?? 0;
              final hasDistanceIntent = _dragPeakDelta.abs() > 40;
              final hasVelocityIntent = vx.abs() > 900;

              if (!hasVelocityIntent && !hasDistanceIntent) {
                setState(() => _dragVisualOffset = 0);
                dragDelta = 0;
                _dragPeakDelta = 0;
                return;
              }

              final direction = hasDistanceIntent
                  ? (_dragPeakDelta < 0 ? 1 : -1)
                  : (vx < 0 ? 1 : -1);

              if (direction == 1) {
                _commitTransition(
                  (selectedIndex + 1) % pages.length,
                  direction: 1,
                  velocity: vx,
                );
              } else {
                _commitTransition(
                  (selectedIndex - 1 + pages.length) % pages.length,
                  direction: -1,
                  velocity: vx,
                );
              }

              dragDelta = 0;
              _dragPeakDelta = 0;
            },
            child: Padding(
              padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
              child: ClipRect(
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0, end: _dragVisualOffset),
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  builder: (context, dragVisual, child) {
                    return Transform.translate(
                      offset: Offset(dragVisual * 0.16, 0),
                      child: child,
                    );
                  },
                  child: AnimatedSwitcher(
                    duration: Duration(milliseconds: _transitionDurationMs),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInOutCubic,
                    transitionBuilder: (child, animation) {
                      final key = child.key;
                      final isIncoming =
                          key is ValueKey<int> && key.value == selectedIndex;

                      final fade = CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOut,
                      );

                      final eased = CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeInOutCubicEmphasized,
                      );

                      final horizontalShift =
                          Tween<Offset>(
                            begin: isIncoming
                                ? Offset(_transitionDirection * 0.14, 0)
                                : Offset.zero,
                            end: isIncoming
                                ? Offset.zero
                                : Offset(-_transitionDirection * 0.12, 0),
                          ).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeInOutCubic,
                            ),
                          );

                      final subtleLift =
                          Tween<Offset>(
                            begin: isIncoming
                                ? const Offset(0, 0.02)
                                : Offset.zero,
                            end: Offset.zero,
                          ).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOut,
                            ),
                          );

                      final scale =
                          Tween<double>(
                            begin: isIncoming ? 0.975 : 1.0,
                            end: isIncoming ? 1.0 : 0.985,
                          ).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeInOutCubic,
                            ),
                          );

                      final blurSigma = Tween<double>(
                        begin: isIncoming ? 6.0 : 0.0,
                        end: isIncoming ? 0.0 : 2.5,
                      ).animate(eased);

                      final tilt = Tween<double>(
                        begin: isIncoming
                            ? (-_transitionDirection * 0.045)
                            : 0.0,
                        end: isIncoming ? 0.0 : (_transitionDirection * 0.025),
                      ).animate(eased);

                      return FadeTransition(
                        opacity: fade,
                        child: SlideTransition(
                          position: horizontalShift,
                          child: SlideTransition(
                            position: subtleLift,
                            child: ScaleTransition(
                              scale: scale,
                              child: AnimatedBuilder(
                                animation: eased,
                                builder: (context, _) {
                                  final m = Matrix4.identity()
                                    ..setEntry(3, 2, 0.001)
                                    ..rotateY(tilt.value);

                                  return Transform(
                                    alignment: Alignment.center,
                                    transform: m,
                                    child: ImageFiltered(
                                      imageFilter: ImageFilter.blur(
                                        sigmaX: blurSigma.value,
                                        sigmaY: blurSigma.value * 0.55,
                                      ),
                                      child: child,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                    child: KeyedSubtree(
                      key: ValueKey(selectedIndex),
                      child: SizedBox.expand(child: pages[selectedIndex]),
                    ),
                  ),
                ),
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
