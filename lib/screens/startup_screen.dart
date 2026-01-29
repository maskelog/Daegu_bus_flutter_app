import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/permission_service.dart';
import 'home_screen.dart';

class StartupScreen extends StatefulWidget {
  const StartupScreen({super.key});

  @override
  State<StartupScreen> createState() => _StartupScreenState();
}

class _StartupScreenState extends State<StartupScreen> {
  bool _isRequesting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkAndProceed();
  }

  Future<void> _checkAndProceed() async {
    if (!mounted) return;
    final granted = await _hasCorePermissions();
    if (granted && mounted) {
      _goHome();
    }
  }

  Future<bool> _hasCorePermissions() async {
    final location = await Permission.locationWhenInUse.isGranted;
    final notification = await Permission.notification.isGranted;
    return location && notification;
  }

  Future<void> _requestPermissions() async {
    setState(() {
      _isRequesting = true;
      _errorMessage = null;
    });
    try {
      await PermissionService.requestAllPermissions();
      final granted = await _hasCorePermissions();
      if (granted && mounted) {
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
    final theme = Theme.of(context);
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
                _PermissionItem(
                  icon: Icons.my_location_rounded,
                  title: '위치 권한',
                  subtitle: '주변 정류장 및 지도 기능',
                ),
                const SizedBox(height: 8),
                _PermissionItem(
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
                  onPressed: _isRequesting ? null : _goHome,
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
