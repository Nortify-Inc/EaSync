import 'package:flutter/material.dart';
import '../../models/device.dart';
import 'lightDialog.dart';
import 'acDialog.dart';
import 'fridgeDialog.dart';
import 'curtainDialog.dart';
import 'lockDialog.dart';

Future<void> showDeviceDialog(
  BuildContext context,
  Device device,
) {
  Widget dialog;

  switch (device.type) {
    case DeviceType.light:
      dialog = LightDialog(device: device);
      break;
    case DeviceType.airConditioner:
      dialog = AcDialog(device: device);
      break;
    case DeviceType.fridge:
      dialog = FridgeDialog(device: device);
      break;
    case DeviceType.curtain:
      dialog = CurtainDialog(device: device);
      break;
    case DeviceType.lock:
      dialog = LockDialog(device: device);
      break;
  }

  return showDialog(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => dialog,
  );
}
