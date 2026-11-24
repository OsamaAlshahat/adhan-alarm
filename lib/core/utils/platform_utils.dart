import 'dart:io';
import 'package:permission_handler/permission_handler.dart';
import '../constants/app_constants.dart';

Future<bool> canUseFullScreenIntent() async {
  if (!Platform.isAndroid) return true;
  try {
    final res = await platformFullscreen.invokeMethod<bool>('canUseFullScreenIntent');
    return res ?? true;
  } catch (_) {
    return true;
  }
}

Future<void> openFullScreenIntentSettings() async {
  if (!Platform.isAndroid) return;
  try {
    await platformFullscreen.invokeMethod('openFullScreenIntentSettings');
  } catch (_) {
    await openAppSettings();
  }
}
