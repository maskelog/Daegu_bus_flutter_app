import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:permission_handler/permission_handler.dart';

class NotificationHelper {
  static final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // 지속적인 알림을 위한 고정 ID 추가
  static const int ongoingNotificationId = 10000;

  /// ✅ 로컬 알림 초기화 (앱 실행 시 최초 1회)
  static Future<void> initialize() async {
    tz_data.initializeTimeZones(); // 시간대 데이터 초기화

    // ✅ Android 초기화 설정
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('ic_bus_notification');

    // ✅ iOS 초기화 설정
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    // ✅ 플랫폼별 초기화 설정 적용
    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    // 알림 응답 처리기 추가
    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        debugPrint(
            '🔔 알림 응답 수신: ${response.notificationResponseType}, 액션: ${response.actionId}, payload: ${response.payload}');
        if (response.notificationResponseType ==
            NotificationResponseType.selectedNotificationAction) {
          if (response.actionId == 'dismiss') {
            debugPrint('🔔 알람 종료 버튼 클릭됨: ${response.id}');
            // 필요에 따라 추가 알람 종료 로직 구현
          } else if (response.actionId == 'stop_tracking') {
            debugPrint('🚌 추적 중지 버튼 클릭됨: ${response.id}');
            // 추적 중지 처리를 수행 (예: 지속적인 추적 알림 취소)
            await cancelOngoingTracking();
          }
        }
      },
    );

    // Android 플랫폼 특화 설정: 알림 액션 핸들러 설정
    final androidImplementation =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      // 알림 액션 클릭에 대한 리스너 설정
      await androidImplementation.requestNotificationsPermission();
      await androidImplementation.requestExactAlarmsPermission();

      // 액션 버튼 클릭 핸들러 등록
      await androidImplementation.createNotificationChannel(
        const AndroidNotificationChannel(
          'bus_alerts',
          'Bus Alerts',
          description: '버스 도착 알림',
          importance: Importance.max,
          enableVibration: true,
          enableLights: true,
        ),
      );
    }

    // ✅ Android 8.0 이상을 위한 알림 채널 생성
    await _createNotificationChannel();

    // ✅ 지속적인 업데이트를 위한 채널 생성
    await _createOngoingNotificationChannel();

    // ✅ 알림 권한 요청
    await requestNotificationPermission();

    // ✅ 알림 채널 확인
    final channels = await getNotificationChannels();
    if (channels != null) {
      for (var channel in channels) {
        debugPrint(
            '알림 채널: ${channel.id}, ${channel.name}, 중요도: ${channel.importance}');
      }
    }
  }

  /// ✅ Android 8.0 이상을 위한 알림 채널 생성
  static Future<void> _createNotificationChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'bus_alerts', // 채널 ID
      'Bus Alerts', // 채널 이름
      description: '버스 도착 알림',
      importance: Importance.max, // 중요도 최대로 높임
      playSound: true,
      sound: RawResourceAndroidNotificationSound('alarm_sound'),
      enableVibration: true,
      enableLights: true,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// ✅ 지속적인 업데이트를 위한 알림 채널 생성
  static Future<void> _createOngoingNotificationChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'bus_ongoing', // 채널 ID
      'Bus Tracking', // 채널 이름
      description: '버스 위치 실시간 추적',
      importance: Importance.low, // 중요도는 낮게 설정 (상태바에만 표시)
      playSound: false,
      enableVibration: false,
      enableLights: false,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  /// ✅ 알림 권한 요청 (Android 13+, iOS 포함)
  static Future<bool> requestNotificationPermission() async {
    // 📌 Android 13 이상: 알림 권한 요청
    if (await Permission.notification.isDenied ||
        await Permission.notification.isPermanentlyDenied) {
      await Permission.notification.request();
    }

    // 📌 iOS: 권한 요청
    final bool? granted = await NotificationHelper
        .flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );

    return granted ?? false;
  }

  /// ✅ 즉시 알림 전송
  static Future<void> showNotification({
    required int id,
    required String busNo,
    required String stationName,
    required int remainingMinutes,
    String? currentStation,
    String? payload,
  }) async {
    // 디버그 로그 추가
    print('🔔 알림 표시 시도: $busNo, $stationName, $remainingMinutes분, ID: $id');

    // 알림 제목과 내용
    String title = '$busNo번 버스 승차 알림';
    String body = '$stationName 정류장 - 약 $remainingMinutes분 후 도착';

    if (currentStation != null && currentStation.isNotEmpty) {
      body += ' (현재 위치: $currentStation)';
    }

    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'bus_alerts', // 채널 ID
      'Bus Alerts', // 채널 이름
      channelDescription: '버스 도착 알림',
      importance: Importance.max,
      priority: Priority.max,
      showWhen: true,
      when: DateTime.now().millisecondsSinceEpoch,
      icon: 'ic_bus_notification',
      color: const Color(0xFFFF5722),
      largeIcon: const DrawableResourceAndroidBitmap('ic_bus_large'),
      sound: const RawResourceAndroidNotificationSound('alarm_sound'),
      ongoing: true,
      autoCancel: false,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
      fullScreenIntent: true,
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction(
          'dismiss',
          '알람 종료',
          showsUserInterface: false,
          cancelNotification: true, // 알림 자동 취소 활성화
        ),
      ],
    );

    const DarwinNotificationDetails iOSPlatformChannelSpecifics =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'alarm_sound.wav',
      badgeNumber: 1,
      threadIdentifier: 'bus_arrival',
    );

    final NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );

    try {
      print('🔔 flutterLocalNotificationsPlugin.show 직전');
      await flutterLocalNotificationsPlugin.show(
        id,
        title,
        body,
        platformChannelSpecifics,
        payload: payload,
      );
      print('🔔 알림 표시 완료: $id');
    } catch (e) {
      print('🔔 알림 표시 오류: $e');
    }
  }

  /// ✅ 지속적인 버스 위치 추적 알림 시작/업데이트
  static Future<void> showOngoingBusTracking({
    required String busNo,
    required String stationName,
    required int remainingMinutes,
    String? currentStation,
    bool isUpdate = false,
  }) async {
    String title = '$busNo번 버스 실시간 추적';

    String body;
    if (remainingMinutes <= 0) {
      body = '$stationName 정류장에 곧 도착합니다!';
    } else {
      body = '$stationName 정류장까지 약 $remainingMinutes분 남았습니다.';
    }
    if (currentStation != null && currentStation.isNotEmpty) {
      body += ' 현재 위치: $currentStation';
    }

    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'bus_ongoing',
      'Bus Tracking',
      channelDescription: '버스 위치 실시간 추적',
      importance: Importance.defaultImportance, // 중요도를 default 또는 high로 조정
      priority: Priority.max, // 최대 우선순위로 변경
      showWhen: true,
      usesChronometer: true,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: false, // 업데이트 시에도 알림 변경을 반영하도록 false로 설정
      icon: 'ic_bus_notification',
      color: const Color(0xFF2196F3),
      progress: 100 - (remainingMinutes > 30 ? 0 : remainingMinutes * 3),
      maxProgress: 100,
      category: AndroidNotificationCategory.service,
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction(
          'stop_tracking',
          '추적 중지',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );

    const DarwinNotificationDetails iOSPlatformChannelSpecifics =
        DarwinNotificationDetails(
      presentAlert: false,
      presentBadge: false,
      presentSound: false,
      interruptionLevel: InterruptionLevel.critical,
      threadIdentifier: 'bus_tracking',
    );

    final NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );

    try {
      await flutterLocalNotificationsPlugin.show(
        ongoingNotificationId,
        title,
        body,
        platformChannelSpecifics,
        payload: 'bus_tracking_$busNo',
      );
      debugPrint(
          '🚌 버스 추적 알림 ${isUpdate ? "업데이트" : "시작"}: $busNo, $remainingMinutes분');
    } catch (e) {
      debugPrint('🚌 버스 추적 알림 오류: $e');
    }
  }

  /// ✅ 버스 도착 임박 알림 (중요도 높음)
  static Future<void> showBusArrivingSoon({
    required String busNo,
    required String stationName,
    String? currentStation,
  }) async {
    final AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'bus_alerts', // 긴급 알림 채널
      'Bus Alerts',
      channelDescription: '버스 도착 알림',
      importance: Importance.max,
      priority: Priority.max,
      showWhen: true,
      when: DateTime.now().millisecondsSinceEpoch,
      icon: 'ic_bus_notification',
      color: const Color(0xFFFF0000), // 빨간색으로 강조
      largeIcon: const DrawableResourceAndroidBitmap('ic_bus_large'),
      sound: const RawResourceAndroidNotificationSound('alarm_sound'),
      vibrationPattern: Int64List.fromList([0, 500, 200, 500, 200, 500]),
      enableLights: true,
      ledColor: const Color(0xFFFF0000),
      ledOnMs: 1000,
      ledOffMs: 500,
      visibility: NotificationVisibility.public,
      fullScreenIntent: true, // 잠금화면에서도 표시
    );

    const DarwinNotificationDetails iOSPlatformChannelSpecifics =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'alarm_sound.wav',
      interruptionLevel: InterruptionLevel.critical, // 가장 높은 방해 수준
      threadIdentifier: 'bus_arrival',
    );

    final NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: iOSPlatformChannelSpecifics,
    );

    String body = '$stationName 정류장에 곧 도착합니다! 탑승 준비하세요.';
    if (currentStation != null && currentStation.isNotEmpty) {
      body += ' 현재 위치: $currentStation';
    }

    try {
      await flutterLocalNotificationsPlugin.show(
        busNo.hashCode, // 버스 번호에 따른 고유 ID
        '⚠️ $busNo번 버스 곧 도착!',
        body,
        platformChannelSpecifics,
      );
      debugPrint('🚨 버스 도착 임박 알림 표시: $busNo');
    } catch (e) {
      debugPrint('🚨 버스 도착 임박 알림 오류: $e');
    }
  }

  /// ✅ 알림 취소 메소드
  static Future<void> cancelNotification(int id) async {
    await NotificationHelper.flutterLocalNotificationsPlugin.cancel(id);
  }

  /// ✅ 지속적인 추적 알림 취소
  static Future<void> cancelOngoingTracking() async {
    await NotificationHelper.flutterLocalNotificationsPlugin
        .cancel(ongoingNotificationId);
  }

  /// ✅ 모든 알림 취소 메소드
  static Future<void> cancelAllNotifications() async {
    await NotificationHelper.flutterLocalNotificationsPlugin.cancelAll();
  }

  /// ✅ 테스트 알림 전송
  static Future<void> showTestNotification() async {
    await showNotification(
      id: 9999,
      busNo: '테스트',
      stationName: '테스트 정류장',
      remainingMinutes: 3,
      currentStation: '테스트 중',
    );
  }
}

Future<List<AndroidNotificationChannel>?> getNotificationChannels() async {
  final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
      NotificationHelper.flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
  return await androidPlugin?.getNotificationChannels();
}
