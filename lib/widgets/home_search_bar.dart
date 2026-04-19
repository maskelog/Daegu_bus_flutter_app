import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HomeSearchBar extends StatelessWidget {
  final VoidCallback onSearchTap;
  final VoidCallback onSettingsTap;
  final VoidCallback onFavoritesEditTap;
  final String hintText;

  const HomeSearchBar({
    super.key,
    required this.onSearchTap,
    required this.onSettingsTap,
    required this.onFavoritesEditTap,
    required this.hintText,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Semantics(
          label: '메뉴',
          hint: '설정 및 즐겨찾기 편집',
          child: Container(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color.fromRGBO(0, 0, 0, 0.08),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: PopupMenuButton<String>(
              tooltip: '메뉴',
              offset: const Offset(0, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              color: colorScheme.surfaceContainerHigh,
              onSelected: (value) {
                switch (value) {
                  case 'favorites':
                    onFavoritesEditTap();
                    break;
                  case 'settings':
                    onSettingsTap();
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'favorites',
                  child: Row(
                    children: [
                      Icon(Icons.star_rounded,
                          size: 22, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 12),
                      const Text('즐겨찾기 편집'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'settings',
                  child: Row(
                    children: [
                      Icon(Icons.settings_rounded,
                          size: 22, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 12),
                      const Text('설정'),
                    ],
                  ),
                ),
              ],
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colorScheme.surfaceContainerHigh,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.menu_rounded,
                  color: colorScheme.onSurfaceVariant,
                  size: 22,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Semantics(
            label: hintText,
            hint: '탭하여 검색 화면으로 이동합니다',
            child: GestureDetector(
              onTap: onSearchTap,
              child: _HomeSearchBarShell(
                child: Row(
                  children: [
                    const _HomeSearchBarIcon(),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        hintText,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
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
      ],
    );
  }
}

/// `HomeSearchBar`와 동일한 디자인의 실제 입력 가능한 검색 필드.
class HomeSearchBarField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hintText;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;

  const HomeSearchBarField({
    super.key,
    required this.controller,
    required this.hintText,
    this.focusNode,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return _HomeSearchBarShell(
      child: Row(
        children: [
          const _HomeSearchBarIcon(),
          const SizedBox(width: 14),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: autofocus,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                    ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              maxLines: 1,
              inputFormatters: const [
                SingleLineFormatter(),
              ],
              textInputAction: TextInputAction.search,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
            ),
          ),
          if (onClear != null)
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onClear,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  Icons.clear_rounded,
                  size: 20,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SingleLineFormatter extends TextInputFormatter {
  const SingleLineFormatter();

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (!newValue.text.contains('\n')) return newValue;
    final text = newValue.text.replaceAll('\n', '');
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// 홈/검색/노선도 화면에서 공통으로 사용하는 원형 아이콘 버튼.
/// 햄버거 / 뒤로가기 / 지도 등 헤더 액션에 통일된 디자인을 제공합니다.
class HeaderCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final String? semanticLabel;
  final String? semanticHint;

  const HeaderCircleButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.semanticLabel,
    this.semanticHint,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final button = Container(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.08),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: colorScheme.surfaceContainerHigh,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 50,
            height: 50,
            child: Center(
              child: Icon(
                icon,
                color: colorScheme.onSurfaceVariant,
                size: 22,
              ),
            ),
          ),
        ),
      ),
    );
    if (semanticLabel == null) return button;
    return Semantics(label: semanticLabel, hint: semanticHint, child: button);
  }
}

/// 검색바와 동일한 pill 모양의 읽기 전용 타이틀 표시.
class HeaderTitlePill extends StatelessWidget {
  final String title;
  final IconData? leadingIcon;

  const HeaderTitlePill({
    super.key,
    required this.title,
    this.leadingIcon,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return _HomeSearchBarShell(
      child: Row(
        children: [
          if (leadingIcon != null) ...[
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                leadingIcon,
                color: colorScheme.onPrimaryContainer,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeSearchBarShell extends StatelessWidget {
  final Widget child;
  const _HomeSearchBarShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: colorScheme.outlineVariant,
          width: 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.08),
            blurRadius: 12,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: child,
      ),
    );
  }
}

class _HomeSearchBarIcon extends StatelessWidget {
  const _HomeSearchBarIcon();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        Icons.search_rounded,
        color: colorScheme.onPrimaryContainer,
        size: 22,
      ),
    );
  }
}
