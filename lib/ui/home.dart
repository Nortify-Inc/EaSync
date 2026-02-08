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

  final PageController bottomController =
      PageController(
        viewportFraction: 0.35,
        initialPage: startPage,
      );

  late double screenWidth;

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

    bottomController.addListener(_syncPages);
  }

  void _syncPages() {
    final page = bottomController.page;

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

  @override
  void dispose() {
    pageController.dispose();
    bottomController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,

      // BODY (INFINITE)
      body: PageView.builder(
        controller: pageController,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: fakePages,
        itemBuilder: (context, index) {
          final real = getRealIndex(index);
          return pages[real];
        },
      ),

      // BOTTOM CAROUSEL (INFINITE)
      bottomNavigationBar: SizedBox(
        height: 100,
        child: PageView.builder(
          controller: bottomController,
          itemCount: fakePages,
          itemBuilder: (context, index) {
            final real = getRealIndex(index);
            final bool isSelected = real == selectedIndex;

            return GestureDetector(
              onTap: () {
                bottomController.animateToPage(
                  index,
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                );
              },
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 18,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? EaColor.fore
                        : EaColor.back.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.18),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : [],
                  ),
                  child: Text(
                    tabs[real],
                    style: isSelected
                        ? EaText.primary
                        : EaText.secondary,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
