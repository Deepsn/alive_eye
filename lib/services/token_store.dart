import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';

class TokenStore {
  TokenStore({SharedPreferencesAsync? prefs})
    : _prefs = prefs ?? SharedPreferencesAsync();

  static const _key = 'olho_vivo_token';

  final SharedPreferencesAsync _prefs;

  Future<String?> read() async {
    final saved = (await _prefs.getString(_key))?.trim();
    if (saved != null && saved.isNotEmpty) return saved;
    return AppConfig.olhoVivoToken.isEmpty ? null : AppConfig.olhoVivoToken;
  }

  Future<void> write(String token) => _prefs.setString(_key, token.trim());
}
