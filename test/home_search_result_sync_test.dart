import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daegu_bus_app/models/bus_stop.dart';
import 'package:daegu_bus_app/utils/home_search_result_sync.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HomeSearchResultSync', () {
    test('reloads favorite stops even when no station is selected', () async {
      final favoriteStop = BusStop(
        id: '1001',
        stationId: '1001',
        name: '대구역',
        isFavorite: true,
      );
      SharedPreferences.setMockInitialValues({
        'favorites': <String>[jsonEncode(favoriteStop.toJson())],
      });

      final result = await HomeSearchResultSync.resolve(null);

      expect(result.selectedStop, isNull);
      expect(result.favoriteStops, hasLength(1));
      expect(result.favoriteStops.first.id, favoriteStop.id);
      expect(result.favoriteStops.first.name, favoriteStop.name);
    });

    test('keeps selected stop and refreshes favorite stops from storage',
        () async {
      final favoriteStop = BusStop(
        id: '2002',
        stationId: '2002',
        name: '동대구역',
        isFavorite: true,
      );
      final selectedStop = BusStop(
        id: '3003',
        stationId: '3003',
        name: '반월당',
      );
      SharedPreferences.setMockInitialValues({
        'favorites': <String>[jsonEncode(favoriteStop.toJson())],
      });

      final result = await HomeSearchResultSync.resolve(selectedStop);

      expect(result.selectedStop, selectedStop);
      expect(result.favoriteStops, hasLength(1));
      expect(result.favoriteStops.first.id, favoriteStop.id);
    });
  });
}
