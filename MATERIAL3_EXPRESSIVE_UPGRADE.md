# Material 3 Expressive 디자인 업그레이드

## 개요
대구 버스 앱을 Google의 최신 Material 3 Expressive 디자인 시스템으로 업그레이드했습니다.

## 주요 변경사항

### 1. **더 큰 Border Radius (16px → 28px)**
Material 3 Expressive의 핵심 특징인 더 둥근 모서리를 적용했습니다.

#### 적용된 컴포넌트:
- ✅ Card (모든 카드 컴포넌트)
- ✅ Button (ElevatedButton, FilledButton)
- ✅ Input Fields (검색바, 입력 필드)
- ✅ FloatingActionButton
- ✅ Chip
- ✅ Dialog
- ✅ BottomSheet
- ✅ NavigationBar Indicator

### 2. **향상된 타이포그래피**
더 크고 대담한 텍스트 스타일로 가독성과 시각적 계층 구조 개선

#### 변경사항:
- **Display Large**: 57px → 64px (FontWeight.w900)
- **Display Medium**: 45px → 52px (FontWeight.w800)
- **Display Small**: 36px → 40px (FontWeight.w700)
- **Title Large**: 22px → 24px (FontWeight.w700)
- **Title Medium**: 16px → 18px
- **Body Large**: 16px → 17px
- **Label Large**: 14px → 16px (FontWeight.w700)

### 3. **개선된 Elevation과 그림자**
더 많은 깊이감을 위한 elevation 효과 추가

#### 변경사항:
- **Card elevation**: 0 → 1 (라이트 모드), 2 (다크 모드)
- **FAB elevation**: 기본 → 3, 활성 시 6
- **Dialog elevation**: 3
- **BottomSheet elevation**: 3
- **그림자색 적용**: `Colors.black.withOpacity(0.05)` (라이트), `0.4` (다크)

### 4. **더 큰 터치 영역**
더 나은 접근성을 위한 padding 증가

#### 예시:
- **Button padding**: `16x16` → `32x20`
- **Input padding**: `20x16` → `24x20`
- **Card padding**: `16` → `20`
- **Search Bar height**: `52` → `56`

### 5. **확장된 FAB 지원**
Extended Floating Action Button 스타일 정의

```dart
floatingActionButtonTheme: FloatingActionButtonThemeData(
  elevation: 3,
  highlightElevation: 6,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
  extendedPadding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
  extendedTextStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
)
```

### 6. **더 두꺼운 Focus Border**
포커스 상태 시각적 강조 강화

- Input Focus Border: `1.5px` → `2.5px`

### 7. **향상된 색상 대비**
더 vibrant한 색상과 더 부드러운 outline 사용

#### 변경사항:
- **Outline opacity**: `0.5` → `0.3`
- **Surface Container opacity**: `0.5` → `0.7`

## 파일별 변경사항

### `lib/main.dart`
- ✅ AppTheme.lightTheme: Material 3 Expressive 테마 적용
- ✅ AppTheme.darkTheme: 다크 모드 Material 3 Expressive 적용
- ✅ 모든 컴포넌트 테마(Card, Button, Input, FAB, Chip, Navigation, Dialog, BottomSheet) 업데이트

### `lib/screens/home_screen.dart`
- ✅ 즐겨찾기 버스 카드: border-radius 28px
- ✅ 정류장 섹션 카드: border-radius 24px
- ✅ 주변 정류장 칩: border-radius 24px
- ✅ 메인 정류장 카드: border-radius 28px
- ✅ 액션 버튼: border-radius 24px, 아이콘 크기 24px

### `lib/widgets/bus_card.dart`
- ✅ 버스 카드: border-radius 28px
- ✅ 승차 완료 버튼: border-radius 28px
- ✅ Padding 증가 (16 → 20)
- ✅ Elevation 추가 (0 → 1)

### `lib/widgets/home_search_bar.dart`
- ✅ 검색바: border-radius 28px
- ✅ Height: 52px → 56px
- ✅ Icon size: 24px → 26px
- ✅ Font size: 16px → 17px
- ✅ Padding 증가

## 디자인 원칙

### Material 3 Expressive의 핵심 원칙:
1. **표현력 강화**: 더 크고 대담한 디자인 요소
2. **개선된 접근성**: 더 큰 터치 영역과 명확한 시각적 계층
3. **일관성**: 모든 컴포넌트에 28px border-radius 통일
4. **깊이감**: 적절한 elevation과 그림자 사용
5. **유동성**: 부드러운 곡선과 둥근 모서리

## Before & After

### Border Radius
- **Before**: 12px - 20px (혼재)
- **After**: 28px (일관적으로 적용)

### Typography
- **Before**: 표준 Material 3 크기
- **After**: Material 3 Expressive - 더 크고 더 대담함

### Elevation
- **Before**: 주로 평평한 디자인 (elevation 0-1)
- **After**: 적절한 깊이 (elevation 1-3, 상황에 따라 6)

### Padding & Spacing
- **Before**: 12px - 16px
- **After**: 16px - 24px (더 여유로운 공간)

## 향후 개선 사항

### 애니메이션 (Material 3 Expressive의 중요 요소)
현재 구현에서는 정적 디자인만 업데이트했습니다. 향후 추가할 애니메이션:

1. **페이지 전환**: Hero 애니메이션과 shared element transitions
2. **버튼 상호작용**: Ripple 효과와 press 애니메이션
3. **카드 확장**: Expand/Collapse 애니메이션
4. **로딩 상태**: Skeleton screens과 shimmer effects

### 다이나믹 컬러
Material 3의 Dynamic Color 시스템 통합 고려

### Adaptive Layouts
다양한 화면 크기에 대응하는 adaptive layouts

## 테스트 체크리스트

- [ ] 라이트 모드 UI 확인
- [ ] 다크 모드 UI 확인
- [ ] 모든 카드 컴포넌트의 border-radius 확인
- [ ] 버튼 크기와 터치 영역 확인
- [ ] 타이포그래피 크기 확인
- [ ] Elevation과 그림자 효과 확인
- [ ] 다양한 화면 크기에서 테스트
- [ ] 접근성 기능 테스트

## 참고 자료

- [Material 3 Design Kit](https://www.figma.com/community/file/1035203688168086460)
- [Material 3 Guidelines](https://m3.material.io/)
- [Flutter Material 3 Support](https://docs.flutter.dev/ui/design/material)
