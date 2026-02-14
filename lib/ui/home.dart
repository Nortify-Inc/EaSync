import 'package:flutter/material.dart';
import 'handler.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  static const int fakePages = 10000;

  static const int startPage =
      (fakePages ~/ 2) - ((fakePages ~/ 2) % 3);

  int selectedIndex = 0;
  int currentFakePage = startPage;

  final PageController pageController =
      PageController(initialPage: startPage);

  final PageController bottomTextController =
      PageController(initialPage: startPage);

  late double screenWidth;

  double dragStartX = 0;
  double dragDelta = 0;

  final List<Widget> pages = const [
    Dashboard(),
    Profiles(),
    Manage(),
  ];

  final List<String> tabs = [
    "Dashboard",
    "Profiles",
    "Manage",
  ];

  int getRealIndex(int fakeIndex) {
    return fakeIndex % pages.length;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    screenWidth = MediaQuery.of(context).size.width;
  }

  @override
  void initState() {
    super.initState();
    bottomTextController.addListener(syncPages);
  }

  void syncPages() {
    final page = bottomTextController.page;
    if (page == null) return;

    final fake = page.round();

    if (fake != currentFakePage) {
      currentFakePage = fake;

      final real = getRealIndex(fake);

      if (real != selectedIndex) {
        setState(() => selectedIndex = real);
      }
    }

    pageController.jumpTo(page * screenWidth);
  }

  void goNext() {
    bottomTextController.animateToPage(
      currentFakePage + 1,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void goPrev() {
    bottomTextController.animateToPage(
      currentFakePage - 1,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    pageController.dispose();
    bottomTextController.dispose();
    super.dispose();
  }

  Widget _buildIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        pages.length,
        (index) => _buildDot(index),
      ),
    );
  }

  Widget _buildDot(int index) {
    final bool active = index == selectedIndex;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      width: active ? 18 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: active ? EaColor.fore : EaColor.back,
        borderRadius: BorderRadius.circular(20),
        boxShadow: active
            ? [
                BoxShadow(
                  color: EaColor.fore.withValues(alpha: 0.4),
                  blurRadius: 6,
                ),
              ]
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // BODY COM SWIPE GLOBAL
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,

        onHorizontalDragStart: (d) {
          dragStartX = d.globalPosition.dx;
        },

        onHorizontalDragUpdate: (d) {
          dragDelta = d.globalPosition.dx - dragStartX;
        },

        onHorizontalDragEnd: (d) {
          if (dragDelta.abs() < 50) return;

          if (dragDelta < 0) {
            goNext();
          } else {
            goPrev();
          }

          dragDelta = 0;
        },

        child: PageView.builder(
          controller: pageController,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: fakePages,
          itemBuilder: (context, index) {
            final real = getRealIndex(index);
            return pages[real];
          },
        ),
      ),

      // BOTTOM BAR
      bottomNavigationBar: SafeArea(
        child: SizedBox(
          height: 110,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildIndicator(),

              const SizedBox(height: 10),

              // PILL FIXA
              Container(
                height: 48,
                width: 180,
                decoration: BoxDecoration(
                  color: EaColor.fore,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: PageView.builder(
                  controller: bottomTextController,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: fakePages,
                  itemBuilder: (context, index) {
                    final real = getRealIndex(index);

                    return Center(
                      child: Text(
                        tabs[real],
                        style: EaText.primaryBack,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
