import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/alarm_service.dart';
import 'screens/home_screen.dart';
import 'utils/notification_helper.dart';
import 'utils/tts_helper.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 알람 매니저 초기화
  await AndroidAlarmManager.initialize();

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
