import 'handler.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  List<DeviceInfo> devices = [];

  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final list = Bridge.listDevices();

      setState(() {
        devices = list;
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          _header(),

          Expanded(
            child: _body(),
          ),
        ],
      ),
    );
  }

  /* ===================================================== */

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.all(20),

      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,

            children: [
              Text(
                "Dashboard",

                style: EaText.primary.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 4),

              Text(
                "${devices.length} devices",

                style: EaText.secondary,
              ),
            ],
          ),

          const Spacer(),
        ],
      ),
    );
  }

  Widget _body() {
    if (loading) {
      return _loading();
    }

    if (error != null) {
      return _errorState();
    }

    if (devices.isEmpty) {
      return _emptyState();
    }

    return _grid();
  }

  /* ===================================================== */

  Widget _loading() {
    return const Center(
      child: CircularProgressIndicator(
        color: EaColor.fore,
      ),
    );
  }

  Widget _errorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),

        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            const Icon(
              Icons.error_outline,
              size: 48,
              color: Colors.redAccent,
            ),

            const SizedBox(height: 16),

            Text(
              "Core error",
              style: EaText.primary,
            ),

            const SizedBox(height: 8),

            Text(
              error ?? "",
              textAlign: TextAlign.center,
              style: EaText.secondary,
            ),

            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: _loadDevices,

              style: ElevatedButton.styleFrom(
                backgroundColor: EaColor.fore,
                foregroundColor: EaColor.background,
              ),

              child: const Text("Retry"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),

        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [
            Container(
              width: 100,
              height: 100,

              decoration: BoxDecoration(
                shape: BoxShape.circle,

                gradient: LinearGradient(
                  colors: [
                    EaColor.fore.withValues(alpha: .25),
                    EaColor.fore.withValues(alpha: .08),
                  ],
                ),
              ),

              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,

                children: [
                  Icon(Icons.tungsten, size: 30, color: EaColor.fore),
                  Icon(Icons.color_lens, size: 30, color: EaColor.fore),
                  Icon(Icons.thermostat, size: 30, color: EaColor.fore),
                ],
              ),
            ),

            const SizedBox(height: 24),

            Text(
              "No devices yet",

              style: EaText.primary.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              "Your devices will appear here",

              textAlign: TextAlign.center,

              style: EaText.secondary,
            ),
          ],
        ),
      ),
    );
  }

  /* ===================================================== */

  Widget _grid() {
    return RefreshIndicator(
      color: EaColor.fore,

      onRefresh: _loadDevices,

      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),

        gridDelegate:
            const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 18,
          crossAxisSpacing: 18,
          childAspectRatio: .92,
        ),

        itemCount: devices.length,

        itemBuilder: (_, i) {
          return _deviceCard(devices[i]);
        },
      ),
    );
  }

  Widget _deviceCard(DeviceInfo device) {
    return GestureDetector(
      onTap: () {
        _togglePower(device);
      },

      child: Container(
        padding: const EdgeInsets.all(16),

        decoration: BoxDecoration(
          color: EaColor.back,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: EaColor.border),
        ),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            const Align(
              alignment: Alignment.topRight,

              child: Icon(
                Icons.circle,
                size: 10,
                color: Colors.greenAccent,
              ),
            ),

            const Spacer(),

            const Icon(
              Icons.devices,
              size: 36,
              color: EaColor.fore,
            ),

            const SizedBox(height: 12),

            Text(
              device.name,
              style: EaText.primary,
            ),

            Text(
              device.uuid,

              maxLines: 1,
              overflow: TextOverflow.ellipsis,

              style: EaText.secondary.copyWith(
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /* ===================================================== */

  void _togglePower(DeviceInfo device) async {
    try {
      final state = Bridge.getState(device.uuid);

      Bridge.setPower(device.uuid, !state.power);

      await _loadDevices();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
        ),
      );
    }
  }
}
