import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'services/alarm_service.dart';
import 'services/notification_service.dart';
import 'services/permission_service.dart';
import 'services/settings_service.dart';
import 'services/backgroud_service.dart';
import 'screens/home_screen.dart';
import 'utils/database_helper.dart';
import 'utils/dio_client.dart';
import 'utils/simple_tts_helper.dart';

/// 전역 알림 플러그인 인스턴스
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

/// 로그 레벨 열거형
enum LogLevel {
  none, // 로깅 없음
  error, // 오류만 로깅
  warning, // 경고와 오류 로깅
  info, // 정보, 경고, 오류 로깅
  debug, // 디버그, 정보, 경고, 오류 로깅
  verbose // 모든 로그 출력
}

/// 현재 로그 레벨 설정
const LogLevel currentLogLevel = LogLevel.verbose;

/// Dio 클라이언트 인스턴스
final dioClient = DioClient();

/// 로깅 유틸리티 함수
void logMessage(String message, {LogLevel level = LogLevel.debug}) {
  // 개발 모드에서만 콘솔에 출력
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
    case LogLevel.verbose:
      prefix = '📝 [VERBOSE]';
      break;
    default:
      prefix = '[LOG]';
  }

  // 콘솔에 직접 출력
  debugPrint('$prefix $message');

  // 개발자 로그에도 기록
  dev.log('$prefix $message', name: level.toString());
}

/// 기존 log 함수를 logMessage로 대체 (하위 호환성)
void log(String message, {LogLevel level = LogLevel.debug}) =>
    logMessage(message, level: level);

/// 애플리케이션 시작점
Future<void> main() async {
  // Flutter 엔진 초기화
  WidgetsFlutterBinding.ensureInitialized();

  // 앱 시작 로그
  logMessage('🚀 앱 초기화 시작: ${DateTime.now()}', level: LogLevel.info);

  // 서비스 초기화 상태 추적 변수
  ServiceInitStatus initStatus = ServiceInitStatus();

  try {
    // 1. 데이터베이스 미리 초기화 시작 (백그라운드에서 실행)
    DatabaseHelper.preInitialize();
    logMessage('💾 데이터베이스 초기화 시작됨 (백그라운드)', level: LogLevel.info);

    // 2. 환경 변수 로드
    await _loadEnvironmentVariables();

    // 3. 필수 서비스 초기화
    await _initializeServices(initStatus);

    // 4. 자동 알람 초기화 (성공적으로 초기화된 서비스가 있을 경우)
    if (initStatus.workManagerInitialized) {
      _setupAutoAlarms();
    } else {
      logMessage('⚠️ WorkManager 초기화 실패로 자동 알람 등록 건너뜀',
          level: LogLevel.warning);
    }

    // 5. 권한 요청 진행 (비동기로 처리)
    _requestPermissions();

    // 6. 초기화 상태 요약 로그
    _logInitializationSummary(initStatus);

    // 7. 알람 서비스 초기화
    final alarmService = await _initializeAlarmService();

    // 8. UI 시작
    _startAppUI(alarmService);
  } catch (e) {
    logMessage('❌ 앱 초기화 중 심각한 오류 발생: $e', level: LogLevel.error);

    // 최소한의 서비스로 앱 실행 (완전한 초기화 실패 시)
    _startAppUI(AlarmService());
  }
}

/// 환경 변수 로드
Future<void> _loadEnvironmentVariables() async {
  try {
    await dotenv.load(fileName: '.env');
    logMessage('.env 파일 로드 성공', level: LogLevel.info);
  } catch (e) {
    logMessage('.env 파일 로드 실패 (무시하고 계속): $e', level: LogLevel.warning);
  }
}

/// 필수 서비스 초기화
Future<void> _initializeServices(ServiceInitStatus status) async {
  // 1. 설정 서비스 초기화
  try {
    await SettingsService().initialize();
    status.settingsInitialized = true;
    logMessage('✅ SettingsService 초기화 성공', level: LogLevel.info);
  } catch (e) {
    logMessage('⚠️ SettingsService 초기화 오류 (계속 진행): $e', level: LogLevel.error);
  }

  // 2. 알림 서비스 초기화
  try {
    await NotificationService().initialize();
    status.notificationInitialized = true;
    logMessage('✅ NotificationService 초기화 성공', level: LogLevel.info);
  } catch (e) {
    logMessage('⚠️ NotificationService 초기화 오류 (계속 진행): $e',
        level: LogLevel.error);
  }

  // 3. TTS 초기화
  try {
    await SimpleTTSHelper.initialize();
    status.ttsInitialized = true;
    logMessage('✅ TTS 초기화 성공', level: LogLevel.info);
  } catch (e) {
    logMessage('⚠️ TTS 초기화 오류 (계속 진행): $e', level: LogLevel.error);
  }

  // 4. AndroidAlarmManager 초기화
  try {
    await AndroidAlarmManager.initialize();
    status.alarmManagerInitialized = true;
    logMessage('✅ AndroidAlarmManager 초기화 성공', level: LogLevel.info);
  } catch (e) {
    logMessage('⚠️ AndroidAlarmManager 초기화 오류 (계속 진행): $e',
        level: LogLevel.error);
  }

  // 5. WorkManager 초기화
  try {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: true,
    );
    status.workManagerInitialized = true;
    logMessage('✅ Workmanager 초기화 완료', level: LogLevel.info);
  } catch (e) {
    logMessage('⚠️ Workmanager 초기화 오류 (계속 진행): $e', level: LogLevel.error);
  }
}

/// 자동 알람 설정
void _setupAutoAlarms() {
  // 앱이 완전히 시작된 후 자동 알람 등록 시도 (30초 지연)
  Future.delayed(const Duration(seconds: 30), () async {
    try {
      logMessage('🕒 자동 알람 초기화 작업 시작 (지연 실행)', level: LogLevel.info);
      await Workmanager().registerOneOffTask(
        'init_auto_alarms',
        'initAutoAlarms',
        initialDelay: const Duration(seconds: 15),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
        ),
      );
      logMessage('✅ 자동 알람 초기화 작업 등록 완료', level: LogLevel.info);
    } catch (e) {
      logMessage('⚠️ 자동 알람 작업 등록 오류 (무시): $e', level: LogLevel.error);
    }
  });
}

/// 필요한 권한 요청
void _requestPermissions() {
  PermissionService.requestNotificationPermission()
      .then((_) => logMessage('✅ 알림 권한 요청 완료', level: LogLevel.info))
      .catchError(
          (e) => logMessage('⚠️ 알림 권한 요청 오류: $e', level: LogLevel.warning));
}

/// 초기화 상태 로그 출력
void _logInitializationSummary(ServiceInitStatus status) {
  logMessage('📊 서비스 초기화 상태 요약:', level: LogLevel.info);
  logMessage('   - 설정 서비스: ${status.settingsInitialized ? '✅' : '❌'}',
      level: LogLevel.info);
  logMessage('   - 알림 서비스: ${status.notificationInitialized ? '✅' : '❌'}',
      level: LogLevel.info);
  logMessage('   - TTS: ${status.ttsInitialized ? '✅' : '❌'}',
      level: LogLevel.info);
  logMessage('   - AlarmManager: ${status.alarmManagerInitialized ? '✅' : '❌'}',
      level: LogLevel.info);
  logMessage('   - WorkManager: ${status.workManagerInitialized ? '✅' : '❌'}',
      level: LogLevel.info);
  logMessage('🚀 앱 UI 시작: ${DateTime.now()}', level: LogLevel.info);
}

/// 알람 서비스 초기화
Future<AlarmService> _initializeAlarmService() async {
  final alarmService = AlarmService();
  try {
    await alarmService.initialize();
    logMessage('✅ AlarmService 초기화 완료');
  } catch (e) {
    logMessage('❌ AlarmService 초기화 실패: $e', level: LogLevel.error);
  }
  return alarmService;
}

/// 앱 UI 시작
void _startAppUI(AlarmService alarmService) {
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

/// 서비스 초기화 상태 관리 클래스
class ServiceInitStatus {
  bool settingsInitialized = false;
  bool notificationInitialized = false;
  bool ttsInitialized = false;
  bool alarmManagerInitialized = false;
  bool workManagerInitialized = false;
}

/// 앱 메인 위젯
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
    logMessage('앱 생명주기 옵저버 등록됨', level: LogLevel.info);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    logMessage('앱 생명주기 옵저버 해제됨', level: LogLevel.info);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      logMessage('포그라운드 전환됨 → TTS 재초기화', level: LogLevel.info);
      SimpleTTSHelper.initialize()
          .then(
            (_) => logMessage('TTS 재초기화 완료', level: LogLevel.info),
          )
          .catchError(
            (error) => logMessage('TTS 재초기화 실패: $error', level: LogLevel.error),
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 에러 위젯 커스터마이징
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
