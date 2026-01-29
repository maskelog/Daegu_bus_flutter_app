import 'package:flutter/material.dart';

class HomeSearchBar extends StatelessWidget {
  final VoidCallback onSearchTap;
  final VoidCallback onSettingsTap;
  final String hintText;

  const HomeSearchBar({
    super.key,
    required this.onSearchTap,
    required this.onSettingsTap,
    required this.hintText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        Expanded(
          child: Semantics(
            label: hintText,
            hint: '탭하여 검색 화면으로 이동합니다',
            child: GestureDetector(
              onTap: onSearchTap,
              child: Container(
                height: 64, // Increased height for a bolder look
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      colorScheme.surfaceContainer,
                      colorScheme.surfaceContainerHigh,
                    ],
                  ),
                  borderRadius:
                      BorderRadius.circular(32), // Pill shape
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.shadow.withOpacity(0.1),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search_rounded,
                        color: colorScheme.primary,
                        size: 30, // Larger icon
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          hintText,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.bold,
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
        const SizedBox(width: 8),
        Semantics(
          label: '설정',
          hint: '설정화면으로 이동',
          child: FilledButton(
            onPressed: onSettingsTap,
            style: FilledButton.styleFrom(
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(16),
              backgroundColor: colorScheme.surfaceContainer,
            ),
            child: Icon(Icons.settings_rounded,
                color: colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
