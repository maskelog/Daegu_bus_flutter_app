import '../models/bus_stop.dart';
import 'favorite_stop_store.dart';

class HomeSearchResultSyncData {
  const HomeSearchResultSyncData({
    required this.favoriteStops,
    this.selectedStop,
  });

  final List<BusStop> favoriteStops;
  final BusStop? selectedStop;
}

class HomeSearchResultSync {
  static Future<HomeSearchResultSyncData> resolve(Object? result) async {
    final favoriteStops = await FavoriteStopStore.load();
    return HomeSearchResultSyncData(
      favoriteStops: favoriteStops,
      selectedStop: result is BusStop ? result : null,
    );
  }
}
