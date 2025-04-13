import 'package:daegu_bus_app/services/backgroud_service.dart';
import 'package:daegu_bus_app/utils/simple_tts_helper.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:developer' as dev;

import 'services/alarm_service.dart';
import 'services/notification_service.dart';
import 'services/permission_service.dart';
import 'screens/home_screen.dart';
import 'package:daegu_bus_app/services/settings_service.dart';
import 'utils/database_helper.dart';
import 'utils/dio_client.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// 로그 레벨 정의 (utils/dio_client.dart의 LogLevel과 일치시킴)
enum LogLevel { none, error, warning, info, debug, verbose }

// 현재 로그 레벨 설정
const LogLevel currentLogLevel = LogLevel.info;

// Dio 클라이언트 인스턴스
final dioClient = DioClient();

// 로깅 유틸리티 함수
void logMessage(String message, {LogLevel level = LogLevel.debug}) {
  if (level.index >= currentLogLevel.index) {
    // 개발 모드에서만 콘솔에 출력
    if (!const bool.fromEnvironment('dart.vm.product')) {
      String prefix;
      switch (level) {
        case LogLevel.debug:
          prefix = '🐛 [DEBUG]';
          break;
        case LogLevel.info:
          prefix = 'ℹ️ [INFO]';
          break;
        case LogLevel.warning:
          prefix = '⚠️ [WARN]';
          break;
        case LogLevel.error:
          prefix = '❌ [ERROR]';
          break;
        default:
          prefix = '[LOG]';
      }

      // 개발자 로그에 기록
      dev.log('$prefix $message', name: level.toString());
    }
  }
}

// 기존 log 함수를 logMessage로 대체
void log(String message, {LogLevel level = LogLevel.debug}) =>
    logMessage(message, level: level);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 앱 시작 로그
  log('🚀 앱 초기화 시작: ${DateTime.now()}', level: LogLevel.info);

  // 데이터베이스 미리 초기화 시작 (백그라운드에서 실행)
  DatabaseHelper.preInitialize();
  log('💾 데이터베이스 초기화 시작됨 (백그라운드)', level: LogLevel.info);

  try {
    await dotenv.load(fileName: '.env');
    log('.env 파일 로드 성공', level: LogLevel.info);
  } catch (e) {
    log('.env 파일 로드 실패 (무시하고 계속): $e', level: LogLevel.warning);
  }

  // 필수 서비스 초기화 - 단계별로 분리하고 각각 오류 처리
  bool settingsInitialized = false;
  bool notificationInitialized = false;
  bool ttsInitialized = false;
  bool alarmManagerInitialized = false;
  bool workManagerInitialized = false;

  // 1. 설정 서비스 초기화
  try {
    await SettingsService().initialize();
    settingsInitialized = true;
    log('✅ SettingsService 초기화 성공', level: LogLevel.info);
  } catch (e) {
    log('⚠️ SettingsService 초기화 오류 (계속 진행): $e', level: LogLevel.error);
  }

  // 2. 알림 서비스 초기화
  try {
    await NotificationService().initialize();
    notificationInitialized = true;
    log('✅ NotificationService 초기화 성공', level: LogLevel.info);
  } catch (e) {
    log('⚠️ NotificationService 초기화 오류 (계속 진행): $e', level: LogLevel.error);
  }

  // 3. TTS 초기화
  try {
    await SimpleTTSHelper.initialize();
    ttsInitialized = true;
    log('✅ TTS 초기화 성공', level: LogLevel.info);
  } catch (e) {
    log('⚠️ TTS 초기화 오류 (계속 진행): $e', level: LogLevel.error);
  }

  // 4. AndroidAlarmManager 초기화
  try {
    await AndroidAlarmManager.initialize();
    alarmManagerInitialized = true;
    log('✅ AndroidAlarmManager 초기화 성공', level: LogLevel.info);
  } catch (e) {
    log('⚠️ AndroidAlarmManager 초기화 오류 (계속 진행): $e', level: LogLevel.error);
  }

  // 5. WorkManager 초기화 - 오류 처리 개선
  try {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: true,
    );
    workManagerInitialized = true;
    log('✅ Workmanager 초기화 완료', level: LogLevel.info);
  } catch (e) {
    log('⚠️ Workmanager 초기화 오류 (계속 진행): $e', level: LogLevel.error);
  }

  // 자동 알람 등록 작업은 앱 시작 후에 비동기적으로 처리
  if (workManagerInitialized) {
    // 앱이 완전히 시작된 후 자동 알람 등록 시도 (30초 지연)
    Future.delayed(const Duration(seconds: 30), () async {
      try {
        log('🕒 자동 알람 초기화 작업 시작 (지연 실행)', level: LogLevel.info);
        await Workmanager().registerOneOffTask(
          'init_auto_alarms',
          'initAutoAlarms',
          initialDelay: const Duration(seconds: 15),
          constraints: Constraints(
            networkType: NetworkType.connected,
            requiresBatteryNotLow: false,
          ),
        );
        log('✅ 자동 알람 초기화 작업 등록 완료', level: LogLevel.info);
      } catch (e) {
        log('⚠️ 자동 알람 작업 등록 오류 (무시): $e', level: LogLevel.error);
      }
    });
  } else {
    log('⚠️ WorkManager 초기화 실패로 자동 알람 등록 건너뜀', level: LogLevel.warning);
  }

  // 안드로이드 전용 앱이므로 권한 요청 진행 (비동기로 처리)
  PermissionService.requestNotificationPermission()
      .then((_) => log('✅ 알림 권한 요청 완료', level: LogLevel.info))
      .catchError((e) => log('⚠️ 알림 권한 요청 오류: $e', level: LogLevel.warning));

  // 초기화 상태 요약 로그
  log('📊 서비스 초기화 상태 요약:', level: LogLevel.info);
  log('   - 설정 서비스: ${settingsInitialized ? '✅' : '❌'}', level: LogLevel.info);
  log('   - 알림 서비스: ${notificationInitialized ? '✅' : '❌'}',
      level: LogLevel.info);
  log('   - TTS: ${ttsInitialized ? '✅' : '❌'}', level: LogLevel.info);
  log('   - AlarmManager: ${alarmManagerInitialized ? '✅' : '❌'}',
      level: LogLevel.info);
  log('   - WorkManager: ${workManagerInitialized ? '✅' : '❌'}',
      level: LogLevel.info);

  log('🚀 앱 UI 시작: ${DateTime.now()}', level: LogLevel.info);

  final alarmService = AlarmService();
  try {
    await alarmService.initialize();
    logMessage('✅ AlarmService 초기화 완료');
  } catch (e) {
    logMessage('❌ AlarmService 초기화 실패: $e', level: LogLevel.error);
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: alarmService),
        ChangeNotifierProvider(create: (_) => SettingsService()),
      ],
      child: const MyApp(),
    ),
  );
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
    WidgetsBinding.instance.addObserver(this);
    log('앱 생명주기 옵저버 등록됨', level: LogLevel.info);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    log('앱 생명주기 옵저버 해제됨', level: LogLevel.info);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      log('포그라운드 전환됨 → TTS 재초기화', level: LogLevel.info);
      SimpleTTSHelper.initialize()
          .then(
            (_) => log('TTS 재초기화 완료', level: LogLevel.info),
          )
          .catchError(
            (error) => log('TTS 재초기화 실패: $error', level: LogLevel.error),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return Container(
        padding: const EdgeInsets.all(16),
        color: Colors.red[100],
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.red[700], size: 60),
            const SizedBox(height: 16),
            Text(
              'Error: ${details.exception}',
              style: TextStyle(
                  color: Colors.red[700], fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              details.stack.toString(),
              style: const TextStyle(fontSize: 12),
              maxLines: 10,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    };

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
