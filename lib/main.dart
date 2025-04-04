import 'dart:io';
import 'package:daegu_bus_app/services/backgroud_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'services/alarm_service.dart';
import 'services/notification_service.dart';
import 'services/permission_service.dart';
import 'screens/home_screen.dart';
import 'utils/tts_helper.dart';
import 'package:daegu_bus_app/services/settings_service.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

enum LogLevel { debug, info, warning, error }

const LogLevel currentLogLevel = LogLevel.info;

void log(String message, {LogLevel level = LogLevel.debug}) {
  if (level.index >= currentLogLevel.index) {
    if (level != LogLevel.debug ||
        !const bool.fromEnvironment('dart.vm.product')) {
      debugPrint(message);
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  try {
    await AndroidAlarmManager.initialize();
    log('AndroidAlarmManager 초기화 성공', level: LogLevel.info);
  } catch (e) {
    log('AndroidAlarmManager 초기화 오류: $e', level: LogLevel.error);
  }

  try {
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
    log('Workmanager 초기화 완료', level: LogLevel.info);
  } catch (e) {
    log('Workmanager 초기화 오류: $e', level: LogLevel.error);
  }

  try {
    await NotificationService().initialize();
  } catch (e) {
    log('NotificationService 초기화 오류: $e', level: LogLevel.error);
  }

  try {
    await TTSHelper.initialize();
  } catch (e) {
    log('TTS 초기화 오류: $e', level: LogLevel.error);
  }

  try {
    await SettingsService().initialize();
    log('SettingsService 초기화 성공', level: LogLevel.info);
  } catch (e) {
    log('SettingsService 초기화 오류: $e', level: LogLevel.error);
  }

  if (Platform.isAndroid) {
    try {
      await PermissionService.requestNotificationPermission();
    } catch (e) {
      log('알림 권한 요청 오류: $e', level: LogLevel.warning);
    }
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AlarmService()),
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
      TTSHelper.initialize()
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
