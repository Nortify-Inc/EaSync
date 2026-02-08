import 'dart:ffi';
import 'package:flutter/material.dart';
import 'bridge.dart';

/* ===========================================================
   MODEL
=========================================================== */

class DeviceModel {
  final String uuid;
  final String name;
  final int protocol;
  final List<int> capabilities;

  bool power;
  int brightness;
  double temperature;

  DeviceModel({
    required this.uuid,
    required this.name,
    required this.protocol,
    required this.capabilities,
    required this.power,
    required this.brightness,
    required this.temperature,
  });
}

/* ===========================================================
   DASHBOARD
=========================================================== */

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  final List<DeviceModel> devices = [];

  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    initCore();
  }

  Future<void> initCore() async {
    try {
      Bridge.init();
      await loadDevices();
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  Future<void> loadDevices() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final list = Bridge.listDevices();

      devices.clear();

      for (final dev in list) {
        final uuid = _readCString(dev.uuid);
        final name = _readCString(dev.name);

        final state = Bridge.getState(uuid);

        devices.add(
          DeviceModel(
            uuid: uuid,
            name: name,
            protocol: dev.protocol,
            capabilities: _readCaps(dev),
            power: state.power,
            brightness: state.brightness,
            temperature: state.temperature,
          ),
        );
      }

      setState(() {
        loading = false;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  Future<void> togglePower(DeviceModel dev) async {
    try {
      await Future(() {
        Bridge.setPower(dev.uuid, !dev.power);
      });

      await loadDevices();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  void dispose() {
    Bridge.destroy();
    super.dispose();
  }

  /* ===========================================================
     UI
  =========================================================== */

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (error != null) {
      return Scaffold(
        body: Center(
          child: Text(
            error!,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
        actions: [
          IconButton(
            onPressed: loadDevices,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),

      body: GridView.builder(
        padding: const EdgeInsets.all(16),

        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 1,
        ),

        itemCount: devices.length,

        itemBuilder: (context, i) {
          return _DeviceCard(
            device: devices[i],
            onToggle: () => togglePower(devices[i]),
          );
        },
      ),
    );
  }

  /* ===========================================================
     UTILS
  =========================================================== */

  String _readCString(Array<Int8> arr) {
    final bytes = <int>[];

    for (int i = 0; i < 256; i++) {
      final v = arr[i];

      if (v == 0) break;

      bytes.add(v);
    }

    return String.fromCharCodes(bytes);
  }

  List<int> _readCaps(CoreDeviceInfo info) {
    final list = <int>[];

    for (int i = 0; i < info.capabilityCount; i++) {
      list.add(info.capabilities[i]);
    }

    return list;
  }
  
}

/* ===========================================================
   DEVICE CARD
=========================================================== */

class _DeviceCard extends StatelessWidget {
  final DeviceModel device;
  final VoidCallback onToggle;

  const _DeviceCard({
    required this.device,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),

      child: InkWell(
        onTap: onToggle,

        borderRadius: BorderRadius.circular(16),

        child: Padding(
          padding: const EdgeInsets.all(16),

          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,

            children: [
              Text(
                device.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,

                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),

              Icon(
                device.power
                    ? Icons.power
                    : Icons.power_off,

                size: 48,

                color: device.power
                    ? Colors.green
                    : Colors.grey,
              ),

              Column(
                children: [
                  Text('Temp: ${device.temperature.toStringAsFixed(1)}°C'),
                  Text('Brightness: ${device.brightness}%'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
