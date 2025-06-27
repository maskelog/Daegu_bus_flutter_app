import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';
import 'package:workmanager/workmanager.dart';
import 'screens/home_screen.dart';
import 'services/alarm_service.dart';
import 'services/notification_service.dart';
import 'services/permission_service.dart';
import 'services/settings_service.dart';
import 'services/alarm_manager.dart';

/// WorkManager 콜백 함수 (백그라운드에서 실행)
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      if (inputData == null) {
        return Future.value(false);
      }

      final notificationService = NotificationService();
      await notificationService.initialize();

      final settingsService = SettingsService();
      await settingsService.initialize();

      // 백그라운드에서는 Provider를 사용할 수 없으므로 직접 생성 및 주입
      final alarmService = AlarmService(
          notificationService: notificationService,
          settingsService: settingsService);
      await alarmService.initialize();

      final String busNo = inputData['busNo'] ?? 'N/A';
      logMessage('백그라운드 작업 실행: $busNo', level: LogLevel.info);

      // await alarmService.triggerAutoAlarm(autoAlarm);
      return Future.value(true);
    } catch (e) {
      logMessage('WorkManager 작업 오류: $e', level: LogLevel.error);
      return Future.value(false);
    }
  });
}

/// Android에서 온 이벤트를 처리하기 위한 MethodChannel 핸들러 설정
void _setupMethodChannelHandlers() {
  const platform = MethodChannel('com.example.daegu_bus_app/notification');

  platform.setMethodCallHandler((call) async {
    try {
      switch (call.method) {
        case 'onAlarmCanceledFromNotification':
          // 특정 알람 취소 이벤트
          final busNo = call.arguments['busNo'] as String? ?? '';
          final routeId = call.arguments['routeId'] as String? ?? '';
          final stationName = call.arguments['stationName'] as String? ?? '';
          final source = call.arguments['source'] as String? ?? '';

          debugPrint(
              '🔄 [SYNC] Android에서 알람 취소 이벤트 수신: $busNo, $routeId, $stationName (source: $source)');

          if (busNo.isNotEmpty &&
              routeId.isNotEmpty &&
              stationName.isNotEmpty) {
            await AlarmManager.cancelAlarm(
              busNo: busNo,
              stationName: stationName,
              routeId: routeId,
            );
          }
          break;

        case 'onAllAlarmsCanceled':
          // 모든 알람 취소 이벤트
          final source = call.arguments?['source'] as String? ?? '';
          debugPrint('🔄 [SYNC] Android에서 모든 알람 취소 이벤트 수신 (source: $source)');

          await AlarmManager.cancelAllAlarms();
          break;

        default:
          debugPrint('⚠️ [WARN] 알 수 없는 메서드 호출: ${call.method}');
      }
    } catch (e) {
      debugPrint('❌ [ERROR] MethodChannel 핸들러 오류: $e');
    }
  });
}

/// 애플리케이션 시작점
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  // Android에서 온 알람 취소 이벤트를 처리하기 위한 MethodChannel 핸들러 설정
  _setupMethodChannelHandlers();

  // 로깅 설정
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    debugPrint(
        '[${record.level.name}] ${record.time}: ${record.loggerName}: ${record.message}');
  });

  // WorkManager 초기화
  if (!kIsWeb) {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: kDebugMode,
    );
  }

  // 서비스 초기화
  final settingsService = SettingsService();
  await settingsService.initialize();

  final permissionService = PermissionService();

  final notificationService = NotificationService();
  await notificationService.initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: notificationService),
        ChangeNotifierProvider.value(value: settingsService),
        Provider.value(value: permissionService),
        ChangeNotifierProvider(
          create: (context) => AlarmService(
            notificationService: context.read<NotificationService>(),
            settingsService: context.read<SettingsService>(),
          ),
        ),
      ],
      child: const MyApp(), // const 제거
    ),
  );
}

class MyApp extends StatelessWidget {
  // const 제거
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsService = Provider.of<SettingsService>(context);
    return MaterialApp(
      title: '대구버스',
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        useMaterial3: true,
      ),
      themeMode: settingsService.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// 로그 레벨 정의
enum LogLevel { debug, info, warning, error }

/// 중앙 로깅 함수
void logMessage(String message,
    {LogLevel level = LogLevel.debug, String? loggerName}) {
  final logger = Logger(loggerName ?? 'App');
  switch (level) {
    case LogLevel.debug:
      logger.fine(message);
      break;
    case LogLevel.info:
      logger.info(message);
      break;
    case LogLevel.warning:
      logger.warning(message);
      break;
    case LogLevel.error:
      logger.severe(message);
      break;
  }
}
