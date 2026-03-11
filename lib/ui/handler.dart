/*!
 * @file handler.dart
 * @brief Export aggregator file for modules.
 * @param No external parameters.
 * @return Symbol exposure for simplified exports.
 * @author Erick Radmann
 */

export 'package:flutter/material.dart';
export 'package:google_fonts/google_fonts.dart';
export 'package:ffi/ffi.dart';
export 'package:flutter/services.dart' show rootBundle;
export 'package:path_provider/path_provider.dart';
export 'package:flutter/foundation.dart';

export 'dart:ffi' hide Size;
export 'dart:math';
export 'dart:async';
export 'dart:io';
export 'dart:isolate';
export 'dart:convert';

export 'utils/bridge.dart';
export 'utils/skeleton.dart';
export 'theme.dart';
export 'i18n.dart';

export 'splash.dart';
export 'home.dart';

export 'dashboard.dart';
export 'profiles.dart';
export 'manage.dart';
export 'account.dart';
export 'settings.dart';

