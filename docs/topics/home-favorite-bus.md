# 홈 즐겨찾기 버스

> 이 문서는 **현재 상태**를 서술한다. 변경 이력은 [devlog.md](../devlog.md)를 참조한다.
> 마지막 갱신: 2026-07-12

## 즐겨찾기 버스 카드

- 홈의 즐겨찾기 버스 카드는 `HomeRouteItem`을 사용한다.
- 노선 칩은 `resolveRouteBranding()` 결과를 우선 사용해 배경색과 글자색을 함께 맞춘다.
- `직행`처럼 흰 배경을 쓰는 노선은 빨간 글자와 빨간 테두리로 표시해 다크모드에서도 읽기 쉽게 유지한다.
- 브랜드가 정의된 노선은 배경색과 텍스트 색을 공용 분류 규칙에 맞춘다.
- 브랜드가 없는 노선만 홈 전용 색상 함수로 폴백한다.
- 일반노선 폴백 배지는 배경 명도에 따라 검정 또는 흰색 글자를 선택해 라이트/다크모드 대비를 유지한다.

## 구현 위치

- `lib/screens/home_widgets.dart`
- `lib/screens/home_screen.dart`
- `lib/utils/route_branding.dart`
- `test/home_favorite_bus_route_branding_test.dart`
