import 'dart:ffi';
import 'dart:io';

import 'package:finance_app/data/local/isar_db.dart';
import 'package:isar_community/isar.dart';

/// Set ISAR_CORE_LIB to a local libisar for the host (e.g. from the
/// isar_community_flutter_libs package) when the download host is blocked.
Future<void> initIsarForTests() {
  final local = Platform.environment['ISAR_CORE_LIB'];
  return Isar.initializeIsarCore(download: local == null, libraries: local == null ? const {} : {Abi.current(): local});
}

Future<(Isar, Directory)> openTestIsar() async {
  final dir = await Directory.systemTemp.createTemp('isar_test');
  final isar = await Isar.open(localSchemas, directory: dir.path, name: 'test');
  return (isar, dir);
}

Future<void> closeTestIsar(Isar isar, Directory dir) async {
  await isar.close(deleteFromDisk: true);
  await dir.delete(recursive: true);
}
