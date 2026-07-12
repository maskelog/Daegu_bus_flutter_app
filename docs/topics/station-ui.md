# 정류장 UI

> 이 문서는 **현재 상태**를 서술한다. 변경 이력은 [devlog.md](../devlog.md)를 참조한다.
> 마지막 갱신: 2026-07-12

## 정류장 번호 배지

- 검색 결과와 홈의 선택된 정류장 카드에서 `StationNumberBadge`를 사용한다.
- 밝은 테마에서는 `primaryContainer` 배경과 `onPrimaryContainer` 글자를 사용해 번호를 선명하게 보이게 한다.
- 어두운 테마에서는 `surfaceContainerHighest` 배경과 `onSurface` 글자를 사용해 정류장 번호 대비를 높인다.
- 배지 테두리는 테마에 따라 `outlineVariant` 또는 `primary` 계열을 사용해 카드 배경과 분리된다.
- 정류장 번호는 단순 텍스트가 아니라 둥근 배지로 표시해 다크모드에서도 읽기 쉽게 유지한다.

## 구현 위치

- `lib/widgets/station_number_badge.dart`
- `lib/widgets/station_item.dart`
- `lib/screens/home_widgets.dart`
