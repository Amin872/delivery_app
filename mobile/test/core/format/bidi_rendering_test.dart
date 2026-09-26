import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/core/format/display_formatters.dart';

/// Horizontal position of the character at [index] when [text] is laid out
/// as an Arabic (RTL) paragraph.
double _xOf(String text, int index) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: const TextStyle(fontSize: 14)),
    textDirection: TextDirection.rtl,
  )..layout();
  return painter.getBoxesForSelection(TextSelection(baseOffset: index, extentOffset: index + 1)).single.left;
}

void main() {
  // In an Arabic sentence, the leading "+" of a phone number and the "#" of
  // an order reference must stay at the visual *left* of the digits (they
  // read left-to-right as one unit). Without isolation the bidi algorithm
  // moves them to the right end.
  test('phone: "+" stays left of the digits inside Arabic text', () {
    final isolated = 'اتصل على ${formatPhone('+963944123456')} الآن';
    final plus = isolated.indexOf('+');
    final firstDigit = isolated.indexOf('9', plus);
    expect(_xOf(isolated, plus), lessThan(_xOf(isolated, firstDigit)));

    // Control: the raw number is scrambled (the "+" drifts right).
    const raw = 'اتصل على +963944123456 الآن';
    expect(_xOf(raw, raw.indexOf('+')), greaterThan(_xOf(raw, raw.indexOf('9'))));
  });

  test('order reference: "#" stays left of the code inside Arabic text', () {
    final isolated = 'الطلب ${displayOrderId('Xk3pQ9aB7cD2eF1gH4iJ')}';
    final hash = isolated.indexOf('#');
    expect(_xOf(isolated, hash), lessThan(_xOf(isolated, hash + 1)));
  });

  test('coordinates keep latitude before longitude, left to right, in Arabic text', () {
    final isolated = 'الموقع ${formatCoordinates(33.5138, 36.2765)}';
    expect(_xOf(isolated, isolated.indexOf('33')), lessThan(_xOf(isolated, isolated.indexOf('36'))));
  });
}
