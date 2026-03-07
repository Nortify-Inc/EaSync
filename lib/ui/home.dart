/*!
 * @file home.dart
 * @brief Main screen with horizontal navigation across application modules.
 * @param index Virtual index of the current page in the `PageView`.
 * @return Navigation widgets and visual composition for the home screen.
 * @author Erick Radmann
 */

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
  static const int _kLoopItemCount = 1000000;
  static const int _kLoopSeed = 500000;
  static const double _kDragMinDistance = 14.0;

  int selectedIndex = 0;
  late final PageController _pageController;
  late int _virtualPage;
  bool _pageAnimating = false;
  double _dragAccumulatedDx = 0;
  bool _dragTriggered = false;

  String? _profilePhoto;
  late final List<bool> _pageReady;
  final Set<int> _warmingPages = <int>{};

  final List<Widget> pages = [
    const Dashboard(),
    const Profiles(),
    const Manage(),
    const AssistantChat(),
    const Account(),
  ];

  final List<String> tabs = [
    'Dashboard',
    'Profiles',
    'Manage',
    'Assistant',
    'Account',
  ];

  @override
  void initState() {
    super.initState();
    _virtualPage = (_kLoopSeed - (_kLoopSeed % pages.length)) + selectedIndex;
    _pageController = PageController(initialPage: _virtualPage);
    _pageReady = List<bool>.filled(pages.length, false);
    _warmInitialPages();
    _loadProfilePhoto();
  }

  int _realIndexFromVirtual(int virtualIndex) {
    return virtualIndex % pages.length;
  }

  Future<void> _warmInitialPages() async {
    await _ensurePageReady(selectedIndex);
    _warmNeighborPages(selectedIndex);
  }

  void _warmNeighborPages(int center) {
    _ensurePageReady((center - 1 + pages.length) % pages.length);
    _ensurePageReady((center + 1) % pages.length);
  }

  Future<void> _ensurePageReady(int index) async {
    if (_pageReady[index] || _warmingPages.contains(index)) return;
    _warmingPages.add(index);

    await Future<void>.delayed(const Duration(milliseconds: 90));

    if (!mounted) return;
    setState(() => _pageReady[index] = true);
    _warmingPages.remove(index);
  }

  Future<void> _loadProfilePhoto() async {
    final prefs = await SharedPreferences.getInstance();
    _profilePhoto = prefs.getString(_kAuthPhoto);
    if (mounted) setState(() {});
  }

  void goNext() {
    _goToIndex((selectedIndex + 1) % pages.length);
  }

  void goPrev() {
    _goToIndex((selectedIndex - 1 + pages.length) % pages.length);
  }

  Future<void> _goToIndex(int index) async {
    if (index == selectedIndex || _pageAnimating) return;
    _pageAnimating = true;

    await _ensurePageReady(index);
    _warmNeighborPages(index);

    final currentReal = _realIndexFromVirtual(_virtualPage);
    var delta = index - currentReal;
    if (delta > pages.length / 2) delta -= pages.length;
    if (delta < -pages.length / 2) delta += pages.length;
    final targetVirtual = _virtualPage + delta;

    try {
      await _pageController.animateToPage(
        targetVirtual,
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOut,
      );

      if (!mounted) return;
      setState(() {
        selectedIndex = index;
        _virtualPage = targetVirtual;
      });
    } finally {
      _pageAnimating = false;
    }
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    _dragAccumulatedDx = 0;
    _dragTriggered = false;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (_dragTriggered || _pageAnimating) return;
    _dragAccumulatedDx += details.delta.dx;

    if (_dragAccumulatedDx.abs() < _kDragMinDistance) return;
    _dragTriggered = true;

    if (_dragAccumulatedDx < 0) {
      goNext();
    } else {
      goPrev();
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    _dragAccumulatedDx = 0;
    _dragTriggered = false;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  int _safeSelectedIndex() {
    if (pages.isEmpty) return 0;
    if (selectedIndex < 0) return 0;
    if (selectedIndex >= pages.length) {
      return selectedIndex % pages.length;
    }
    return selectedIndex;
  }

  Widget _buildBlurTitle() {
    final idx = _safeSelectedIndex();
    final title = EaI18n.t(context, tabs[idx]);

    return EaBlurFadeSwitcher(
      marker: title,
      child: Text(
        title,
        style: EaText.primary.copyWith(
          color: EaAdaptiveColor.bodyText(context),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    final idx = _safeSelectedIndex();
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: EaBlurFadeSwitcher(
        marker: idx,
        duration: const Duration(milliseconds: 140),
        beginBlur: 4,
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
                  if (idx == 4)
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
      ),
    );
  }

  Widget _buildIndicator() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: EaBlurFadeSwitcher(
        marker: _safeSelectedIndex(),
        duration: const Duration(milliseconds: 140),
        beginBlur: 4,
        child: SizedBox(
          height: 36,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(pages.length, (index) => _buildDot(index)),
          ),
        ),
      ),
    );
  }

  Widget _buildDot(int index) {
    final bool active = index == _safeSelectedIndex();
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
          Padding(
            padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
            child: ClipRect(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragStart: _onHorizontalDragStart,
                onHorizontalDragUpdate: _onHorizontalDragUpdate,
                onHorizontalDragEnd: _onHorizontalDragEnd,
                child: PageView.builder(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (virtualIndex) {
                    if (!mounted) return;
                    final realIndex = _realIndexFromVirtual(virtualIndex);
                    setState(() {
                      selectedIndex = realIndex;
                      _virtualPage = virtualIndex;
                    });
                    _ensurePageReady(realIndex);
                    _warmNeighborPages(realIndex);
                  },
                  itemCount: _kLoopItemCount,
                  itemBuilder: (context, virtualIndex) {
                    final realIndex = _realIndexFromVirtual(virtualIndex);
                    return RepaintBoundary(
                      child: ColoredBox(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: ClipRect(
                          child: _pageReady[realIndex]
                              ? pages[realIndex]
                              : const _HomePageSkeleton(),
                        ),
                      ),
                    );
                  },
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

class _HomePageSkeleton extends StatelessWidget {
  const _HomePageSkeleton();

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: [
        EaSkeleton(width: w * 0.55, height: 20),
        const SizedBox(height: 12),
        EaSkeleton(width: w - 32, height: 120),
        const SizedBox(height: 12),
        EaSkeleton(width: w - 32, height: 84),
        const SizedBox(height: 12),
        EaSkeleton(width: w - 32, height: 84),
      ],
    );
  }
}
