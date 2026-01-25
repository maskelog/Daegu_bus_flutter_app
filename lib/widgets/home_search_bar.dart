import 'package:flutter/material.dart';

class HomeSearchBar extends StatelessWidget {
  final VoidCallback onSearchTap;
  final VoidCallback onSettingsTap;

  const HomeSearchBar({
    super.key,
    required this.onSearchTap,
    required this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Expanded(
          child: Semantics(
            label: '정류장 검색',
            hint: '정류장 이름을 입력해 검색합니다',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onSearchTap,
                borderRadius: BorderRadius.circular(32), // Very rounded for Material You
                child: Container(
                  height: 60, // Taller for prominence
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(32),
                    // No border - Material You style
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search_rounded,
                          color: colorScheme.onSurfaceVariant,
                          size: 28, // Larger icon
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Text(
                            "정류장 검색",
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 18, // Larger text
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Semantics(
          label: '설정',
          hint: '설정화면으로 이동',
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: IconButton.filledTonal(
              onPressed: onSettingsTap,
              icon: Icon(Icons.settings_outlined, color: colorScheme.onSurface, size: 26),
              tooltip: '설정',
              style: IconButton.styleFrom(
                backgroundColor: colorScheme.surfaceContainerHighest,
                padding: const EdgeInsets.all(16),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
