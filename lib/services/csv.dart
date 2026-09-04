List<String> splitCsvLine(String line) {
  final fields = <String>[];
  final buffer = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (quoted) {
      if (ch != '"') {
        buffer.write(ch);
      } else if (i + 1 < line.length && line[i + 1] == '"') {
        buffer.write('"');
        i++;
      } else {
        quoted = false;
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == ',') {
      fields.add(buffer.toString());
      buffer.clear();
    } else {
      buffer.write(ch);
    }
  }
  fields.add(buffer.toString());
  return fields;
}

List<String> csvHeader(String line) => [
  for (final h in splitCsvLine(line)) h.replaceFirst('\uFEFF', '').trim(),
];
