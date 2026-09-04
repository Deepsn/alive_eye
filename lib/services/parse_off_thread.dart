import 'dart:isolate';

const _isolateThreshold = 64 * 1024;

// Spawning an isolate costs more than parsing a small payload, and it never
// completes under the widget tests' fake clock.
Future<T> parseOffThread<T>(String source, T Function(String) parse) =>
    source.length < _isolateThreshold
    ? Future.value(parse(source))
    : Isolate.run(() => parse(source));
