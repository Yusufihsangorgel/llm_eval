import 'package:llm_eval/src/error_detail.dart';
import 'package:test/test.dart';

/// Throws so that the caller gets a stack trace the VM built, rather than one
/// written here. A hand-written trace would pass a test the real format fails,
/// and the real format is the whole point: these strings are pasted into pull
/// requests.
String _describeARealThrow() {
  try {
    throw StateError('boom');
  } catch (error, stackTrace) {
    return describeError('model call threw', error, stackTrace);
  }
}

void main() {
  group('describeError', () {
    test('keeps the context and the error', () {
      final described = _describeARealThrow();
      expect(described, startsWith('model call threw: Bad state: boom'));
    });

    test('carries no absolute path from the machine that ran it', () {
      final described = _describeARealThrow();

      // Positive control first: if the frame this asserts about is missing,
      // the two checks below would pass on an empty string and prove nothing.
      expect(
        described,
        contains('error_detail_test.dart'),
        reason: 'the throwing frame should still be identifiable',
      );

      expect(described, isNot(contains('file://')));
      expect(described, isNot(contains('/Users/')));
      expect(described, isNot(contains('/home/')));
      expect(described, isNot(contains(r'C:\')));
    });

    test('keeps the line number, which is what makes a frame useful', () {
      expect(
        _describeARealThrow(),
        matches(RegExp(r'error_detail_test\.dart:\d+:\d+')),
      );
    });

    test('leaves package: and dart: frames alone', () {
      final described = _describeARealThrow();
      // The isolate frames underneath a test come from dart:.
      expect(described, anyOf(contains('dart:'), contains('package:')));
    });

    test('stays on one line, since reports put it in a Markdown list', () {
      expect(_describeARealThrow(), isNot(contains('\n')));
    });

    test('drops the stack section entirely when there are no frames', () {
      final described = describeError(
        'context',
        StateError('boom'),
        StackTrace.fromString(''),
      );
      expect(described, 'context: Bad state: boom');
    });

    test('a short path is kept whole rather than emptied', () {
      // Two segments is already as short as the shortening can make it, and a
      // greedy implementation that always drops leading segments would return
      // nothing here.
      final described = describeError(
        'context',
        StateError('boom'),
        StackTrace.fromString('#0 main (file:///a/b.dart:1:2)'),
      );
      expect(described, contains('a/b.dart:1:2'));
    });
  });
}
