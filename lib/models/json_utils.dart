// SPTrans sends some numeric fields as strings (e.g. the vehicle prefix).
int asInt(Object? value) => switch (value) {
  num n => n.toInt(),
  String s => int.tryParse(s.trim()) ?? 0,
  _ => 0,
};
