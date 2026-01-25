import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/favorite_bus.dart';

class FavoriteBusStore {
  static const String _key = 'favorite_buses';

  static Future<List<FavoriteBus>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? <String>[];
    final buses = <FavoriteBus>[];
    for (final entry in raw) {
      try {
        final data = jsonDecode(entry) as Map<String, dynamic>;
        buses.add(FavoriteBus.fromJson(data));
      } catch (_) {
        // Skip malformed entries to keep the list usable.
      }
    }
    return buses;
  }

  static Future<void> save(List<FavoriteBus> buses) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = buses.map((bus) => jsonEncode(bus.toJson())).toList();
    await prefs.setStringList(_key, encoded);
  }

  static List<FavoriteBus> toggle(List<FavoriteBus> buses, FavoriteBus target) {
    final updated = List<FavoriteBus>.from(buses);
    final index = updated.indexWhere((bus) => bus.key == target.key);
    if (index >= 0) {
      updated.removeAt(index);
    } else {
      updated.add(target);
    }
    return updated;
  }
}
