import 'dart:developer' as dev;
import 'dart:ui';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/alarm_service.dart';
import 'services/notification_service.dart';
import 'services/permission_service.dart';
import 'services/settings_service.dart';
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

/// WorkManager 콜백 디스패처 - 백그라운드에서 실행됨
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint('🔔 [WorkManager] 백그라운드 작업 실행: $task');
    debugPrint('🔔 [WorkManager] 입력 데이터: $inputData');

    try {
      switch (task) {
        case 'autoAlarmTask':
          return await _handleAutoAlarmTask(inputData);
        case 'initAutoAlarms':
          return await _handleInitAutoAlarms(inputData);
        default:
          debugPrint('⚠️ [WorkManager] 알 수 없는 작업: $task');
          return Future.value(true);
      }
    } catch (e) {
      debugPrint('❌ [WorkManager] 작업 실행 오류: $e');
      return Future.value(false);
    }
  });
}

/// 자동 알람 작업 처리 함수
@pragma('vm:entry-point')
Future<bool> _handleAutoAlarmTask(Map<String, dynamic>? inputData) async {
  if (inputData == null) {
    debugPrint('❌ [AutoAlarm] inputData가 null입니다');
    return false;
  }

  try {
    // BackgroundIsolateBinaryMessenger 초기화
    try {
      final rootIsolateToken = RootIsolateToken.instance;
      if (rootIsolateToken != null) {
        BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);
        debugPrint('✅ [AutoAlarm] BackgroundIsolateBinaryMessenger 초기화 성공');
      }
    } catch (e) {
      debugPrint('⚠️ [AutoAlarm] BackgroundIsolateBinaryMessenger 초기화 오류: $e');
    }

    final int alarmId = inputData['alarmId'] ?? 0;
    final String busNo = inputData['busNo'] ?? '';
    final String stationName = inputData['stationName'] ?? '';
    final String routeId = inputData['routeId'] ?? '';
    final String stationId = inputData['stationId'] ?? '';
    final int remainingMinutes = inputData['remainingMinutes'] ?? 0;
    final bool useTTS = inputData['useTTS'] ?? true;

    debugPrint('🚌 [AutoAlarm] 자동 알람 실행: $busNo번 버스, $stationName');
    debugPrint(
        '🚌 [AutoAlarm] 파라미터: ID=$alarmId, RouteID=$routeId, StationID=$stationId');

    if (busNo.isEmpty || stationName.isEmpty) {
      debugPrint(
          '❌ [AutoAlarm] 필수 파라미터 누락: busNo=$busNo, stationName=$stationName');
      return false;
    }

    // 백그라운드에서는 네이티브 알림 채널 직접 사용
    try {
      // 네이티브 채널을 통한 알림 표시
      const MethodChannel notificationChannel =
          MethodChannel('com.example.daegu_bus_app/notification');

      // 알림 초기화 시도
      try {
        await notificationChannel.invokeMethod('initialize');
        debugPrint('✅ [AutoAlarm] 네이티브 알림 채널 초기화 성공');
      } catch (e) {
        debugPrint('❌ [AutoAlarm] 네이티브 알림 채널 초기화 실패: $e');
        // 초기화 실패 시에도 계속 진행
      }

      // 실시간 버스 정보 조회 시도
      String? currentStation;
      int actualRemainingMinutes = remainingMinutes;

      if (stationId.isNotEmpty && routeId.isNotEmpty) {
        try {
          debugPrint('🔍 [AutoAlarm] 실시간 버스 정보 조회 시작: $stationId, $routeId');

          // 네이티브 버스 API 호출
          const MethodChannel busApiChannel =
              MethodChannel('com.example.daegu_bus_app/bus_api');

          final result =
              await busApiChannel.invokeMethod('getBusArrivalByRouteId', {
            'stationId': stationId,
            'routeId': routeId,
          });

          if (result != null) {
            try {
              dynamic parsedData;
              if (result is String) {
                parsedData = jsonDecode(result);
              } else {
                parsedData = result;
              }

              // 버스 정보 추출
              List<dynamic> arrivals = [];
              if (parsedData is List) {
                arrivals = parsedData;
              } else if (parsedData is Map &&
                  parsedData.containsKey('arrList')) {
                arrivals = parsedData['arrList'] as List? ?? [];
              }

              if (arrivals.isNotEmpty) {
                final busInfo = arrivals.first;
                if (busInfo is Map) {
                  final estimatedTime = busInfo['arrState'] ??
                      busInfo['estimatedTime'] ??
                      "정보 없음";
                  currentStation =
                      busInfo['bsNm'] ?? busInfo['currentStation'] ?? '정보 없음';

                  // 남은 시간 파싱
                  if (estimatedTime == '곧 도착') {
                    actualRemainingMinutes = 0;
                  } else if (estimatedTime.toString().contains('분')) {
                    final numericValue = estimatedTime
                        .toString()
                        .replaceAll(RegExp(r'[^0-9]'), '');
                    if (numericValue.isNotEmpty) {
                      actualRemainingMinutes =
                          int.tryParse(numericValue) ?? remainingMinutes;
                    }
                  }
                }
              }

              debugPrint(
                  '✅ [AutoAlarm] 실시간 정보 조회 성공: $actualRemainingMinutes분, 위치: $currentStation');
            } catch (e) {
              debugPrint('⚠️ [AutoAlarm] 버스 정보 파싱 오류: $e');
              currentStation = '정보 파싱 실패';
            }
          } else {
            debugPrint('⚠️ [AutoAlarm] 실시간 버스 정보 없음');
            currentStation = '실시간 정보 없음';
          }
        } catch (e) {
          debugPrint('⚠️ [AutoAlarm] 실시간 정보 조회 오류: $e');
          currentStation = '정보 조회 실패';
        }
      }

      // 자동 알람 알림 표시 시도
      bool success = false;
      try {
        final result =
            await notificationChannel.invokeMethod('showOngoingBusTracking', {
          'busNo': busNo,
          'stationName': stationName,
          'remainingMinutes': actualRemainingMinutes,
          'currentStation': currentStation ?? '자동 알람',
          'routeId': routeId,
          'stationId': stationId,
          'notificationId': alarmId,
          'isUpdate': false,
          'isIndividualAlarm': true,
          'action': 'com.example.daegu_bus_app.action.SHOW_INDIVIDUAL_ALARM',
        });
        success = result == true;
        debugPrint('✅ [AutoAlarm] 네이티브 개별 알림 표시 성공: $success');
      } catch (e) {
        debugPrint('❌ [AutoAlarm] 네이티브 개별 알림 표시 오류: $e');

        // 대안: 안드로이드 로컬 알림 생성 시도
        try {
          const MethodChannel mainChannel =
              MethodChannel('com.example.daegu_bus_app/bus_api');
          final result =
              await mainChannel.invokeMethod('showOngoingBusTracking', {
            'busNo': busNo,
            'stationName': stationName,
            'remainingMinutes': actualRemainingMinutes,
            'currentStation': currentStation ?? '자동 알람',
            'routeId': routeId,
            'stationId': stationId,
            'notificationId': alarmId,
            'isUpdate': false,
            'isIndividualAlarm': true,
          });
          success = result == true;
          debugPrint('✅ [AutoAlarm] 메인 채널을 통한 개별 알림 표시 성공: $success');
        } catch (e2) {
          debugPrint('❌ [AutoAlarm] 메인 채널 개별 알림 표시도 실패: $e2');
        }
      }

      // TTS 알림 시도 (이어폰 연결된 경우만)
      if (useTTS) {
        try {
          const MethodChannel ttsChannel =
              MethodChannel('com.example.daegu_bus_app/tts');

          // 이어폰 연결 상태 확인
          final isHeadphoneConnected =
              await ttsChannel.invokeMethod('isHeadphoneConnected');

          if (isHeadphoneConnected == true) {
            String ttsMessage;
            if (actualRemainingMinutes <= 0) {
              ttsMessage = "$busNo번 버스가 $stationName 정류장에 곧 도착합니다.";
            } else {
              ttsMessage = "$busNo번 버스가 약 $actualRemainingMinutes분 후 도착 예정입니다.";
            }

            await ttsChannel.invokeMethod('speakTTS', {
              'message': ttsMessage,
              'isHeadphoneMode': true,
            });
            debugPrint('✅ [AutoAlarm] TTS 발화 완료 (이어폰 모드)');
          } else {
            debugPrint('🎧 [AutoAlarm] 이어폰 미연결 - TTS 건너뜀');
          }
        } catch (e) {
          debugPrint('⚠️ [AutoAlarm] TTS 발화 오류: $e');
        }
      }

      // SharedPreferences에 알람 정보 저장 (앱 활성화 시 처리용)
      try {
        final prefs = await SharedPreferences.getInstance();
        final alarmData = {
          'alarmId': alarmId,
          'busNo': busNo,
          'stationName': stationName,
          'routeId': routeId,
          'stationId': stationId,
          'remainingMinutes': actualRemainingMinutes,
          'currentStation': currentStation,
          'isAutoAlarm': true,
          'hasRealTimeInfo':
              currentStation != null && currentStation.isNotEmpty,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };

        await prefs.setString('last_auto_alarm_data', jsonEncode(alarmData));
        await prefs.setBool('has_new_auto_alarm', true);
        debugPrint('✅ [AutoAlarm] 알람 정보 저장 완료');
      } catch (e) {
        debugPrint('⚠️ [AutoAlarm] 알람 정보 저장 오류: $e');
      }

      return success;
    } catch (e) {
      debugPrint('❌ [AutoAlarm] 알림 표시 오류: $e');
      return false;
    }
  } catch (e) {
    debugPrint('❌ [AutoAlarm] 자동 알람 처리 오류: $e');
    return false;
  }
}

/// 자동 알람 초기화 작업 처리
@pragma('vm:entry-point')
Future<bool> _handleInitAutoAlarms(Map<String, dynamic>? inputData) async {
  debugPrint('🕒 [InitAutoAlarms] 자동 알람 초기화 작업 시작');

  if (inputData != null) {
    final timestamp = inputData['timestamp'];
    final autoAlarmsCount = inputData['autoAlarmsCount'] ?? 0;
    final isRetry = inputData['isRetry'] ?? false;

    debugPrint(
        '🕒 [InitAutoAlarms] 작업 정보: 시간=$timestamp, 알람수=$autoAlarmsCount, 재시도=$isRetry');
  }

  // 실제 자동 알람 초기화 로직은 여기에 구현
  // 현재는 로깅만 수행
  debugPrint('✅ [InitAutoAlarms] 자동 알람 초기화 작업 완료');
  return true;
}

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
    // 작업 재시도 정책 및 제한사항 완화
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: true,
    );
    status.workManagerInitialized = true;
    logMessage('✅ Workmanager 초기화 완료', level: LogLevel.info);

    // 기존 작업 정리
    try {
      await Workmanager().cancelAll();
      logMessage('✅ 기존 WorkManager 작업 모두 취소', level: LogLevel.info);
    } catch (e) {
      logMessage('⚠️ 기존 WorkManager 작업 취소 오류 (무시): $e',
          level: LogLevel.warning);
    }
  } catch (e) {
    logMessage('⚠️ Workmanager 초기화 오류 (계속 진행): $e', level: LogLevel.error);
  }
}

/// 자동 알람 설정
void _setupAutoAlarms() {
  // 앱이 완전히 시작된 후 자동 알람 등록 시도 (10초 지연)
  Future.delayed(const Duration(seconds: 10), () async {
    try {
      logMessage('🕒 자동 알람 초기화 작업 시작 (지연 실행)', level: LogLevel.info);

      // 자동 알람 정보 상태 확인
      final alarmService = AlarmService();
      await alarmService.initialize();
      await alarmService.loadAutoAlarms();
      final autoAlarms = alarmService.autoAlarms;

      logMessage('🕒 현재 자동 알람 상태: ${autoAlarms.length}개', level: LogLevel.info);

      // 자동 알람이 없는 경우 작업 스케줄링 스킵
      if (autoAlarms.isEmpty) {
        logMessage('⚠️ 자동 알람이 없어 작업 스케줄링 스킵', level: LogLevel.info);
        return;
      }

      // 기존 모든 작업 취소
      try {
        await Workmanager().cancelAll();
        logMessage('✅ 기존 모든 WorkManager 작업 취소', level: LogLevel.info);
      } catch (e) {
        logMessage('⚠️ 기존 작업 취소 오류 (무시): $e', level: LogLevel.warning);
      }

      // 새 작업 등록 - 지연 시간 증가
      await Workmanager().registerOneOffTask(
        'init_auto_alarms',
        'initAutoAlarms',
        initialDelay: const Duration(seconds: 5),
        inputData: {
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'autoAlarmsCount': autoAlarms.length,
        },
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: true, // 배터리 부족 시 실행 안함
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: true, // 저장공간 부족 시 실행 안함
        ),
        existingWorkPolicy: ExistingWorkPolicy.replace,
        backoffPolicy: BackoffPolicy.exponential, // 지수적 백오프
        backoffPolicyDelay: const Duration(minutes: 5), // 백오프 지연 시간 증가
      );
      logMessage('✅ 자동 알람 초기화 작업 등록 완료', level: LogLevel.info);

      // 30초 후 다시 한번 시도 (시간 증가)
      Future.delayed(const Duration(seconds: 30), () async {
        try {
          logMessage('🕒 자동 알람 초기화 작업 재시도', level: LogLevel.info);

          // 자동 알람 정보 상태 다시 확인
          final alarmService = AlarmService();
          await alarmService.initialize();
          await alarmService.loadAutoAlarms();
          final autoAlarms = alarmService.autoAlarms;

          if (autoAlarms.isEmpty) {
            logMessage('⚠️ 자동 알람이 없어 작업 스케줄링 스킵', level: LogLevel.info);
            return;
          }

          await Workmanager().registerOneOffTask(
            'init_auto_alarms_retry',
            'initAutoAlarms',
            initialDelay: const Duration(seconds: 5),
            inputData: {
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'autoAlarmsCount': autoAlarms.length,
              'isRetry': true,
            },
            constraints: Constraints(
              networkType: NetworkType.connected,
              requiresBatteryNotLow: true, // 배터리 부족 시 재시도도 실행 안함
              requiresCharging: false,
              requiresDeviceIdle: false,
              requiresStorageNotLow: true, // 저장공간 부족 시 재시도도 실행 안함
            ),
            existingWorkPolicy: ExistingWorkPolicy.replace,
            backoffPolicy: BackoffPolicy.exponential, // 지수적 백오프
            backoffPolicyDelay: const Duration(minutes: 10), // 재시도는 더 긴 지연
          );
          logMessage('✅ 자동 알람 초기화 작업 재시도 등록 완료', level: LogLevel.info);
        } catch (e) {
          logMessage('⚠️ 자동 알람 작업 재시도 오류 (무시): $e', level: LogLevel.error);
        }
      });
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

    // 앱 시작 시 자동 알람 정보 확인 (딜레이 추가)
    Future.delayed(const Duration(seconds: 3), () {
      _checkPendingAutoAlarms();
    });
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

      // 자동 알람 정보 확인
      _checkPendingAutoAlarms();
    }
  }

  /// 백그라운드에서 실행된 자동 알람 정보를 확인하고 처리
  Future<void> _checkPendingAutoAlarms() async {
    try {
      // BackgroundIsolateBinaryMessenger 초기화
      if (!kIsWeb) {
        try {
          final rootIsolateToken = RootIsolateToken.instance;
          if (rootIsolateToken != null) {
            BackgroundIsolateBinaryMessenger.ensureInitialized(
                rootIsolateToken);
            logMessage('✅ BackgroundIsolateBinaryMessenger 초기화 성공',
                level: LogLevel.info);
          } else {
            logMessage('⚠️ RootIsolateToken이 null입니다', level: LogLevel.warning);
          }
        } catch (e) {
          logMessage('⚠️ BackgroundIsolateBinaryMessenger 초기화 오류 (무시): $e',
              level: LogLevel.warning);
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final hasNewAlarm = prefs.getBool('has_new_auto_alarm') ?? false;

      // 자동 알람 상태만 확인하고 자동 복원은 하지 않음
      if (mounted) {
        final alarmService = Provider.of<AlarmService>(context, listen: false);
        await alarmService.loadAutoAlarms();
        logMessage('✅ 자동 알람 상태 확인 완료: ${alarmService.autoAlarms.length}개',
            level: LogLevel.info);
      } else {
        // context가 유효하지 않은 경우 직접 알람 서비스 생성
        final alarmService = AlarmService();
        await alarmService.initialize();
        await alarmService.loadAutoAlarms();
        logMessage(
            '✅ 자동 알람 상태 확인 완료 (직접 생성): ${alarmService.autoAlarms.length}개',
            level: LogLevel.info);
      }

      // 새로운 자동 알람이 없으면 종료
      if (!hasNewAlarm) {
        logMessage('ℹ️ 새로운 자동 알람 없음 - 자동 복원 건너뜀', level: LogLevel.info);
        return;
      }

      // 저장된 자동 알람 데이터 정리 (자동 복원하지 않음)
      await prefs.remove('last_auto_alarm_data');
      await prefs.setBool('has_new_auto_alarm', false);
      logMessage('🧹 저장된 자동 알람 데이터 정리 완료', level: LogLevel.info);
    } catch (e) {
      logMessage('❌ 자동 알람 정보 처리 중 오류: $e', level: LogLevel.error);
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
