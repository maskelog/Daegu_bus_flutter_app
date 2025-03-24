import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:workmanager/workmanager.dart';
import 'services/alarm_service.dart';
import 'screens/home_screen.dart';
import 'services/notification_service.dart';
import 'utils/tts_helper.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// 로그 레벨을 정의
enum LogLevel { debug, info, warning, error }

// 현재 로그 레벨 설정 (필요에 따라 변경)
const LogLevel currentLogLevel = LogLevel.info;

// 로그 함수: 현재 로그 레벨에 따라 출력 제어
void log(String message, {LogLevel level = LogLevel.debug}) {
  if (level.index >= currentLogLevel.index) {
    // 릴리스 모드에서는 debug 레벨 로그 비활성화
    if (level != LogLevel.debug ||
        !const bool.fromEnvironment('dart.vm.product')) {
      debugPrint(message);
    }
  }
}

/// WorkManager 콜백 핸들러
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    log('WorkManager 태스크 시작: $taskName', level: LogLevel.info);

    try {
      if (taskName == 'busAlarmTask') {
        final busNo = inputData!['busNo'] as String;
        final stationName = inputData['stationName'] as String;
        final remainingMinutes = inputData['remainingMinutes'] as int;
        final currentStation = inputData['currentStation'] as String?;
        final alarmId = inputData['alarmId'] as int;
        // skipNotification 플래그 추가
        final skipNotification =
            inputData['skipNotification'] as bool? ?? false;

        log('버스 알람 실행: $busNo, $stationName, $remainingMinutes분',
            level: LogLevel.info);

        // Wakelock 활성화
        try {
          await WakelockPlus.enable();
        } catch (e) {
          log('Wakelock 오류: $e', level: LogLevel.error);
        }

        // skipNotification 플래그 확인
        if (!skipNotification) {
          // NotificationService 초기화 및 알림 표시
          try {
            final notificationService = NotificationService();
            await notificationService.initialize();
            await notificationService.showNotification(
              id: alarmId,
              busNo: busNo,
              stationName: stationName,
              remainingMinutes: remainingMinutes,
              currentStation: currentStation,
            );
          } catch (e) {
            log('알림 표시 오류: $e', level: LogLevel.error);
          }

          // TTS 초기화 및 실행
          try {
            await TTSHelper.initialize();
            await TTSHelper.speakBusAlert(
              busNo: busNo,
              stationName: stationName,
              remainingMinutes: remainingMinutes,
              currentStation: currentStation,
            );
          } catch (e) {
            log('TTS 오류: $e', level: LogLevel.error);
          }

          // TTS 완료 대기
          await Future.delayed(const Duration(seconds: 10));
        } else {
          log('알림 표시 생략 (트래킹 모드): $busNo, $stationName', level: LogLevel.info);
        }

        // Wakelock 비활성화
        try {
          await WakelockPlus.disable();
        } catch (e) {
          log('Wakelock 비활성화 오류: $e', level: LogLevel.error);
        }

        log('WorkManager 태스크 완료: $taskName', level: LogLevel.info);
      }
      return Future.value(true);
    } catch (e) {
      log('WorkManager 태스크 오류: $e', level: LogLevel.error);
      return Future.value(false);
    }
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // flutter_dotenv를 이용해 .env 파일 로드
  await dotenv.load(fileName: '.env');

  // WorkManager 초기화
  Workmanager().initialize(
    callbackDispatcher,
    isInDebugMode: false, // 디버그 모드 비활성화하여 WorkManager 로그 줄이기
  );

  // 로컬 알림 초기화 - NotificationService로 변경
  await NotificationService().initialize();

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
    log('알림 권한이 승인되었습니다.', level: LogLevel.info);
  } else if (status.isDenied) {
    log('알림 권한이 거부되었습니다.', level: LogLevel.warning);
  } else if (status.isPermanentlyDenied) {
    log('알림 권한이 영구적으로 거부됨. 설정에서 변경 필요.', level: LogLevel.warning);
    openAppSettings();
  }

  // 이제 네이티브 코드에서 권한 처리를 하므로 이 부분은 생략 가능
  // 하지만 호환성을 위해 유지할 수도 있음
  final androidImplementation =
      flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  final bool? granted =
      await androidImplementation?.requestNotificationsPermission();
  log('flutter_local_notifications 권한 상태: ${granted == true ? "승인됨" : "거부됨"}',
      level: LogLevel.info);
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    // 앱 생명주기 옵저버 등록
    WidgetsBinding.instance.addObserver(this);
    log('앱 생명주기 옵저버 등록됨', level: LogLevel.info);
  }

  @override
  void dispose() {
    // 옵저버 해제
    WidgetsBinding.instance.removeObserver(this);
    log('앱 생명주기 옵저버 해제됨', level: LogLevel.info);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      // 앱이 포그라운드로 돌아올 때 TTS 재초기화
      log('앱이 포그라운드로 전환됨: TTS 재초기화 시작', level: LogLevel.info);
      TTSHelper.initialize().then((_) {
        log('TTS 재초기화 완료', level: LogLevel.info);
      }).catchError((error) {
        log('TTS 재초기화 실패: $error', level: LogLevel.error);
      });
    } else if (state == AppLifecycleState.paused) {
      log('앱이 백그라운드로 전환됨', level: LogLevel.info);
    }
  }

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
