import 'package:allora/features/chat/widgets/message_bubble.dart'
    show stripReplyFallback;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('strips the quoted fallback block', () {
    const body = '> <@bob:x> hey there\n> second quoted line\n\nsure thing!';
    expect(stripReplyFallback(body), 'sure thing!');
  });

  test('leaves normal messages untouched', () {
    expect(stripReplyFallback('just a message'), 'just a message');
  });

  test('handles quote-only edge case without crashing', () {
    expect(stripReplyFallback('> only a quote'), '');
  });
}
