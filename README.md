# 대구 버스

대구버스 앱이며 Flutter와 Android 16 의 live updates 기능을 활용한 알림 시스템을 탑재했습니다. 
버스 api는 대구광역시 버스정보시스템을 파싱하여 사용합니다.
https://github.com/maskelog/Daegu_bus_api

<div align="center">
  <table>
    <tr>
      <td align="center">
        <img src="https://private-user-images.githubusercontent.com/30742914/544216443-88e04342-bd09-4721-9bcc-30946878e226.jpg?jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbSIsImtleSI6ImtleTUiLCJleHAiOjE3NzAxMDcwNjQsIm5iZiI6MTc3MDEwNjc2NCwicGF0aCI6Ii8zMDc0MjkxNC81NDQyMTY0NDMtODhlMDQzNDItYmQwOS00NzIxLTliY2MtMzA5NDY4NzhlMjI2LmpwZz9YLUFtei1BbGdvcml0aG09QVdTNC1ITUFDLVNIQTI1NiZYLUFtei1DcmVkZW50aWFsPUFLSUFWQ09EWUxTQTUzUFFLNFpBJTJGMjAyNjAyMDMlMkZ1cy1lYXN0LTElMkZzMyUyRmF3czRfcmVxdWVzdCZYLUFtei1EYXRlPTIwMjYwMjAzVDA4MTkyNFomWC1BbXotRXhwaXJlcz0zMDAmWC1BbXotU2lnbmF0dXJlPTBlOTBlMmNhOWU1NWI1NTFkNGIyN2RmNjIxOTE1NDkyZDk5ZjZlOGZhMzM2YmU0MzAzNWRhOTA2ZGEwODQ5YTUmWC1BbXotU2lnbmVkSGVhZGVycz1ob3N0In0.QQv4wV5AwoSW8G3a1yFeatKT9TSJTUK3uVhh4Z3oilo" width="300" alt="홈 화면"/>
        <br/><b>홈 화면</b>
      </td>
      <td align="center">
        <img src="https://private-user-images.githubusercontent.com/30742914/544216441-1f7073e6-86ea-4a52-a6fc-64d2b7c79a31.jpg?jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbSIsImtleSI6ImtleTUiLCJleHAiOjE3NzAxMDcwNjQsIm5iZiI6MTc3MDEwNjc2NCwicGF0aCI6Ii8zMDc0MjkxNC81NDQyMTY0NDEtMWY3MDczZTYtODZlYS00YTUyLWE2ZmMtNjRkMmI3Yzc5YTMxLmpwZz9YLUFtei1BbGdvcml0aG09QVdTNC1ITUFDLVNIQTI1NiZYLUFtei1DcmVkZW50aWFsPUFLSUFWQ09EWUxTQTUzUFFLNFpBJTJGMjAyNjAyMDMlMkZ1cy1lYXN0LTElMkZzMyUyRmF3czRfcmVxdWVzdCZYLUFtei1EYXRlPTIwMjYwMjAzVDA4MTkyNFomWC1BbXotRXhwaXJlcz0zMDAmWC1BbXotU2lnbmF0dXJlPTczNzNmMjU4Mjk2MWNmY2E3NGIwNTIxMGUwY2UzYWRkYjYzMjlmMDNhMjI0ZWRiYWVmMjVhMWQ3YmMxOTA3NDQmWC1BbXotU2lnbmVkSGVhZGVycz1ob3N0In0.uFY1Gt6xaGKJy-8_AZ8NZ6BtrWBsDl2h7_37cnheYNI" width="300" alt="정류장 상세"/>
        <br/><b>정류장 상세</b>
      </td>
    </tr>
  </table>
</div>

---

## ✨ 주요 기능

### 1. 실시간 버스 도착 정보
- 특정 정류장의 버스 도착 정보를 실시간으로 확인하고, 버스의 현재 위치를 추적할 수 있습니다.
- 홈 화면에서 자주 찾는 버스를 등록하고 빠르게 도착 정보를 확인할 수 있습니다.

### 2. 강력한 승차 알람
- 놓치고 싶지 않은 버스에 **승차 알람**을 설정하여 버스가 도착하기 전에 미리 알림을 받을 수 있습니다.
- 이어폰/헤드폰을 연결했을 때만 소리가 나는 **이어폰 전용 TTS 알람**을 지원하여 공공장소에서도 편리하게 사용할 수 있습니다.

### 3. Android 16 Live Updates (실시간 업데이트 알림)지원
- Android 16 기기에서 버스 알람 설정 시, 알림 센터와 잠금 화면에 **실시간 진행률 알림**이 표시됩니다.
- 버스 아이콘이 진행 바 위에서 실시간으로 이동하여, 남은 정류장과 도착 예정 시간을 한눈에 파악할 수 있습니다.

![Live Update Notification](https://private-user-images.githubusercontent.com/30742914/544216444-022298c3-79eb-4c29-b797-5bec291a9eb3.jpg?jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbSIsImtleSI6ImtleTUiLCJleHAiOjE3NzAxMDcwNjQsIm5iZiI6MTc3MDEwNjc2NCwicGF0aCI6Ii8zMDc0MjkxNC81NDQyMTY0NDQtMDIyMjk4YzMtNzllYi00YzI5LWI3OTctNWJlYzI5MWE5ZWIzLmpwZz9YLUFtei1BbGdvcml0aG09QVdTNC1ITUFDLVNIQTI1NiZYLUFtei1DcmVkZW50aWFsPUFLSUFWQ09EWUxTQTUzUFFLNFpBJTJGMjAyNjAyMDMlMkZ1cy1lYXN0LTElMkZzMyUyRmF3czRfcmVxdWVzdCZYLUFtei1EYXRlPTIwMjYwMjAzVDA4MTkyNFomWC1BbXotRXhwaXJlcz0zMDAmWC1BbXotU2lnbmF0dXJlPWM1MmRjM2E4MjI4ZTYyZDgxYzJmYzZlNWQ1ZjY2ZDEzYzhiZDQ3N2Q3ZGFkMmYzN2RhYjQwMmU0NTE4YmQ3MWMmWC1BbXotU2lnbmVkSGVhZGVycz1ob3N0In0.tPWNnGbg4FHqOo1e6E5Gaf0bjsOd4NYFUwsXdR382Ko)

### 4. 즐겨찾기
- 자주 이용하는 버스를 정류장과 함께 **즐겨찾기**에 추가하여 빠르게 정보를 확인할 수 있습니다.
- 홈 화면과 상세 정보 화면에서 간편하게 즐겨찾기를 추가하거나 해제할 수 있습니다.

### 5. 아름답고 직관적인 Material 3 UI/UX
- 최신 **Material 3** 디자인 가이드라인을 적용하여 시각적으로 아름답고 일관된 사용자 경험을 제공합니다.
- 부드러운 **애니메이션**과 **햅틱 피드백**을 통해 앱 사용의 즐거움을 더했습니다.
- 정보의 중요도에 따라 색상과 아이콘을 활용하여(도착 임박, 운행 종료 등) 뛰어난 시인성을 제공합니다.

---

## 🛠️ 기술 스택

- **Cross-Platform Framework**: [Flutter](https://flutter.dev/)
- **UI Design**: [Material 3](https://m3.material.io/)
- **State Management**: [Provider](https://pub.dev/packages/provider)
- **Asynchronous Programming**: `Future`, `Stream`, `async/await`
- **Local Storage**: `shared_preferences`, `sqflite`
- **Native Integration**:
  - `MethodChannel`을 이용한 Kotlin/Swift 네이티브 연동
  - Android 16 Live Updates API (Reflection)
  - `Notification.ProgressStyle`을 사용한 진행률 알림 구현
- **API Communication**: `dio`

---

## 📝 개발 기록

자세한 개발 과정과 구현 내용은 [GEMINI.md](GEMINI.md) 파일에서 확인할 수 있습니다.