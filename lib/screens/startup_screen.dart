import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/permission_service.dart';
import 'home_screen.dart';

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen>
    with WidgetsBindingObserver {
  bool _isRequesting = false;
  bool _isLoadingPermissions = true; // 권한 로딩 상태 추가
  String? _errorMessage;
  bool _shouldShowScreen = true; // 화면 표시 여부
  static const String _permissionsGrantedKey = 'permissions_granted_once';
  bool _promotedNotificationsEnabled = true;
  bool _batteryOptimizationEnabled = true;
  bool _waitingForBatteryOptimization = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAndProceed();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _handleResume();
    }
  }

  Future<void> _checkAndProceed() async {
    setState(() {
      _isLoadingPermissions = true;
      _errorMessage = null;
    });

    bool granted;
    try {
      granted = await _hasCorePermissions();
      _promotedNotificationsEnabled =
          await PermissionService.canPostPromotedNotifications();
      _batteryOptimizationEnabled =
          await PermissionService.isIgnoringBatteryOptimizations();
    } catch (e) {
      granted = false;
      if (mounted) {
        setState(() {
          _errorMessage = '권한 상태 확인 실패로 기본값(미허용) 모드로 진입합니다.';
        });
      }
    }

    // 권한이 이미 모두 허용되어 있으면 바로 홈으로 이동
    if (granted && mounted) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_permissionsGrantedKey, true);
      if (mounted) {
        setState(() {
          _shouldShowScreen = false;
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _goHome();
      });
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingPermissions = false;
      });
    }
  }

  Future<bool> _hasCorePermissions() async {
    // 위치 권한 확인
    final location = await Permission.locationWhenInUse.isGranted;
    
    // 알림 권한 확인 (Android 13 이상만 체크)
    bool notificationGranted = true;
    if (Platform.isAndroid) {
      try {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        final sdkVersion = androidInfo.version.sdkInt;
        if (sdkVersion >= 33) {
          // Android 13 이상만 알림 권한 체크
          notificationGranted = await Permission.notification.isGranted;
        }
        // Android 12 이하는 알림 권한이 자동으로 허용되므로 true로 간주
      } catch (e) {
        // 오류 발생 시 기본값 사용
        notificationGranted = true;
      }
    }
    
    return location && notificationGranted;
  }

  Future<void> _requestPermissions() async {
    if (!mounted) return;
    setState(() {
      _isRequesting = true;
      _errorMessage = null;
    });
    try {
      await PermissionService.requestNotificationPermission();
      await PermissionService.requestPromotedNotificationPermission();
      await PermissionService.requestLocationPermission();
      await PermissionService.requestExactAlarmPermission();

      final grantedBeforeBattery = await _hasCorePermissions();
      if (grantedBeforeBattery && !_batteryOptimizationEnabled) {
        _waitingForBatteryOptimization = true;
        await PermissionService.requestIgnoreBatteryOptimizations();
      }

      await PermissionService.checkAutoStartPermission();

      final granted = await _hasCorePermissions();
      final promotedEnabled =
          await PermissionService.canPostPromotedNotifications();
      final batteryOptimizationEnabled =
          await PermissionService.isIgnoringBatteryOptimizations();
      _promotedNotificationsEnabled = promotedEnabled;
      _batteryOptimizationEnabled = batteryOptimizationEnabled;
      if (granted && batteryOptimizationEnabled && mounted) {
        // 권한이 허용되었음을 저장
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_permissionsGrantedKey, true);
        if (mounted) {
          setState(() {});
        }
        _goHome();
      } else if (mounted) {
        setState(() {
          _errorMessage = batteryOptimizationEnabled
              ? '일부 권한이 허용되지 않아 기능이 제한될 수 있습니다.'
              : '배터리 사용량 제한 없음을 설정하면 자동알람이 더 안정적으로 동작합니다.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '권한 요청 중 오류가 발생했습니다.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isRequesting = false);
      }
    }
  }

  Future<void> _handleResume() async {
    if (!_waitingForBatteryOptimization || !mounted) return;

    final granted = await _hasCorePermissions();
    final batteryOptimizationEnabled =
        await PermissionService.isIgnoringBatteryOptimizations();
    if (!mounted) return;

    setState(() {
      _batteryOptimizationEnabled = batteryOptimizationEnabled;
      if (batteryOptimizationEnabled) {
        _waitingForBatteryOptimization = false;
        _errorMessage = null;
      }
    });

    if (granted && batteryOptimizationEnabled) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_permissionsGrantedKey, true);
      if (mounted) {
        _goHome();
      }
    }
  }

  Future<void> _handlePermissionRequestTap() async {
    if (_isRequesting) return;

    final shouldProceed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            final theme = Theme.of(dialogContext);
            return AlertDialog(
              title: const Text('권한 요청 안내'),
              content: Text(
                '위치 권한은 주변 정류장과 지도 기능에 사용되고, 알림 권한은 도착 알림과 자동 알람에 사용됩니다.\n\n'
                '배터리 사용량 제한 없음 설정은 자동알람이 백그라운드에서도 끊기지 않도록 유지하는 데 사용됩니다.\n\n'
                '안내를 확인한 뒤 다음 단계에서 Android 권한 팝업이 순서대로 표시됩니다.',
                style: theme.textTheme.bodyMedium,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('계속'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!shouldProceed || !mounted) return;
    await _requestPermissions();
  }

  void _goHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 권한이 이미 허용되어 있으면 화면을 렌더링하지 않고 빈 위젯 반환
    // (실제로는 _goHome()이 호출되어 화면이 전환됨)
    // 이 체크는 main.dart에서 이미 권한을 확인했지만, 혹시 모를 경우를 대비한 이중 체크
    if (!_shouldShowScreen) {
      // 빈 위젯 반환 (화면이 보이지 않음)
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    
    // 권한 로딩 중일 경우 로딩 스피너 표시
    if (_isLoadingPermissions) {
      return Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: Center(
          child: CircularProgressIndicator(
            color: theme.colorScheme.primary,
          ),
        ),
      );
    }
    
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.directions_bus_rounded,
                    size: 36,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  '대구버스 이용을 위해 권한이 필요합니다',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  '현재 위치 기반 정류장 검색과\n알림 제공을 위해 권한을 허용해주세요.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                const _PermissionItem(
                  icon: Icons.my_location_rounded,
                  title: '위치 권한',
                  subtitle: '주변 정류장 및 지도 기능',
                ),
                const SizedBox(height: 8),
                const _PermissionItem(
                  icon: Icons.notifications_active_rounded,
                  title: '알림 권한',
                  subtitle: '도착 알림 및 자동 알람',
                ),
                if (Platform.isAndroid) ...[
                  const SizedBox(height: 8),
                  _PermissionItem(
                    icon: Icons.battery_saver_rounded,
                    title: '배터리 사용량 제한 없음',
                    subtitle: _batteryOptimizationEnabled
                        ? '활성화됨 - 자동알람이 백그라운드에서도 유지됨'
                        : '자동알람이 백그라운드에서도 유지되도록 사용',
                  ),
                ],
                if (Platform.isAndroid) ...[
                  const SizedBox(height: 8),
                  _PermissionItem(
                    icon: Icons.update_rounded,
                    title: '실시간 정보',
                    subtitle: _promotedNotificationsEnabled
                        ? 'Live Updates 및 상태칩 표시 사용 가능'
                        : 'Android 16 이상에서 상태바/Now Bar 표시',
                  ),
                ],
                const SizedBox(height: 20),
                if (_errorMessage != null) ...[
                  Text(
                    _errorMessage!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                ],
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed:
                        _isRequesting ? null : _handlePermissionRequestTap,
                    child: _isRequesting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('권한 허용하기'),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _isRequesting ? null : () async {
                    // "나중에 하기"를 눌러도 권한 상태 저장 (다음 번에 다시 확인)
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool(_permissionsGrantedKey, false);
                    _goHome();
                  },
                  child: const Text('나중에 하기'),
                ),
                if (Platform.isAndroid && !_promotedNotificationsEnabled) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _isRequesting
                        ? null
                        : () async {
                            await PermissionService
                                .requestPromotedNotificationPermission();
                            if (!mounted) return;
                            final enabled = await PermissionService
                                .canPostPromotedNotifications();
                            setState(() {
                              _promotedNotificationsEnabled = enabled;
                            });
                          },
                    child: const Text('실시간 정보 설정 열기'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PermissionItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _PermissionItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
