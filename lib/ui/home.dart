/*!
 * @file home.dart
 * @brief Main screen with horizontal navigation across application modules.
 * @param index Virtual index of the current page in the `PageView`.
 * @return Navigation widgets and visual composition for the home screen.
 * @author Erick Radmann
 */

import 'dart:ui';
import 'package:flutter/material.dart';
import 'handler.dart';

List<DeviceInfo> devices = [];

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  static const int fakePages = 10000;
  static const int pageCount = 5;
  static const int startPage =
      (fakePages ~/ 2) - ((fakePages ~/ 2) % pageCount);

  int selectedIndex = 0;
  int currentFakePage = startPage;
  StreamSubscription<CoreEventData>? _eventSub;

  final PageController pageController = PageController(initialPage: startPage);

  late double screenWidth;
  double dragStartX = 0;
  double dragDelta = 0;

  final List<Widget> pages = [
    const Dashboard(),
    const Profiles(),
    const AssistantChat(),
    const Manage(),
    const Account(),
  ];

  final List<String> tabs = [
    "Dashboard",
    "Profiles",
    "Assistant",
    "Manage",
    "Account",
  ];

  int getRealIndex(int fakeIndex) => fakeIndex % pages.length;

  @override
  void initState() {
    super.initState();
    _eventSub = Bridge.onEvents.listen((_) {
      setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    screenWidth = MediaQuery.of(context).size.width;
  }

  void goNext() {
    pageController.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void goPrev() {
    pageController.previousPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    pageController.dispose();
    super.dispose();
  }

  Widget _buildBlurTitle() {
    final title = tabs[selectedIndex];

    return TweenAnimationBuilder<double>(
      key: ValueKey(title),
      tween: Tween<double>(begin: 3, end: 0),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      builder: (context, blur, _) {
        return ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Text(title, style: EaText.primary),
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
                IconButton(
                  tooltip: 'Settings',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const Settings()),
                    );
                  },
                  icon: const Icon(
                    Icons.settings_outlined,
                    color: EaColor.fore,
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
        color: active ? EaColor.secondaryFore : EaColor.back,
        borderRadius: BorderRadius.circular(20),
        boxShadow: active
            ? [
                BoxShadow(
                  color: EaColor.fore,
                  blurRadius: 6,
                  offset: const Offset(0, 0),
                ),
              ]
            : [BoxShadow(color: EaColor.back, blurRadius: 2)],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // calculando padding vertical automático
    final double topPadding =
        MediaQuery.of(context).padding.top + 56; // SafeArea + AppBar
    final double bottomPadding = 36 + 16; // indicador + margem

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (d) => dragStartX = d.globalPosition.dx,
            onHorizontalDragUpdate: (d) =>
                dragDelta = d.globalPosition.dx - dragStartX,
            onHorizontalDragEnd: (d) {
              if (dragDelta.abs() > 50) {
                dragDelta < 0 ? goNext() : goPrev();
              }
              dragDelta = 0;
            },
            child: Padding(
              padding: EdgeInsets.only(top: topPadding, bottom: bottomPadding),
              child: PageView.builder(
                controller: pageController,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: fakePages,
                itemBuilder: (context, index) => pages[getRealIndex(index)],
                onPageChanged: (fake) {
                  currentFakePage = fake;
                  final real = getRealIndex(fake);
                  if (real != selectedIndex)
                    setState(() => selectedIndex = real);
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
