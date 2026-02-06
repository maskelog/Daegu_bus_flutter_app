import 'package:flutter/material.dart';

/// Android 16 Live Update 스타일 진행 바
/// 
/// 특징:
/// - 진행 바 위에서 아이콘이 이동
/// - 색상 세그먼트 (진행/미진행)
/// - 출발/도착 포인트 마커
class Android16ProgressBar extends StatelessWidget {
  final int currentMinutes; // 현재 도착 시간 (분)
  final int maxMinutes; // 최대 시간 (분)
  final Color progressColor; // 진행 색상
  final Color remainingColor; // 남은 색상
  final Color startPointColor; // 시작점 색상
  final Color endPointColor; // 종료점 색상
  final IconData trackerIcon; // 트래커 아이콘
  final double height; // 진행 바 높이
  final bool showLabels; // 레이블 표시 여부

  const Android16ProgressBar({
    super.key,
    required this.currentMinutes,
    this.maxMinutes = 30,
    this.progressColor = const Color(0xFF1565C0),
    this.remainingColor = const Color(0xFFE0E0E0),
    this.startPointColor = const Color(0xFF4CAF50),
    this.endPointColor = const Color(0xFFFF5722),
    this.trackerIcon = Icons.directions_bus_rounded,
    this.height = 12,
    this.showLabels = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 진행률 계산 (0.0 ~ 1.0)
    final progress = currentMinutes.clamp(0, maxMinutes) / maxMinutes;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 진행 바와 트래커
        SizedBox(
          height: height + 24, // 트래커 아이콘 공간 포함
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // 진행 바 배경
              Positioned(
                left: 8,
                right: 8,
                top: 12, // 트래커 아이콘의 중앙에 위치하도록
                child: Container(
                  height: height,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(height / 2),
                    color: remainingColor.withAlpha(77),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(height / 2),
                    child: Row(
                      children: [
                        // 진행된 구간
                        Expanded(
                          flex: (progress * 100).toInt(),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  progressColor,
                                  progressColor.withAlpha(204),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // 남은 구간
                        Expanded(
                          flex: ((1 - progress) * 100).toInt(),
                          child: Container(
                            color: remainingColor.withAlpha(77),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              
              // 시작점 마커
              Positioned(
                left: 0,
                top: 12 + (height / 2) - 5, // 진행 바 중앙
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: startPointColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colorScheme.surface,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: startPointColor.withAlpha(102),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),

              // 도착점 마커
              Positioned(
                right: 0,
                top: 12 + (height / 2) - 5, // 진행 바 중앙
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: endPointColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colorScheme.surface,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: endPointColor.withAlpha(102),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              
              // 트래커 아이콘 (버스 아이콘이 진행 바 위에서 이동)
              Positioned(
                left: 8 + (MediaQuery.of(context).size.width - 32 - 32) * progress - 12, // 진행에 따라 위치 계산
                top: 0,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 600),
                  curve: Curves.easeOutBack,
                  builder: (context, value, child) {
                    return Transform.scale(
                      scale: 0.8 + (0.2 * value),
                      child: child,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: colorScheme.surface,
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withAlpha(128),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(
                      trackerIcon,
                      color: colorScheme.onPrimary,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        
        // 레이블 (선택적)
        if (showLabels)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '출발',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: startPointColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                  ),
                ),
                Text(
                  '$currentMinutes분 / $maxMinutes분',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                    fontSize: 10,
                  ),
                ),
                Text(
                  '도착',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: endPointColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 컴팩트 버전의 Android 16 스타일 진행 바
class CompactAndroid16ProgressBar extends StatelessWidget {
  final int currentMinutes;
  final int maxMinutes;
  final Color progressColor;
  final double height;

  const CompactAndroid16ProgressBar({
    super.key,
    required this.currentMinutes,
    this.maxMinutes = 30,
    required this.progressColor,
    this.height = 6,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final progress = currentMinutes.clamp(0, maxMinutes) / maxMinutes;

    return SizedBox(
      height: height + 16,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 진행 바
          Positioned(
            left: 6,
            right: 6,
            top: 8,
            child: Container(
              height: height,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(height / 2),
                color: colorScheme.surfaceContainerHighest,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(height / 2),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          progressColor,
                          progressColor.withAlpha(179),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 작은 트래커
          Positioned(
            left: 6 + (MediaQuery.of(context).size.width - 32 - 24) * progress - 6,
            top: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: progressColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: colorScheme.surface,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: progressColor.withAlpha(102),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
