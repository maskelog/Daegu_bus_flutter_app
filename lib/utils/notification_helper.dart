import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:permission_handler/permission_handler.dart';

class NotificationHelper {
  static final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  /// ✅ 로컬 알림 초기화 (앱 실행 시 최초 1회)
  static Future<void> initialize() async {
    tz_data.initializeTimeZones(); // 시간대 데이터 초기화

    // ✅ Android 초기화 설정
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('ic_bus_notification'); // 알림 아이콘 설정

    // ✅ iOS 초기화 설정
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: false, // iOS 권한 요청 제거 (직접 권한 요청)
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    // ✅ 플랫폼별 초기화 설정 적용
    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        debugPrint('🔔 알림 클릭됨, payload: ${response.payload}');
      },
    );

    // ✅ Android 8.0 이상을 위한 알림 채널 생성
    await _createNotificationChannel();

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
    debugPrint('🔔 알림 표시 시도: $busNo, $stationName, $remainingMinutes분');

    // 알림 권한 확인 및 로그
    final status = await Permission.notification.status;
    debugPrint('알림 권한 상태: $status');

    if (!status.isGranted) {
      debugPrint('❌ 알림 권한이 없어 알림을 보낼 수 없습니다.');
      await Permission.notification.request(); // 권한 요청 시도
      return;
    }

    // 📌 알림 제목 형식: "[버스번호] 승차알람"
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
      importance: Importance.max, // high에서 max로 변경
      priority: Priority.max, // high에서 max로 변경
      showWhen: true,
      when: DateTime.now().millisecondsSinceEpoch,
      icon: 'ic_bus_notification', // 작은 아이콘
      color: const Color(0xFFFF5722), // 주황색 (버스 테마)
      largeIcon: const DrawableResourceAndroidBitmap('ic_bus_large'),
      sound: const RawResourceAndroidNotificationSound('alarm_sound'),
      ongoing: true, // 사용자가 직접 닫기 전까지 유지
      autoCancel: false, // 자동 닫힘 방지
      category: AndroidNotificationCategory.alarm, // transport에서 alarm으로 변경
      styleInformation: const MediaStyleInformation(htmlFormatContent: true),
      actions: <AndroidNotificationAction>[
        const AndroidNotificationAction(
          'dismiss',
          '알람 종료',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
      visibility: NotificationVisibility.public, // 잠금화면에서도 표시
      fullScreenIntent: true, // 중요 알림으로 처리
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

    await NotificationHelper.flutterLocalNotificationsPlugin.show(
      id,
      title,
      body,
      platformChannelSpecifics,
      payload: payload,
    );
  }

  /// ✅ 알림 취소 메소드
  static Future<void> cancelNotification(int id) async {
    await NotificationHelper.flutterLocalNotificationsPlugin.cancel(id);
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
