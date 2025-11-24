import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logging/logging.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/alarm_service.dart';
import 'services/notification_service.dart';
import 'services/permission_service.dart';
import 'services/settings_service.dart';
import 'services/alarm_manager.dart';
import 'services/cache_cleanup_service.dart';

// 전역 AlarmService 인스턴스 (노티피케이션 취소 처리용)
AlarmService? _globalAlarmService;

/// Material 3 색상 체계 정의
class AppColorScheme {
  // Primary Colors (Material 3 동적 색상 시스템)
  static const Color primaryLight = Color(0xFF2E5BFF); // 생동감 있는 파란색
  static const Color onPrimaryLight = Color(0xFFFFFFFF);
  static const Color primaryContainerLight = Color(0xFFDDE1FF);
  static const Color onPrimaryContainerLight = Color(0xFF001C3B);

  // Secondary Colors
  static const Color secondaryLight = Color(0xFF5A5C7E);
  static const Color onSecondaryLight = Color(0xFFFFFFFF);
  static const Color secondaryContainerLight = Color(0xFFE0E1FF);
  static const Color onSecondaryContainerLight = Color(0xFF171937);

  // Tertiary Colors (대구 지역 특색을 살린 색상)
  static const Color tertiaryLight = Color(0xFF755A2F);
  static const Color onTertiaryLight = Color(0xFFFFFFFF);
  static const Color tertiaryContainerLight = Color(0xFFFFDDAE);
  static const Color onTertiaryContainerLight = Color(0xFF2A1800);

  // Surface Colors
  static const Color surfaceLight = Color(0xFFFEFBFF);
  static const Color onSurfaceLight = Color(0xFF1B1B1F);
  static const Color surfaceVariantLight = Color(0xFFE4E1EC);
  static const Color onSurfaceVariantLight = Color(0xFF47464F);

  // Background Colors
  static const Color backgroundLight = Color(0xFFFEFBFF);
  static const Color onBackgroundLight = Color(0xFF1B1B1F);

  // Error Colors - 더 강한 대비 제공
  static const Color errorLight = Color(0xFFD32F2F); // 더 진한 빨간색
  static const Color onErrorLight = Color(0xFFFFFFFF);
  static const Color errorContainerLight = Color(0xFFFFCDD2); // 더 밝은 배경
  static const Color onErrorContainerLight = Color(0xFF410002);

  // Outline Colors
  static const Color outlineLight = Color(0xFF777680);
  static const Color outlineVariantLight = Color(0xFFC8C5D0);

  // Dark Theme Colors
  static const Color primaryDark = Color(0xFFB8C4FF);
  static const Color onPrimaryDark = Color(0xFF002E5F);
  static const Color primaryContainerDark = Color(0xFF004493);
  static const Color onPrimaryContainerDark = Color(0xFFDDE1FF);

  static const Color secondaryDark = Color(0xFFC4C5DD);
  static const Color onSecondaryDark = Color(0xFF2D2F4D);
  static const Color secondaryContainerDark = Color(0xFF434465);
  static const Color onSecondaryContainerDark = Color(0xFFE0E1FF);

  static const Color tertiaryDark = Color(0xFFE4C18A);
  static const Color onTertiaryDark = Color(0xFF422C05);
  static const Color tertiaryContainerDark = Color(0xFF5B421A);
  static const Color onTertiaryContainerDark = Color(0xFFFFDDAE);

  static const Color surfaceDark = Color(0xFF131316);
  static const Color onSurfaceDark = Color(0xFFFFFFFF); // 더 강한 흰색으로 변경
  static const Color surfaceVariantDark = Color(0xFF47464F);
  static const Color onSurfaceVariantDark = Color(0xFFE0E0E0); // 더 강한 대비

  static const Color backgroundDark = Color(0xFF131316);
  static const Color onBackgroundDark = Color(0xFFFFFFFF); // 더 강한 흰색으로 변경

  // 색각이상 사용자를 위한 추가 색상
  static const Color accessibleGreen = Color(0xFF4CAF50);
  static const Color accessibleBlue = Color(0xFF2196F3);
  static const Color accessibleOrange = Color(0xFFFF9800);
  static const Color accessibleRed = Color(0xFFE53935);
  static const Color accessibleGrey = Color(0xFF757575);

  // Light ColorScheme
  static const ColorScheme lightColorScheme = ColorScheme.light(
    primary: primaryLight,
    onPrimary: onPrimaryLight,
    primaryContainer: primaryContainerLight,
    onPrimaryContainer: onPrimaryContainerLight,
    secondary: secondaryLight,
    onSecondary: onSecondaryLight,
    secondaryContainer: secondaryContainerLight,
    onSecondaryContainer: onSecondaryContainerLight,
    tertiary: tertiaryLight,
    onTertiary: onTertiaryLight,
    tertiaryContainer: tertiaryContainerLight,
    onTertiaryContainer: onTertiaryContainerLight,
    surface: surfaceLight,
    onSurface: onSurfaceLight,
    surfaceContainerHighest: surfaceVariantLight,
    onSurfaceVariant: onSurfaceVariantLight,
    error: errorLight,
    onError: onErrorLight,
    errorContainer: errorContainerLight,
    onErrorContainer: onErrorContainerLight,
    outline: outlineLight,
    outlineVariant: outlineVariantLight,
  );

  // Dark ColorScheme
  static const ColorScheme darkColorScheme = ColorScheme.dark(
    primary: primaryDark,
    onPrimary: onPrimaryDark,
    primaryContainer: primaryContainerDark,
    onPrimaryContainer: onPrimaryContainerDark,
    secondary: secondaryDark,
    onSecondary: onSecondaryDark,
    secondaryContainer: secondaryContainerDark,
    onSecondaryContainer: onSecondaryContainerDark,
    tertiary: tertiaryDark,
    onTertiary: onTertiaryDark,
    tertiaryContainer: tertiaryContainerDark,
    onTertiaryContainer: onTertiaryContainerDark,
    surface: surfaceDark,
    onSurface: onSurfaceDark,
    surfaceContainerHighest: surfaceVariantDark,
    onSurfaceVariant: onSurfaceVariantDark,
    error: errorLight,
    onError: onErrorLight,
    errorContainer: errorContainerLight,
    onErrorContainer: onErrorContainerLight,
    outline: outlineLight,
    outlineVariant: outlineVariantLight,
  );
}

/// Material 3 테마 생성
class AppTheme {
  /// ColorSchemeType에 따른 컬러 스키마 생성
  static ColorScheme getColorScheme(
      ColorSchemeType type, Brightness brightness) {
    Color seedColor;

    switch (type) {
      case ColorSchemeType.blue:
        seedColor = const Color(0xFF2E5BFF);
        break;
      case ColorSchemeType.green:
        seedColor = const Color(0xFF4CAF50);
        break;
      case ColorSchemeType.purple:
        seedColor = const Color(0xFF9C27B0);
        break;
      case ColorSchemeType.orange:
        seedColor = const Color(0xFFFF9800);
        break;
      case ColorSchemeType.pink:
        seedColor = const Color(0xFFE91E63);
        break;
      case ColorSchemeType.red:
        seedColor = const Color(0xFFF44336);
        break;
      case ColorSchemeType.teal:
        seedColor = const Color(0xFF009688);
        break;
      case ColorSchemeType.indigo:
        seedColor = const Color(0xFF3F51B5);
        break;
    }

    return ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );
  }

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    colorScheme: AppColorScheme.lightColorScheme,

    // Typography (Material 3 스타일)
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontSize: 57,
        fontWeight: FontWeight.w400,
        letterSpacing: -0.25,
        height: 1.12,
      ),
      displayMedium: TextStyle(
        fontSize: 45,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 1.16,
      ),
      displaySmall: TextStyle(
        fontSize: 36,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 1.22,
      ),
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 1.25,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 1.29,
      ),
      headlineSmall: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w400,
        letterSpacing: 0,
        height: 1.33,
      ),
      titleLarge: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
        height: 1.27,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.15,
        height: 1.5,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
        height: 1.43,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.5,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.25,
        height: 1.43,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.4,
        height: 1.33,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
        height: 1.43,
      ),
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        height: 1.33,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.5,
        height: 1.45,
      ),
    ),

    // AppBar Theme
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 3,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      iconTheme: IconThemeData(size: 24),
      titleTextStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
        height: 1.27,
      ),
    ),

    // Card Theme
    cardTheme: CardThemeData(
      elevation: 1,
      shadowColor: Colors.transparent,
      surfaceTintColor: AppColorScheme.lightColorScheme.surfaceTint,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      margin: const EdgeInsets.all(4),
    ),

    // Elevated Button Theme
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 1,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
        ),
      ),
    ),

    // Filled Button Theme
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
        ),
      ),
    ),

    // Outlined Button Theme
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        side: BorderSide(
          color: AppColorScheme.lightColorScheme.outline,
        ),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
        ),
      ),
    ),

    // Text Button Theme
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.1,
        ),
      ),
    ),

    // Floating Action Button Theme
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),

    // Navigation Bar Theme
    navigationBarTheme: NavigationBarThemeData(
      elevation: 3,
      height: 80,
      backgroundColor: AppColorScheme.lightColorScheme.surface,
      surfaceTintColor: AppColorScheme.lightColorScheme.surfaceTint,
      indicatorColor: AppColorScheme.lightColorScheme.secondaryContainer,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(
            color: AppColorScheme.lightColorScheme.onSecondaryContainer,
            size: 24,
          );
        }
        return IconThemeData(
          color: AppColorScheme.lightColorScheme.onSurfaceVariant,
          size: 24,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return TextStyle(
            color: AppColorScheme.lightColorScheme.onSurface,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          );
        }
        return TextStyle(
          color: AppColorScheme.lightColorScheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        );
      }),
    ),

    // Chip Theme
    chipTheme: ChipThemeData(
      elevation: 0,
      pressElevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      labelStyle: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    ),

    // Input Decoration Theme
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColorScheme.lightColorScheme.surfaceContainerHighest
          .withValues(alpha: 0.4),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: AppColorScheme.lightColorScheme.primary,
          width: 2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: AppColorScheme.lightColorScheme.error,
          width: 1,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),

    // List Tile Theme
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      minVerticalPadding: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),

    // Visual Density
    visualDensity: VisualDensity.adaptivePlatformDensity,
  );

  static ThemeData darkTheme = lightTheme.copyWith(
    colorScheme: AppColorScheme.darkColorScheme,
    cardTheme: lightTheme.cardTheme.copyWith(
      surfaceTintColor: AppColorScheme.darkColorScheme.surfaceTint,
    ),
    navigationBarTheme: lightTheme.navigationBarTheme.copyWith(
      backgroundColor: AppColorScheme.darkColorScheme.surface,
      surfaceTintColor: AppColorScheme.darkColorScheme.surfaceTint,
      indicatorColor: AppColorScheme.darkColorScheme.secondaryContainer,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(
            color: AppColorScheme.darkColorScheme.onSecondaryContainer,
            size: 24,
          );
        }
        return IconThemeData(
          color: AppColorScheme.darkColorScheme.onSurfaceVariant,
          size: 24,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return TextStyle(
            color: AppColorScheme.darkColorScheme.onSurface,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          );
        }
        return TextStyle(
          color: AppColorScheme.darkColorScheme.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        );
      }),
    ),
    inputDecorationTheme: lightTheme.inputDecorationTheme.copyWith(
      fillColor: AppColorScheme.darkColorScheme.surfaceContainerHighest
          .withValues(alpha: 0.4),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: AppColorScheme.darkColorScheme.primary,
          width: 2,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: AppColorScheme.darkColorScheme.error,
          width: 1,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: lightTheme.outlinedButtonTheme.style?.copyWith(
        side: WidgetStateProperty.all(BorderSide(
          color: AppColorScheme.darkColorScheme.outline,
        )),
      ),
    ),
  );
}



/// Android에서 온 이벤트를 처리하기 위한 MethodChannel 핸들러 설정
void _setupMethodChannelHandlers() {
  const platform = MethodChannel('com.example.daegu_bus_app/bus_api');

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

        case 'cancelAlarmFromNotification':
          // 노티피케이션에서 직접 알람 취소 요청
          final busNo = call.arguments['busNo'] as String? ?? '';
          final routeId = call.arguments['routeId'] as String? ?? '';
          final stationName = call.arguments['stationName'] as String? ?? '';
          final alarmId = call.arguments['alarmId'] as int? ?? 0;

          debugPrint(
              '🔔 [NOTIFICATION] 노티피케이션에서 알람 취소 요청: $busNo, $routeId, $stationName (ID: $alarmId)');

          if (busNo.isNotEmpty &&
              routeId.isNotEmpty &&
              stationName.isNotEmpty) {
            // 전역 AlarmService를 통해 알람 취소
            if (_globalAlarmService != null) {
              await _globalAlarmService!
                  .cancelAlarmByRoute(busNo, stationName, routeId);
              debugPrint('✅ [NOTIFICATION] Flutter에서 알람 취소 완료: $busNo');
            } else {
              // 전역 서비스가 없으면 AlarmManager 사용
              await AlarmManager.cancelAlarm(
                busNo: busNo,
                stationName: stationName,
                routeId: routeId,
              );
              debugPrint('✅ [NOTIFICATION] AlarmManager로 알람 취소 완료: $busNo');
            }
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

  // WorkManager 및 권한 초기화 (웹이 아닌 경우)
  if (!kIsWeb) {
    // 모든 권한 요청
    await PermissionService.requestAllPermissions();

    
  }

  // 서비스 초기화
  final settingsService = SettingsService();
  await settingsService.initialize();

  final notificationService = NotificationService();
  await notificationService.initialize();

  // 캐시 정리 서비스 초기화
  final cacheCleanupService = CacheCleanupService.instance;
  await cacheCleanupService.initialize();

  // 전역 AlarmService 초기화 (노티피케이션 취소 처리용)
  _globalAlarmService = AlarmService(
    notificationService: notificationService,
    settingsService: settingsService,
  );
  await _globalAlarmService!.initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: notificationService),
        ChangeNotifierProvider.value(value: settingsService),
        ChangeNotifierProvider.value(value: _globalAlarmService!),
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
    return Consumer<SettingsService>(
      builder: (context, settingsService, child) {
        // 선택된 컬러 스키마로 테마 생성
        final lightColorScheme = AppTheme.getColorScheme(
          settingsService.colorScheme,
          Brightness.light,
        );
        final darkColorScheme = AppTheme.getColorScheme(
          settingsService.colorScheme,
          Brightness.dark,
        );

        // 폰트 크기 배율을 적용한 테마 생성
        final adjustedLightTheme = AppTheme.lightTheme.copyWith(
          colorScheme: lightColorScheme,
          textTheme: _scaleTextTheme(AppTheme.lightTheme.textTheme, settingsService.fontSizeMultiplier),
        );
        final adjustedDarkTheme = AppTheme.darkTheme.copyWith(
          colorScheme: darkColorScheme,
          textTheme: _scaleTextTheme(AppTheme.darkTheme.textTheme, settingsService.fontSizeMultiplier),
        );

        return MaterialApp(
          title: '대구버스',
          theme: adjustedLightTheme,
          darkTheme: adjustedDarkTheme,
          themeMode: settingsService.themeMode,
          home: const HomeScreen(),
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
  
  // 텍스트 테마에 폰트 크기 배율 적용
  static TextTheme _scaleTextTheme(TextTheme textTheme, double scaleFactor) {
    return TextTheme(
      displayLarge: textTheme.displayLarge?.copyWith(
        fontSize: (textTheme.displayLarge?.fontSize ?? 57) * scaleFactor,
      ),
      displayMedium: textTheme.displayMedium?.copyWith(
        fontSize: (textTheme.displayMedium?.fontSize ?? 45) * scaleFactor,
      ),
      displaySmall: textTheme.displaySmall?.copyWith(
        fontSize: (textTheme.displaySmall?.fontSize ?? 36) * scaleFactor,
      ),
      headlineLarge: textTheme.headlineLarge?.copyWith(
        fontSize: (textTheme.headlineLarge?.fontSize ?? 32) * scaleFactor,
      ),
      headlineMedium: textTheme.headlineMedium?.copyWith(
        fontSize: (textTheme.headlineMedium?.fontSize ?? 28) * scaleFactor,
      ),
      headlineSmall: textTheme.headlineSmall?.copyWith(
        fontSize: (textTheme.headlineSmall?.fontSize ?? 24) * scaleFactor,
      ),
      titleLarge: textTheme.titleLarge?.copyWith(
        fontSize: (textTheme.titleLarge?.fontSize ?? 22) * scaleFactor,
      ),
      titleMedium: textTheme.titleMedium?.copyWith(
        fontSize: (textTheme.titleMedium?.fontSize ?? 16) * scaleFactor,
      ),
      titleSmall: textTheme.titleSmall?.copyWith(
        fontSize: (textTheme.titleSmall?.fontSize ?? 14) * scaleFactor,
      ),
      bodyLarge: textTheme.bodyLarge?.copyWith(
        fontSize: (textTheme.bodyLarge?.fontSize ?? 16) * scaleFactor,
      ),
      bodyMedium: textTheme.bodyMedium?.copyWith(
        fontSize: (textTheme.bodyMedium?.fontSize ?? 14) * scaleFactor,
      ),
      bodySmall: textTheme.bodySmall?.copyWith(
        fontSize: (textTheme.bodySmall?.fontSize ?? 12) * scaleFactor,
      ),
      labelLarge: textTheme.labelLarge?.copyWith(
        fontSize: (textTheme.labelLarge?.fontSize ?? 14) * scaleFactor,
      ),
      labelMedium: textTheme.labelMedium?.copyWith(
        fontSize: (textTheme.labelMedium?.fontSize ?? 12) * scaleFactor,
      ),
      labelSmall: textTheme.labelSmall?.copyWith(
        fontSize: (textTheme.labelSmall?.fontSize ?? 11) * scaleFactor,
      ),
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
