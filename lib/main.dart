import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:workmanager/workmanager.dart';
import 'services/alarm_service.dart';
import 'screens/home_screen.dart';
import 'utils/notification_helper.dart';
import 'utils/tts_helper.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

/// Workmanager 콜백 디스패처 (최상위 함수여야 함)
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      // WorkManager 태스크 처리
      if (taskName == 'busAlarmTask') {
        final busNo = inputData!['busNo'] as String;
        final stationName = inputData['stationName'] as String;
        final remainingMinutes = inputData['remainingMinutes'] as int;
        final currentStation = inputData['currentStation'] as String?;
        final alarmId = inputData['alarmId'] as int;

        // NotificationHelper 초기화
        await NotificationHelper.initialize();

        // TTSHelper 초기화
        await TTSHelper.initialize();

        // 알림 표시
        await NotificationHelper.showNotification(
          id: alarmId,
          busNo: busNo,
          stationName: stationName,
          remainingMinutes: remainingMinutes,
          currentStation: currentStation,
        );

        // TTS 실행
        await TTSHelper.speakBusAlert(
          busNo: busNo,
          stationName: stationName,
          remainingMinutes: remainingMinutes,
          currentStation: currentStation,
        );

        // TTS가 완료될 때까지 잠시 대기
        await Future.delayed(const Duration(seconds: 10));
      }
      return Future.value(true);
    } catch (e) {
      print('WorkManager 태스크 오류: $e');
      return Future.value(false);
    }
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // WorkManager 초기화
  Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: true,
  );

  // WorkManager 태스크 등록
  Workmanager().registerOneOffTask(
    "busAlarmTask",
    "busAlarmTask",
    initialDelay: const Duration(seconds: 5), // 테스트용 5초 후 실행
    inputData: {
      'busNo': '123',
      'stationName': '테스트 정류장',
      'remainingMinutes': 1,
      'currentStation': '테스트 위치',
      'alarmId': 12345,
    },
  );

  // 알람 매니저 초기화 (AndroidAlarmManager는 더 이상 사용하지 않음)
  // await AndroidAlarmManager.initialize();

  // 로컬 알림 초기화
  await NotificationHelper.initialize();

  // TTS 초기화
  await TTSHelper.initialize();

  // 알림 권한 요청 (Android 13+ 대응)
  if (Platform.isAndroid) {
    await requestNotificationPermission();
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AlarmService()),
      ],
      child: const MyApp(),
    ),
  );
}

Future<void> requestNotificationPermission() async {
  // permission_handler로 기본 권한 요청
  final status = await Permission.notification.request();

  if (status.isGranted) {
    debugPrint('알림 권한이 승인되었습니다.');
  } else if (status.isDenied) {
    debugPrint('알림 권한이 거부되었습니다.');
  } else if (status.isPermanentlyDenied) {
    debugPrint('알림 권한이 영구적으로 거부됨. 설정에서 변경 필요.');
    openAppSettings(); // ✅ 설정 앱 열기
  }

  // flutter_local_notifications 알림 권한 요청 (Android 13+)
  final androidImplementation =
      flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  if (androidImplementation != null) {
    final bool? granted =
        await androidImplementation.requestNotificationsPermission();
    debugPrint(
        'flutter_local_notifications 권한 상태: ${granted == true ? "승인됨" : "거부됨"}');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '대구 버스',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        scaffoldBackgroundColor: Colors.grey[50],
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
