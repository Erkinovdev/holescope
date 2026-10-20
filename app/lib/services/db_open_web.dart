import 'package:sqlite3/common.dart';
import 'package:sqlite3/wasm.dart';

/// Веб: sqlite3 в WebAssembly (файл web/sqlite3.wasm), данные живут, пока открыта вкладка.
WasmSqlite3? _sqlite;

Future<void> initDbPlatform() async {
  final s = await WasmSqlite3.loadFromUrl(Uri.parse('sqlite3.wasm'));
  s.registerVirtualFileSystem(InMemoryFileSystem(), makeDefault: true);
  _sqlite = s;
}

CommonDatabase openDbFile(String path) => _sqlite!.open(path);
CommonDatabase openDbMemory() => _sqlite!.openInMemory();
