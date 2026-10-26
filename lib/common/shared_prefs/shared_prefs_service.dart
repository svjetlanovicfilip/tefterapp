import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/login/data/models/user_model.dart';

class SharedPrefsService {
  SharedPrefsService._();
  static final SharedPrefsService instance = SharedPrefsService._();

  static const String _employeesKey = 'employees_list';
  static const String _clientsFullSyncKey = 'clients_full_sync_at_';
  static const String _pushNotificationsEnabledKey = 'push_notifications_enabled_';

  SharedPreferences? _prefs;

  /// Pozovi jednom na startu aplikacije.
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

 Future<SharedPreferences> _getPrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  /// Setuje listu objekata
Future<bool> setUsers(List<UserModel> users) async {
  final prefs = _prefs ?? await SharedPreferences.getInstance();

  // List<UserModel> -> List<String>
  final encoded = users.map((e) => jsonEncode(e.toJson())).toList();

  return prefs.setStringList(_employeesKey, encoded);
}

 /// Dodaj JEDAN objekat (append)
  Future<bool> addUser(UserModel newUser) async {
    final prefs = await _getPrefs();

    // 1) Uzmi postojeću listu stringova
    final raw = prefs.getStringList(_employeesKey) ?? <String>[]

    // 2) Dodaj novi objekat kao JSON string
    ..add(jsonEncode(newUser.toJson()));

    // 3) Snimi nazad
    return prefs.setStringList(_employeesKey, raw);
  }

  Future<List<UserModel>> getUsers() async {
  final prefs = _prefs ?? await SharedPreferences.getInstance();

  final raw = prefs.getStringList(_employeesKey) ?? [];

  return raw.map((item) {
    final map = jsonDecode(item) as Map<String, dynamic>;
    final id = (map['id'] ?? '') as String; // ako čuvaš id u json-u
    return UserModel.fromJson(map, id);
  }).toList();
}

/// Obriši jednog usera iz liste po userId
Future<bool> removeUserById(String userId) async {
  final prefs = await _getPrefs();

  final raw = prefs.getStringList(_employeesKey) ?? <String>[];

  // Filtriramo sve osim usera sa zadatim ID-em
  final updated = raw.where((item) {
    final map = jsonDecode(item) as Map<String, dynamic>;
    final id = (map['id'] ?? '') as String;
    return id != userId;
  }).toList();

  return prefs.setStringList(_employeesKey, updated);
}

  /// Kada su klijenti organizacije posljednji put kompletno sinhronizovani.
  Future<DateTime?> getClientsFullSyncAt(String organizationId) async {
    final prefs = await _getPrefs();
    final millis = prefs.getInt('$_clientsFullSyncKey$organizationId');
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  Future<bool> setClientsFullSyncAt(String organizationId, DateTime time) async {
    final prefs = await _getPrefs();
    return prefs.setInt(
      '$_clientsFullSyncKey$organizationId',
      time.millisecondsSinceEpoch,
    );
  }

  /// Da li korisnik želi push notifikacije na ovom uređaju.
  Future<bool> getPushNotificationsEnabled(String userId) async {
    final prefs = await _getPrefs();
    return prefs.getBool('$_pushNotificationsEnabledKey$userId') ?? true;
  }

  Future<bool> setPushNotificationsEnabled(
    String userId, {
    required bool enabled,
  }) async {
    final prefs = await _getPrefs();
    return prefs.setBool('$_pushNotificationsEnabledKey$userId', enabled);
  }

  /// Opcionalno: obriši listu
  Future<bool> clearUsers() async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    return prefs.remove(_employeesKey);
  }
}
