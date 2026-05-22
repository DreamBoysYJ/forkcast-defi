# 시크릿 관리 — 환경변수로 분리

**관련 이슈:** C-3 (#7)  
**수정 PR:** #14  
**날짜:** 2026-05-22

---

## 문제: 하드코딩된 DB 패스워드

```yaml
# 수정 전 application.yaml
spring:
  datasource:
    username: forkcast_app
    password: 1234
```

### 왜 위험한가

1. **git history에 영구 기록** — 나중에 지워도 `git log`로 복원 가능
2. **공개 레포 = 즉시 노출** — GitHub, GitLab 스캐너가 자동 탐지
3. **환경별 분리 불가** — 개발/스테이징/프로덕션이 동일 패스워드 강제

---

## 해결: Spring Boot 환경변수 치환

```yaml
# 수정 후 application.yaml
spring:
  datasource:
    username: ${DB_USERNAME:forkcast_app}   # 미설정 시 기본값 forkcast_app
    password: ${DB_PASSWORD}                # 기본값 없음 → 미설정 시 기동 실패
```

`${VAR:default}` 문법:
- `${DB_PASSWORD}` → 환경변수 필수. 없으면 기동 실패 (의도된 안전장치)
- `${DB_USERNAME:forkcast_app}` → 없으면 기본값 사용 (username은 덜 민감)

### 실행 방법

```bash
# 로컬
DB_USERNAME=forkcast_app DB_PASSWORD=mypassword ./gradlew bootRun

# GCP / Docker
# 환경변수를 Secret Manager 또는 컨테이너 env로 주입
```

---

## 실무에서 추가로 할 것

1. **`.gitignore`에 `.env` 추가** — 로컬 환경변수 파일 커밋 방지
2. **GCP Secret Manager** — 프로덕션 시크릿 중앙 관리
3. **git-secrets / truffleHog** — pre-commit hook으로 시크릿 커밋 자동 차단
4. **패스워드 로테이션** — 이미 노출된 경우 반드시 패스워드 변경

---

## 핵심 원칙

> **"코드에 시크릿을 넣지 마라. git은 삭제해도 기억한다."**

- 설정값 ≠ 시크릿: DB host, port → yaml OK. password, API key → 환경변수
- Spring Boot `${ENV_VAR}` 치환은 yaml, properties 모두 지원
- 기본값 없는 필수 시크릿은 미설정 시 기동 실패가 더 안전 (silent fail 방지)
