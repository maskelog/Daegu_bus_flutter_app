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

class _StartupScreenState extends State<StartupScreen> {
  bool _isRequesting = false;
  bool _isLoadingPermissions = true; // 권한 로딩 상태 추가
  String? _errorMessage;
  bool _shouldShowScreen = true; // 화면 표시 여부
  static const String _permissionsGrantedKey = 'permissions_granted_once';

  @override
  void initState() {
    super.initState();
    _checkAndProceed();
  }

  Future<void> _checkAndProceed() async {
    // 먼저 현재 권한 상태를 즉시 확인
    final granted = await _hasCorePermissions();
    
    // 권한이 이미 모두 허용되어 있으면 즉시 홈으로 이동 (화면 렌더링 없이)
    if (granted && mounted) {
      // 권한이 허용되었음을 저장
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_permissionsGrantedKey, true);
      
      // 화면을 렌더링하지 않고 바로 홈으로 이동
      setState(() {
        _shouldShowScreen = false;
      });
      
      // 다음 프레임에서 홈으로 이동 (화면이 렌더링되기 전에)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _goHome();
        }
      });
      return;
    }

    // 권한이 없거나 일부만 허용된 경우에만 UI 표시
    if (mounted) {
      setState(() {
        _isLoadingPermissions = true;
      });
    }

    // 약간의 지연 후 권한 상태를 다시 확인 (사용자가 설정에서 권한을 변경했을 수 있음)
    await Future.delayed(const Duration(milliseconds: 100));
    final grantedAfterDelay = await _hasCorePermissions();

    // 권한 확인 완료 후 _isLoadingPermissions를 false로 설정
    if (mounted) {
      setState(() {
        _isLoadingPermissions = false;
      });
    }

    // 권한이 모두 허용되어 있으면 바로 홈으로 이동
    if (grantedAfterDelay && mounted) {
      // 권한이 허용되었음을 저장
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_permissionsGrantedKey, true);
      // 즉시 홈으로 이동 (지연 없이)
      _goHome();
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
      await PermissionService.requestAllPermissions();
      final granted = await _hasCorePermissions();
      if (granted && mounted) {
        // 권한이 허용되었음을 저장
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(_permissionsGrantedKey, true);
        _goHome();
      } else if (mounted) {
        setState(() {
          _errorMessage = '일부 권한이 허용되지 않아 기능이 제한될 수 있습니다.';
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
                    onPressed: _isRequesting ? null : _requestPermissions,
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
