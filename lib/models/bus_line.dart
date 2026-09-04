class BusLine {
  const BusLine({
    required this.code,
    required this.number,
    required this.type,
    required this.direction,
    required this.circular,
    required this.primarySign,
    required this.secondarySign,
  });

  factory BusLine.fromJson(Map<String, dynamic> json) => BusLine(
    code: (json['cl'] as num).toInt(),
    number: json['lt'] as String? ?? '',
    type: (json['tl'] as num?)?.toInt() ?? 0,
    direction: (json['sl'] as num?)?.toInt() ?? 0,
    circular: json['lc'] as bool? ?? false,
    primarySign: (json['tp'] as String? ?? '').trim(),
    secondarySign: (json['ts'] as String? ?? '').trim(),
  );

  final int code;
  final String number;
  final int type;
  final int direction;
  final bool circular;
  final String primarySign;
  final String secondarySign;

  String get signage => '$number-$type';
}
