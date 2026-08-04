import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _readAndroidSource(String relativePath) {
  return File('android/app/src/main/$relativePath').readAsStringSync();
}

int _occurrences(String source, String pattern) {
  return RegExp(RegExp.escape(pattern)).allMatches(source).length;
}

void main() {
  test('bus_api 채널은 책임별 operation으로 분리하고 36개 메서드를 보존한다', () {
    const basePath =
        'kotlin/com/devground/daegubus/channels/';
    final channelSource = _readAndroidSource(
      '${basePath}BusApiChannelHandler.kt',
    );
    final trackingSource = _readAndroidSource(
      '${basePath}BusApiTrackingOperations.kt',
    );
    final querySource = _readAndroidSource(
      '${basePath}BusApiQueryOperations.kt',
    );
    final alarmSource = _readAndroidSource(
      '${basePath}BusApiAlarmOperations.kt',
    );
    final ttsSource = _readAndroidSource(
      '${basePath}BusApiTtsOperations.kt',
    );

    const expectedMethods = <String>{
      'cancelAlarmNotification',
      'forceStopTracking',
      'startBusMonitoring',
      'stopBusTracking',
      'startBusMonitoringService',
      'stopBusMonitoringService',
      'cancelAlarmByRoute',
      'stopStationTracking',
      'stopAutoAlarm',
      'cancelOngoingTracking',
      'cancelAllNotifications',
      'stopSpecificTracking',
      'stopAllBusTracking',
      'updateBusTrackingNotification',
      'updateBusInfo',
      'registerBusArrivalReceiver',
      'searchStations',
      'findNearbyStations',
      'getBusRouteDetails',
      'searchBusRoutes',
      'getStationIdFromBsId',
      'getStationInfo',
      'getBusArrivalByRouteId',
      'getBusRouteInfo',
      'getBusPositionInfo',
      'getRouteStations',
      'showNotification',
      'startAutoAlarmNow',
      'cancelNativeAutoAlarm',
      'scheduleNativeAlarm',
      'startTtsTracking',
      'speakTTS',
      'setAudioOutputMode',
      'setVolume',
      'stopTTS',
      'isHeadphoneConnected',
    };
    final dispatchedMethods = RegExp(r'"([A-Za-z][A-Za-z0-9]+)"\s*->')
        .allMatches(channelSource)
        .map((match) => match.group(1)!)
        .toSet();

    expect(dispatchedMethods, expectedMethods);
    expect(channelSource.split('\n').length, lessThanOrEqualTo(140));
    for (final entry in <String, String>{
      'tracking': trackingSource,
      'query': querySource,
      'alarm': alarmSource,
      'tts': ttsSource,
    }.entries) {
      expect(
        entry.value.split('\n').length,
        lessThanOrEqualTo(500),
        reason: '${entry.key} operation이 다시 모놀리스가 되지 않아야 한다.',
      );
    }
    expect(trackingSource, contains('internal class BusApiTrackingOperations'));
    expect(trackingSource, contains('fun cancelAlarmNotification('));
    expect(querySource, contains('internal class BusApiQueryOperations'));
    expect(querySource, contains('fun searchStations('));
    expect(alarmSource, contains('internal class BusApiAlarmOperations'));
    expect(alarmSource, contains('fun scheduleNativeAlarm('));
    expect(ttsSource, contains('internal class BusApiTtsOperations'));
    expect(ttsSource, contains('fun speakTTS('));
  });

  test('버스 도착 갱신과 판정은 tracking manager에서 monitor로 분리한다', () {
    final managerSource = _readAndroidSource(
      'kotlin/com/devground/daegubus/services/BusAlertTrackingManager.kt',
    );
    final monitorSource = _readAndroidSource(
      'kotlin/com/devground/daegubus/services/BusAlertArrivalMonitor.kt',
    );

    expect(managerSource.split('\n').length, lessThanOrEqualTo(950));
    expect(monitorSource.split('\n').length, lessThanOrEqualTo(450));
    expect(
      managerSource,
      contains('private val arrivalMonitor = BusAlertArrivalMonitor('),
    );
    for (final method in <String>[
      'updateBusInfo',
      'updateBusInfoFromFlutter',
      'checkNextBusAndNotify',
      'checkArrivalAndNotify',
      'updateTrackingInfoFromFlutter',
    ]) {
      expect(
        managerSource,
        contains('arrivalMonitor.$method('),
        reason: '$method 공개 진입점은 manager에 유지한다.',
      );
      expect(
        monitorSource,
        contains('fun $method('),
        reason: '$method 구현은 arrival monitor가 소유한다.',
      );
    }
  });

  test('TTS 반복 예약은 Android 7에서도 사용할 수 있는 Handler API만 쓴다', () {
    final source = _readAndroidSource(
      'kotlin/com/devground/daegubus/services/TTSService.kt',
    );

    expect(source, isNot(contains('hasCallbacks(ttsRunnable)')));
    expect(source, contains('removeCallbacks(ttsRunnable)'));
  });

  test('알림 도우미는 수명주기를 벗어난 동적 리시버를 등록하지 않는다', () {
    final source = _readAndroidSource(
      'kotlin/com/devground/daegubus/utils/NotificationHandler.kt',
    );

    expect(source, isNot(contains('context.registerReceiver(')));
    expect(source, isNot(contains('class NotificationCancelReceiver')));
  });

  test('MainActivity 리시버는 lifecycle에서 한 번씩 안전하게 등록된다', () {
    final source = _readAndroidSource(
      'kotlin/com/devground/daegubus/MainActivity.kt',
    );

    expect(source, isNot(contains('alarmCancelReceiver')));
    final registrationLines = source
        .split('\n')
        .where((line) => line.contains('registerNotificationCancelReceiver()'))
        .where((line) => !line.contains('unregister'));
    expect(registrationLines.length, 2,
        reason: '함수 선언과 onResume 호출만 남아야 한다.');
    expect(source, contains('ContextCompat.RECEIVER_NOT_EXPORTED'));
  });

  test('알림 채널 중요도에는 지원되는 상수만 사용한다', () {
    final mainActivity = _readAndroidSource(
      'kotlin/com/devground/daegubus/MainActivity.kt',
    );
    final notificationHandler = _readAndroidSource(
      'kotlin/com/devground/daegubus/utils/NotificationHandler.kt',
    );

    expect(mainActivity, isNot(contains('IMPORTANCE_MAX')));
    expect(notificationHandler, isNot(contains('IMPORTANCE_MAX')));
  });

  test('상태 표시줄 small icon은 단색 벡터 리소스를 사용한다', () {
    const sources = [
      'kotlin/com/devground/daegubus/utils/NotificationHandler.kt',
      'kotlin/com/devground/daegubus/services/BusAlertAutoAlarmNotifier.kt',
      'kotlin/com/devground/daegubus/services/BusAlertNotificationUpdater.kt',
      'kotlin/com/devground/daegubus/services/StationTrackingService.kt',
      'kotlin/com/devground/daegubus/services/TTSService.kt',
      'kotlin/com/devground/daegubus/channels/BusApiAlarmOperations.kt',
    ];

    for (final path in sources) {
      final source = _readAndroidSource(path);
      expect(
        source,
        isNot(contains('.setSmallIcon(R.drawable.ic_bus_notification)')),
        reason: path,
      );
      expect(
        source,
        isNot(contains('.setSmallIcon(R.mipmap.ic_launcher)')),
        reason: path,
      );
    }
  });

  test('Live Update 알림은 AndroidX 호환 빌더와 ProgressStyle만 사용한다', () {
    const sources = [
      'kotlin/com/devground/daegubus/utils/NotificationHandler.kt',
      'kotlin/com/devground/daegubus/services/BusAlertAutoAlarmNotifier.kt',
    ];

    for (final path in sources) {
      final source = _readAndroidSource(path);
      expect(
        source,
        isNot(contains('Notification.Builder(')),
        reason: '$path: 네이티브 빌더는 AndroidX Live Update 호환성 레이어를 우회한다.',
      );
      expect(
        source,
        isNot(contains('Notification.ProgressStyle')),
        reason: path,
      );
      expect(
        source,
        isNot(contains('.setExtras(')),
        reason: '$path: setExtras는 NotificationCompat 내부 extras를 덮어쓴다.',
      );
      expect(
        source,
        isNot(contains('FLAG_PROMOTED_ONGOING')),
        reason: '$path: 승격 플래그는 NotificationCompat이 설정해야 한다.',
      );
      expect(
        source,
        isNot(contains('builtNotification.flags')),
        reason: '$path: 빌드 결과의 flags를 수동 변경하지 않는다.',
      );
      expect(
        source,
        isNot(contains('.setColorized(true)')),
        reason: '$path: colorized 알림은 Live Update 승격 판정을 방해할 수 있다.',
      );
      expect(source, contains('NotificationCompat.Builder('), reason: path);
      expect(
        source,
        contains('NotificationCompat.ProgressStyle()'),
        reason: path,
      );
      expect(source, contains('.setRequestPromotedOngoing(true)'), reason: path);
    }
  });

  test('BusAlertService 초기화는 객체 그래프를 중복 생성하지 않는다', () {
    final source = _readAndroidSource(
      'kotlin/com/devground/daegubus/services/BusAlertService.kt',
    );

    expect(_occurrences(source, 'notificationHandler = NotificationHandler(this)'), 1);
    expect(_occurrences(source, 'trackingManager = BusAlertTrackingManager('), 1);
  });

  test('앱 내부 브로드캐스트는 앱 패키지로 범위를 제한한다', () {
    final service = _readAndroidSource(
      'kotlin/com/devground/daegubus/services/BusAlertService.kt',
    );
    final trackingManager = _readAndroidSource(
      'kotlin/com/devground/daegubus/services/BusAlertTrackingManager.kt',
    );

    expect(service, contains('setPackage(packageName)'));
    expect(
      _occurrences(trackingManager, 'setPackage(service.packageName)'),
      greaterThanOrEqualTo(3),
    );
  });

  test('manifest는 사용자 승인형 정확 알람만 선언하고 제한 권한을 제외한다', () {
    final manifest = _readAndroidSource('AndroidManifest.xml');

    expect(manifest, contains('android.permission.SCHEDULE_EXACT_ALARM'));
    expect(manifest, isNot(contains('android.permission.USE_EXACT_ALARM')));
    expect(manifest, isNot(contains('android:maxSdkVersion="32"')));
    expect(
      manifest,
      isNot(contains('android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS')),
    );
    expect(manifest, isNot(contains('android.permission.SYSTEM_ALERT_WINDOW')));
  });

  test('배터리 최적화는 제한 권한 요청 대신 시스템 설정 목록을 연다', () {
    final dartSource = File(
      'lib/services/permission_service.dart',
    ).readAsStringSync();
    final nativeSource = _readAndroidSource(
      'kotlin/com/devground/daegubus/channels/PermissionChannelHandler.kt',
    );

    expect(
      dartSource,
      isNot(contains('Permission.ignoreBatteryOptimizations')),
    );
    expect(
      nativeSource,
      contains('ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS'),
    );
    expect(
      nativeSource,
      isNot(contains('ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS')),
    );
  });

  test('데이터베이스 파일을 다른 앱에 쓰기 가능하게 만들지 않는다', () {
    final source = _readAndroidSource(
      'kotlin/com/devground/daegubus/utils/DatabaseHelper.kt',
    );

    expect(source, isNot(contains('setWritable(true, false)')));
  });

  test('정류장 추적 반복 작업은 캐시 복귀 시 몰아서 실행되지 않는다', () {
    final source = _readAndroidSource(
      'kotlin/com/devground/daegubus/services/StationTrackingService.kt',
    );

    expect(source, isNot(contains('scheduleAtFixedRate')));
    expect(source, isNot(contains('java.util.Timer')));
    expect(source, contains('while (isActive)'));
    expect(source, contains('delay(TRACKING_INTERVAL_MS)'));
  });
}
