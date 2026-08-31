/// Result of cleaning a prompt after a replace-all operation.
class PromptReplaceCleanupResult {
  const PromptReplaceCleanupResult({
    required this.text,
    required this.caretOffset,
  });

  final String text;
  final int caretOffset;
}

/// Removes empty top-level prompt entries left by a replace-all operation.
///
/// Prompt syntax may contain commas inside weighted/grouped expressions. The
/// cleaner therefore only treats commas outside `()`, `[]`, `{}` and quoted
/// strings as tag separators. Existing text is returned byte-for-byte when
/// there is nothing to clean; when an empty entry is removed, surrounding
/// whitespace is trimmed but line breaks inside non-empty entries remain.
PromptReplaceCleanupResult cleanPromptAfterReplaceAll(
  String text, {
  int? caretOffset,
}) {
  final requestedCaret = (caretOffset ?? text.length)
      .clamp(0, text.length)
      .toInt();
  final segments = _splitTopLevelSegments(text);
  final nonEmpty = <_PromptSegment>[];
  var hasEmptySegment = false;

  for (final segment in segments) {
    final bounds = segment.trimmedBounds(text);
    segment.trimStart = bounds.$1;
    segment.trimEnd = bounds.$2;
    if (segment.trimStart == segment.trimEnd) {
      hasEmptySegment = true;
    } else {
      nonEmpty.add(segment);
    }
  }

  if (!hasEmptySegment) {
    return PromptReplaceCleanupResult(text: text, caretOffset: requestedCaret);
  }

  final output = StringBuffer();
  final outputRanges =
      <({int sourceStart, int sourceEnd, int outputStart, int outputEnd})>[];

  for (var index = 0; index < nonEmpty.length; index++) {
    final segment = nonEmpty[index];
    if (index > 0) {
      final previous = nonEmpty[index - 1];
      output.write(_separatorFor(text, previous, segment));
    }
    final outputStart = output.length;
    output.write(text.substring(segment.trimStart, segment.trimEnd));
    final outputEnd = output.length;
    outputRanges.add((
      sourceStart: segment.trimStart,
      sourceEnd: segment.trimEnd,
      outputStart: outputStart,
      outputEnd: outputEnd,
    ));
  }

  final cleaned = output.toString();
  var mappedCaret = cleaned.length;
  for (final range in outputRanges) {
    if (requestedCaret < range.sourceStart) {
      mappedCaret = range.outputStart;
      break;
    }
    if (requestedCaret <= range.sourceEnd) {
      mappedCaret =
          range.outputStart +
          (requestedCaret - range.sourceStart)
              .clamp(0, range.sourceEnd - range.sourceStart)
              .toInt();
      break;
    }
  }

  return PromptReplaceCleanupResult(
    text: cleaned,
    caretOffset: mappedCaret.clamp(0, cleaned.length).toInt(),
  );
}

String _separatorFor(
  String text,
  _PromptSegment previous,
  _PromptSegment next,
) {
  final comma = next.precedingComma;
  if (comma == null) {
    return ', ';
  }

  var separator = text.substring(comma, next.trimStart);
  if (separator.isEmpty || separator.codeUnitAt(0) != 0x2c) {
    return ', ';
  }

  // If the removed segment occupied a line of its own, keep that line break
  // instead of collapsing a multi-line prompt onto one line.
  final gap = text.substring(previous.end, next.start);
  if (!separator.contains('\n') && !separator.contains('\r')) {
    final lineBreak = RegExp(r'\r\n|\n|\r').firstMatch(gap)?.group(0);
    if (lineBreak != null) {
      final trailingHorizontal = separator.substring(1);
      separator =
          ',$lineBreak${trailingHorizontal.isEmpty ? '' : trailingHorizontal}';
    }
  }
  return separator;
}

List<_PromptSegment> _splitTopLevelSegments(String text) {
  final result = <_PromptSegment>[];
  var segmentStart = 0;
  int? precedingComma;
  var depth = 0;
  String? quote;
  var escaped = false;

  for (var index = 0; index < text.length; index++) {
    final character = text[index];
    if (quote != null) {
      if (escaped) {
        escaped = false;
      } else if (character == '\\') {
        escaped = true;
      } else if (character == quote) {
        quote = null;
      }
      continue;
    }

    if (character == '"' || character == "'") {
      quote = character;
      continue;
    }
    if (character == '(' || character == '[' || character == '{') {
      depth++;
      continue;
    }
    if (character == ')' || character == ']' || character == '}') {
      if (depth > 0) depth--;
      continue;
    }
    if (character == ',' && depth == 0) {
      result.add(
        _PromptSegment(
          start: segmentStart,
          end: index,
          precedingComma: precedingComma,
        ),
      );
      segmentStart = index + 1;
      precedingComma = index;
    }
  }

  result.add(
    _PromptSegment(
      start: segmentStart,
      end: text.length,
      precedingComma: precedingComma,
    ),
  );
  return result;
}

class _PromptSegment {
  _PromptSegment({
    required this.start,
    required this.end,
    required this.precedingComma,
  });

  final int start;
  final int end;
  final int? precedingComma;
  late int trimStart;
  late int trimEnd;

  (int, int) trimmedBounds(String text) {
    var left = start;
    var right = end;
    while (left < right && text[left].trim().isEmpty) {
      left++;
    }
    while (right > left && text[right - 1].trim().isEmpty) {
      right--;
    }
    return (left, right);
  }
}
