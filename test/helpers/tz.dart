import 'dart:convert';
import 'dart:ffi';

/// Sets the process time zone at runtime so DST cases are exercised wherever
/// the suite runs. Dart's DateTime asks libc (`localtime_r`) for offsets and
/// caches nothing, so `setenv("TZ") + tzset()` takes effect immediately.
/// POSIX only (macOS/Linux hosts, which is where `flutter test` runs).
///
/// Returns a function that restores the previous zone.
void Function() withTimeZone(String tz) {
  final lib = DynamicLibrary.process();
  final setenv = lib.lookupFunction<
      Int32 Function(Pointer<Char>, Pointer<Char>, Int32),
      int Function(Pointer<Char>, Pointer<Char>, int)>('setenv');
  final unsetenv = lib.lookupFunction<Int32 Function(Pointer<Char>),
      int Function(Pointer<Char>)>('unsetenv');
  final getenv = lib.lookupFunction<Pointer<Char> Function(Pointer<Char>),
      Pointer<Char> Function(Pointer<Char>)>('getenv');
  final tzset = lib.lookupFunction<Void Function(), void Function()>('tzset');
  final malloc = lib.lookupFunction<Pointer<Char> Function(IntPtr),
      Pointer<Char> Function(int)>('malloc');
  final free = lib.lookupFunction<Void Function(Pointer<Char>),
      void Function(Pointer<Char>)>('free');

  Pointer<Char> cstr(String s) {
    final bytes = utf8.encode(s);
    final p = malloc(bytes.length + 1);
    final list = p.cast<Uint8>().asTypedList(bytes.length + 1);
    list.setAll(0, bytes);
    list[bytes.length] = 0;
    return p;
  }

  String? readC(Pointer<Char> p) {
    if (p == nullptr) return null;
    final bytes = <int>[];
    for (var i = 0;; i++) {
      final b = p.cast<Uint8>()[i];
      if (b == 0) break;
      bytes.add(b);
    }
    return utf8.decode(bytes);
  }

  final key = cstr('TZ');
  final previous = readC(getenv(key));
  final value = cstr(tz);
  setenv(key, value, 1);
  tzset();
  free(value);

  return () {
    if (previous == null) {
      unsetenv(key);
    } else {
      final v = cstr(previous);
      setenv(key, v, 1);
      free(v);
    }
    tzset();
    free(key);
  };
}
