import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/login/data/models/user_model.dart';

class SharedPrefsService {
  SharedPrefsService._();
  static final SharedPrefsService instance = SharedPrefsService._();

  static const String _employeesKey = 'employees_list';
  static const String _clientsFullSyncKey = 'clients_full_sync_at_';
  static const String _pushNotificationsEnabledKey =
      'push_notifications_enabled_';

  SharedPreferences? _prefs;

  /// Pozovi jednom na startu aplikacije.
  Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<SharedPreferences> _getPrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  // Lista je po organizaciji, da se pri prijavi u drugu organizaciju ne
  // prikažu zaposleni iz prethodne.
  String _employeesKeyFor(String organizationId) =>
      '${_employeesKey}_$organizationId';

  /// Setuje listu objekata
  Future<bool> setUsers(String organizationId, List<UserModel> users) async {
    final prefs = await _getPrefs();

    // List<UserModel> -> List<String>
    final encoded = users.map((e) => jsonEncode(e.toJson())).toList();

    return prefs.setStringList(_employeesKeyFor(organizationId), encoded);
  }

  /// Dodaj JEDAN objekat (append)
  Future<bool> addUser(String organizationId, UserModel newUser) async {
    final prefs = await _getPrefs();
    final raw = await _getRawUsers(organizationId)
      ..add(jsonEncode(newUser.toJson()));

    return prefs.setStringList(_employeesKeyFor(organizationId), raw);
  }

  Future<List<UserModel>> getUsers(String organizationId) async {
    final raw = await _getRawUsers(organizationId);

    return raw.map((item) {
      final map = jsonDecode(item) as Map<String, dynamic>;
      final id = (map['id'] ?? '') as String; // ako čuvaš id u json-u
      return UserModel.fromJson(map, id);
    }).toList();
  }

  /// Obriši jednog usera iz liste po userId
  Future<bool> removeUserById(String organizationId, String userId) async {
    final prefs = await _getPrefs();

    final raw = await _getRawUsers(organizationId);

    // Filtriramo sve osim usera sa zadatim ID-em
    final updated =
        raw.where((item) {
          final map = jsonDecode(item) as Map<String, dynamic>;
          final id = (map['id'] ?? '') as String;
          return id != userId;
        }).toList();

    return prefs.setStringList(_employeesKeyFor(organizationId), updated);
  }

  Future<List<String>> _getRawUsers(String organizationId) async {
    final prefs = await _getPrefs();
    final raw = prefs.getStringList(_employeesKeyFor(organizationId));
    if (raw != null) return List.of(raw);

    // Starije verzije su čuvale jednu listu za sve. Preuzima se samo ako je
    // iz iste organizacije, da se ne izgubi redoslijed zaposlenih.
    final legacy = prefs.getStringList(_employeesKey);
    if (legacy == null) return [];
    await prefs.remove(_employeesKey);

    final migrated =
        legacy.where((item) {
          final map = jsonDecode(item) as Map<String, dynamic>;
          return map['orgId'] == organizationId;
        }).toList();
    await prefs.setStringList(_employeesKeyFor(organizationId), migrated);
    return migrated;
  }

  /// Kada su klijenti organizacije posljednji put kompletno sinhronizovani.
  Future<DateTime?> getClientsFullSyncAt(String organizationId) async {
    final prefs = await _getPrefs();
    final millis = prefs.getInt('$_clientsFullSyncKey$organizationId');
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  Future<bool> setClientsFullSyncAt(
    String organizationId,
    DateTime time,
  ) async {
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
}
