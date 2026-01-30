import '../../models/alarm_data.dart' as alarm_model;
import 'cached_bus_info.dart';

class AlarmState {
  final Map<String, alarm_model.AlarmData> activeAlarms = {};
  final List<alarm_model.AlarmData> autoAlarms = [];
  final Map<String, CachedBusInfo> cachedBusInfo = {};
  final Set<String> processedNotifications = {};

  bool autoAlarmEnabled = true;
  final Set<String> manuallyStoppedAlarms = <String>{};
  final Map<String, DateTime> manuallyStoppedTimestamps = <String, DateTime>{};

  final Map<String, DateTime> executedAlarms = <String, DateTime>{};
  final Map<String, int> processedEventTimestamps = <String, int>{};

  bool isInTrackingMode = false;
  String? trackedRouteId;

  bool userManuallyStopped = false;
  int lastManualStopTime = 0;
}
