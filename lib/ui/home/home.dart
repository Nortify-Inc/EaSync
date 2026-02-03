import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../state/deviceStore.dart';
import './header.dart';
import './modeBar.dart';
import './deviceGrid.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      context.read<DeviceStore>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: const [
            HomeHeader(),
            ModeBar(),
            Expanded(child: DeviceGrid()),
          ],
        ),
      ),
    );
  }
}
