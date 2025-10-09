import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> bootstrap(Widget app) async {
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      runApp(ProviderScope(child: app));
    },
    (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Uncaught error: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    },
  );
}
