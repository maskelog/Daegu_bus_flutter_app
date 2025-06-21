import 'dart:async';
import 'dart:convert';
import 'package:daegu_bus_app/models/auto_alarm.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'models/alarm_data.dart' as alarm_model;
import 'screens/home_screen.dart';
import 'services/alarm_service.dart';
import 'services/notification_service.dart';
import 'services/permission_service.dart';
import 'services/settings_service.dart';
import 'utils/database_helper.dart';

// 로거 설정
final Logger _logger = Logger('MyApp');

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

      final autoAlarm = AutoAlarm(
        id: inputData['id']?.toString() ?? '',
        routeNo: inputData['routeNo'] ?? '',
        stationName: inputData['stationName'] ?? '',
        stationId: inputData['stationId'] ?? '',
        routeId: inputData['routeId'] ?? '',
        hour: inputData['hour'] ?? 0,
        minute: inputData['minute'] ?? 0,
        repeatDays:
            (inputData['repeatDays'] as List<dynamic>?)?.cast<int>() ?? [],
        useTTS: inputData['useTTS'] ?? true,
        isActive: true,
      );

      // await alarmService.triggerAutoAlarm(autoAlarm);
      return Future.value(true);
    } catch (e) {
      logMessage('WorkManager 작업 오류: $e', level: LogLevel.error);
      return Future.value(false);
    }
  });
}

/// 애플리케이션 시작점
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

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
