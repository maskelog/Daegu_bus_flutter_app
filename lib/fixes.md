# Bus App TTS 수정사항

이 문서는 버스 앱의 TTS(Text-to-Speech) 관련 오류를 수정하기 위한 지침입니다.

## 문제 진단

로그 분석 결과 다음과 같은 문제가 발견되었습니다:

1. `RangeError (end): Invalid value: Not in inclusive range 13..24: 28` 오류 발생
2. TTS 발화가 부분적으로만 동작하고 전체 메시지가 발화되지 않음
3. 이어폰 모드와 일반 모드의 TTS 시스템이 충돌하는 문제

## 해결방안

1. `SimpleTTSHelper`와 `TTSSwitcher` 클래스를 생성하여 안전한 TTS 발화를 보장합니다.
2. 기존 `TTSHelper` 대신 새로운 클래스를 사용하도록 코드를 수정합니다.
3. 메시지를 적절하게 분리하여 발화 오류를 방지합니다.

## 수정 적용 방법

1. 파일 수정:
   - `bus_card.dart`와 `compact_bus_card.dart`에서 TTSHelper 참조를 TTSSwitcher로 변경
   - 색상 수정: 승차 알람 활성화 시 버튼 색상이 노란색으로 변경되도록 수정
   - active_alarm_panel에 알람이 제대로 표시되도록 수정

2. `simple_tts_helper.dart` 및 `tts_switcher.dart` 파일 생성됨:
   - 간단한 TTS 발화 기능 제공
   - 네이티브 채널과 Flutter TTS 둘 다 시도하여 안정성 향상
   - 메시지를 작은 단위로 분할하여 발화 오류 방지

## 다음 단계

1. 이 변경사항이 적용된 앱을 테스트하여 TTS 발화가 정상적으로 동작하는지 확인
2. 문제가 해결되지 않으면 추가 디버깅을 통해 정확한 원인 파악 필요

## 주의사항

이 솔루션은 임시적인 것으로, 장기적으로는 네이티브 TTS 시스템의 근본적인 문제를 해결하는 것이 바람직합니다. 특히 문자열 처리 부분과 이어폰 출력 관련 부분을 개선할 필요가 있습니다.
