import 'handler.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  static const int fakePages = 10000;

  static const int startPage = (fakePages ~/ 2) - ((fakePages ~/ 2) % 3);

  int selectedIndex = 0;
  int currentFakePage = startPage;

  final PageController pageController = PageController(initialPage: startPage);

  final PageController bottomController = PageController(
    viewportFraction: 0.35,
    initialPage: startPage,
  );

  late double screenWidth;

  double dragStartX = 0;
  double dragDelta = 0;

  final List<Widget> pages = const [Dashboard(), Profiles(), Manage()];

  final List<String> tabs = ["Dashboard", "Profiles", "Manage"];

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

    bottomController.addListener(syncPages);
  }

  void syncPages() {
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

  void goNext() {
    bottomController.animateToPage(
      currentFakePage + 1,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  void goPrev() {
    bottomController.animateToPage(
      currentFakePage - 1,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
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

      // BOTTOM NAV
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
                        : EaColor.back.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.18),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : [],
                  ),
                  child: Text(
                    tabs[real],
                    style: isSelected ? EaText.primaryBack : EaText.secondary,
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
