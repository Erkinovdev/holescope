import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:holescope/app.dart';
import 'package:holescope/core/settings.dart';
import 'package:holescope/services/local_db.dart';
import 'package:holescope/services/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final dir = await getApplicationSupportDirectory();
  final db = LocalDb.open(p.join(dir.path, 'holescope.db'));
  runApp(ProviderScope(
    overrides: [
      prefsProvider.overrideWithValue(prefs),
      dbProvider.overrideWithValue(db),
      supportDirProvider.overrideWithValue(dir.path),
    ],
    child: const HoleScopeApp(),
  ));
}
