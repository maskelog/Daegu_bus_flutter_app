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
import 'screens/startup_screen.dart';
import 'services/settings_service.dart';
import 'services/alarm_manager.dart';
import 'services/cache_cleanup_service.dart';

// 전역 AlarmService 인스턴스 (노티피케이션 취소 처리용)
AlarmService? _globalAlarmService;

/// Material 3 색상 체계 정의
class AppColorScheme {
  // Premium Blue Palette (Trust, Professionalism)
  // Primary: Deep, vibrant blue
  static const Color primaryLight = Color(0xFF2563EB); 
  static const Color onPrimaryLight = Color(0xFFFFFFFF);
  static const Color primaryContainerLight = Color(0xFFDBEAFE);
  static const Color onPrimaryContainerLight = Color(0xFF1E3A8A);

  // Secondary: Slate/Cool Gray (Modern UI)
  static const Color secondaryLight = Color(0xFF475569);
  static const Color onSecondaryLight = Color(0xFFFFFFFF);
  static const Color secondaryContainerLight = Color(0xFFF1F5F9);
  static const Color onSecondaryContainerLight = Color(0xFF0F172A);

  // Tertiary: Accent (e.g., for specific route types or highlights)
  static const Color tertiaryLight = Color(0xFF0EA5E9); // Sky Blue
  static const Color onTertiaryLight = Color(0xFFFFFFFF);
  static const Color tertiaryContainerLight = Color(0xFFE0F2FE);
  static const Color onTertiaryContainerLight = Color(0xFF075985);

  // Surface & Background (Clean White/Off-white)
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color onSurfaceLight = Color(0xFF0F172A); // Almost Black
  static const Color surfaceVariantLight = Color(0xFFF8FAFC);
  static const Color onSurfaceVariantLight = Color(0xFF64748B);

  static const Color backgroundLight = Color(0xFFF8FAFC); // Very light gray for background
  static const Color onBackgroundLight = Color(0xFF0F172A);

  // Error
  static const Color errorLight = Color(0xFFDC2626);
  static const Color onErrorLight = Color(0xFFFFFFFF);
  static const Color errorContainerLight = Color(0xFFFEE2E2);
  static const Color onErrorContainerLight = Color(0xFF7F1D1D);

  // Outline
  static const Color outlineLight = Color(0xFFCBD5E1);
  static const Color outlineVariantLight = Color(0xFFE2E8F0);

  // Dark Theme (Sleek Dark Mode)
  static const Color primaryDark = Color(0xFF60A5FA);
  static const Color onPrimaryDark = Color(0xFF1E3A8A);
  static const Color primaryContainerDark = Color(0xFF1E40AF);
  static const Color onPrimaryContainerDark = Color(0xFFDBEAFE);

  static const Color secondaryDark = Color(0xFF94A3B8);
  static const Color onSecondaryDark = Color(0xFF0F172A);
  static const Color secondaryContainerDark = Color(0xFF334155);
  static const Color onSecondaryContainerDark = Color(0xFFF1F5F9);

  static const Color tertiaryDark = Color(0xFF38BDF8);
  static const Color onTertiaryDark = Color(0xFF0C4A6E);
  static const Color tertiaryContainerDark = Color(0xFF075985);
  static const Color onTertiaryContainerDark = Color(0xFFE0F2FE);

  static const Color surfaceDark = Color(0xFF0F172A); // Slate 900
  static const Color onSurfaceDark = Color(0xFFF8FAFC);
  static const Color surfaceVariantDark = Color(0xFF1E293B); // Slate 800
  static const Color onSurfaceVariantDark = Color(0xFFCBD5E1);

  static const Color backgroundDark = Color(0xFF020617); // Slate 950
  static const Color onBackgroundDark = Color(0xFFF8FAFC);

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
    // Add Surface Tint for elevation effects
    surfaceTint: primaryLight,
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
    surfaceTint: primaryDark,
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
        // Premium Blue (New)
        if (brightness == Brightness.light) {
             return AppColorScheme.lightColorScheme;
        } else {
             return AppColorScheme.darkColorScheme;
        }
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
    
    // Material 3 Expressive Typography - More pronounced, larger display styles
    textTheme: const TextTheme(
      displayLarge: TextStyle(fontSize: 64, fontWeight: FontWeight.w900, letterSpacing: -1.0, height: 1.15),
      displayMedium: TextStyle(fontSize: 52, fontWeight: FontWeight.w800, letterSpacing: -0.5, height: 1.2),
      displaySmall: TextStyle(fontSize: 40, fontWeight: FontWeight.w700, letterSpacing: -0.25, height: 1.25),
      headlineLarge: TextStyle(fontSize: 36, fontWeight: FontWeight.w700, letterSpacing: -0.5, height: 1.3),
      headlineMedium: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: 0, height: 1.3),
      headlineSmall: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, letterSpacing: 0, height: 1.35),
      titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: 0, height: 1.4),
      titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 0.15, height: 1.4),
      titleSmall: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.1, height: 1.45),
      bodyLarge: TextStyle(fontSize: 17, fontWeight: FontWeight.w400, letterSpacing: 0.5, height: 1.6),
      bodyMedium: TextStyle(fontSize: 15, fontWeight: FontWeight.w400, letterSpacing: 0.25, height: 1.6),
      bodySmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, letterSpacing: 0.4, height: 1.5),
      labelLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.1),
      labelMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.5),
      labelSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.5),
    ),

    // Card Theme - Material 3 Expressive: NO BORDERS, Strong elevation, Clean
    cardTheme: CardThemeData(
      elevation: 4, // MUCH stronger elevation - no borders needed
      shadowColor: Colors.black.withOpacity(0.08),
      surfaceTintColor: AppColorScheme.primaryLight.withOpacity(0.05),
      color: AppColorScheme.surfaceLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide.none, // NO BORDER - clean Material 3 Expressive
      ),
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 20), // More spacing
    ),

    // AppBar Theme - Bolder
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        fontSize: 32, // Even LARGER for impact
        fontWeight: FontWeight.w900, // Bolder
        color: AppColorScheme.onSurfaceLight,
        letterSpacing: -1.0,
      ),
    ),

    // Input Decoration - Clean, no borders
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColorScheme.surfaceVariantLight,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide.none, // No border
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide.none, // No border
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: const BorderSide(color: AppColorScheme.primaryLight, width: 3), // Thicker, more visible
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24), // Much more padding
      hintStyle: const TextStyle(color: AppColorScheme.onSurfaceVariantLight, fontSize: 17),
    ),
    
    // Elevated Button - Bold and prominent
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 4, // Stronger elevation
        shadowColor: AppColorScheme.primaryLight.withOpacity(0.4),
        backgroundColor: AppColorScheme.primaryLight,
        foregroundColor: AppColorScheme.onPrimaryLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 22), // Even larger
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: 0.5),
      ),
    ),

    // Filled Button - New
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        elevation: 0,
        backgroundColor: AppColorScheme.primaryLight,
        foregroundColor: AppColorScheme.onPrimaryLight,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17, letterSpacing: 0.5),
      ),
    ),

    // FAB Theme - BOLD, High elevation
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 6, // Much higher
      highlightElevation: 12, // Double the highlight
      backgroundColor: AppColorScheme.primaryLight, // Use primary for boldness
      foregroundColor: AppColorScheme.onPrimaryLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)), // Even rounder
      extendedPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      extendedTextStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 0.5),
    ),

    // Chip Theme - Clean, no borders
    chipTheme: ChipThemeData(
      backgroundColor: AppColorScheme.surfaceVariantLight,
      selectedColor: AppColorScheme.primaryLight, // Vibrant selected state
      side: BorderSide.none, // No borders
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      labelStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      elevation: 2,
      selectedShadowColor: AppColorScheme.primaryLight.withOpacity(0.5),
    ),

    // Navigation Bar - Clean and prominent
    navigationBarTheme: NavigationBarThemeData(
      elevation: 4, // Stronger elevation
      height: 88, // Taller for more impact
      backgroundColor: AppColorScheme.surfaceLight,
      surfaceTintColor: AppColorScheme.primaryLight.withOpacity(0.05),
      indicatorColor: AppColorScheme.primaryLight, // Bold indicator
      shadowColor: Colors.black.withOpacity(0.1),
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(fontSize: 14, fontWeight: FontWeight.w900);
        }
        return const TextStyle(fontSize: 13, fontWeight: FontWeight.w500);
      }),
    ),

    // Bottom Sheet Theme
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColorScheme.surfaceLight,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      elevation: 3,
    ),

    // Dialog Theme
    dialogTheme: DialogThemeData(
      backgroundColor: AppColorScheme.surfaceLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      elevation: 3,
      titleTextStyle: const TextStyle(
        fontSize: 24, 
        fontWeight: FontWeight.w700,
        color: AppColorScheme.onSurfaceLight,
      ),
    ),
  );

  static ThemeData darkTheme = lightTheme.copyWith(
    colorScheme: AppColorScheme.darkColorScheme,
    scaffoldBackgroundColor: AppColorScheme.backgroundDark,
    
    cardTheme: lightTheme.cardTheme.copyWith(
      color: AppColorScheme.surfaceVariantDark,
      elevation: 2, // Slightly more elevation in dark mode for better depth perception
      shadowColor: Colors.black.withOpacity(0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: BorderSide.none, // Cleaner in dark mode
      ),
    ),
    
    appBarTheme: lightTheme.appBarTheme.copyWith(
      titleTextStyle: const TextStyle(
        fontSize: 28, 
        fontWeight: FontWeight.w700, 
        color: AppColorScheme.onSurfaceDark,
        letterSpacing: -0.5,
      ),
    ),
    
    inputDecorationTheme: lightTheme.inputDecorationTheme.copyWith(
      fillColor: AppColorScheme.surfaceVariantDark,
      hintStyle: const TextStyle(color: AppColorScheme.onSurfaceVariantDark),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: const BorderSide(color: AppColorScheme.primaryDark, width: 2.5),
      ),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 2,
        shadowColor: AppColorScheme.primaryDark.withOpacity(0.4),
        backgroundColor: AppColorScheme.primaryDark,
        foregroundColor: AppColorScheme.onPrimaryDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17, letterSpacing: 0.5),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        elevation: 0,
        backgroundColor: AppColorScheme.primaryDark,
        foregroundColor: AppColorScheme.onPrimaryDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17, letterSpacing: 0.5),
      ),
    ),

    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 3,
      highlightElevation: 6,
      backgroundColor: AppColorScheme.primaryContainerDark,
      foregroundColor: AppColorScheme.onPrimaryContainerDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      extendedPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      extendedTextStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, letterSpacing: 0.5),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: AppColorScheme.surfaceVariantDark,
      selectedColor: AppColorScheme.primaryContainerDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    ),
    
    navigationBarTheme: lightTheme.navigationBarTheme.copyWith(
      backgroundColor: AppColorScheme.surfaceDark,
      indicatorColor: AppColorScheme.primaryContainerDark,
      indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: AppColorScheme.onPrimaryContainerDark);
        }
        return const IconThemeData(color: AppColorScheme.onSurfaceVariantDark);
      }),
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColorScheme.surfaceVariantDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      elevation: 3,
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: AppColorScheme.surfaceVariantDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      elevation: 3,
      titleTextStyle: const TextStyle(
        fontSize: 24, 
        fontWeight: FontWeight.w700,
        color: AppColorScheme.onSurfaceDark,
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

  // WorkManager 및 권한 초기화는 앱 UI 진입 후 처리

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
          home: const StartupScreen(),
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
