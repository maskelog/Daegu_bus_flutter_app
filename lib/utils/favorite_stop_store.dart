import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/bus_stop.dart';

class FavoriteStopStore {
  static const String _key = 'favorites';

  static Future<List<BusStop>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? <String>[];
    final stops = <BusStop>[];

    for (final entry in raw) {
      try {
        final data = jsonDecode(entry) as Map<String, dynamic>;
        stops.add(BusStop.fromJson(data));
      } catch (_) {
        // Skip malformed entries to keep the list usable.
      }
    }

    return stops;
  }

  static Future<void> save(List<BusStop> stops) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = stops.map((stop) => jsonEncode(stop.toJson())).toList();
    await prefs.setStringList(_key, encoded);
  }
}
