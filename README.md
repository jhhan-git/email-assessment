# 업무용 이메일 작성 수행평가

실제 메일 계정 없이 학생들이 **보내는 사람 / 받는 사람 / 참조 / 숨은 참조 / 제목 / 본문 / 서명 / 첨부파일**을 작성해 제출하는 연습용 메일 작성 화면입니다.
제출물은 Supabase에 저장되고, 선생님은 교사용 페이지에서 확인합니다.

| 페이지 | 주소 | 용도 |
|---|---|---|
| 학생용 | `https://<깃허브아이디>.github.io/<저장소이름>/` | 메일 작성·제출 |
| 교사용 | `https://<깃허브아이디>.github.io/<저장소이름>/teacher.html` | 제출물 열람, 첨부파일 내려받기, CSV 내려받기, 인쇄 |

## 파일 구성

```
index.html          학생용 작성 화면
teacher.html        교사용 확인 화면 (로그인 필요)
config.js           ★ Supabase 주소·키 입력 (여기만 수정)
style.css           디자인
vendor/             Supabase 라이브러리 (학교망에서 CDN이 막혀도 동작하도록 포함)
supabase/setup.sql  DB·저장소·권한 설정 (최초 1회 실행)
supabase/open-close.sql  제출 마감/재개용
```

---

## 1단계. Supabase 준비 (약 10분)

1. <https://supabase.com> 가입 → **New project** 생성 (지역은 `Northeast Asia (Seoul)` 권장, DB 비밀번호는 아무거나 기억해 두기).
2. **선생님 로그인 계정 만들기**
   왼쪽 메뉴 **Authentication → Users → Add user → Create new user**
   - 이메일·비밀번호 입력, **Auto Confirm User** 체크 → 생성
3. **DB 설정**
   `supabase/setup.sql` 파일을 열어 맨 아래 `teacher@example.com`을 **2번에서 만든 이메일로 바꾼 뒤**,
   왼쪽 메뉴 **SQL Editor → New query** 에 전체를 붙여넣고 **Run**.
   (다른 선생님도 함께 보려면 2번처럼 계정을 만들고 아래 SQL을 실행)
   ```sql
   insert into public.teachers (email) values ('다른선생님@school.kr');
   ```
4. **(권장) 회원가입 막기**
   **Authentication → Sign In / Providers** 에서 **Allow new users to sign up** 끄기.
5. **주소와 키 복사**
   **Project Settings → API (또는 API Keys)** 에서
   - Project URL (`https://xxxx.supabase.co`)
   - `anon` `public` 키 (또는 `sb_publishable_...` 로 시작하는 Publishable key)

   를 `config.js`에 붙여넣습니다.
   ```js
   SUPABASE_URL: "https://xxxx.supabase.co",
   SUPABASE_ANON_KEY: "eyJhbGciOi...",
   ```
   > 이 키는 웹페이지에 공개되어도 되는 키입니다. 학생은 **제출만** 할 수 있고, 다른 학생 글을 읽을 수 없도록 setup.sql에서 권한을 막아 두었습니다.
   > `service_role` / `secret` 키는 **절대** 넣지 마세요.

## 2단계. GitHub Pages로 배포 (약 5분)

1. GitHub에서 **New repository** → 이름 예: `email-test` → **Public** → 생성
2. **Add file → Upload files** 로 이 폴더의 파일·폴더를 **모두** 끌어다 놓고 **Commit changes**
   (`vendor` 폴더도 꼭 포함)
3. 저장소 **Settings → Pages** → Source: **Deploy from a branch**, Branch: **main / (root)** → Save
4. 1~2분 후 표시되는 주소가 학생용 주소입니다. 뒤에 `teacher.html`을 붙이면 교사용입니다.

> 학생용 주소를 QR코드나 단축 URL로 만들어 시나리오 종이에 함께 인쇄하면 편합니다.

## 3단계. 평가 전 점검

- 학생용 주소에서 직접 한 번 작성·제출 → 교사용 페이지에서 보이는지 확인
- 테스트 제출물은 교사용 페이지에서 **삭제**

## 평가 운영 팁

- **제출 마감**: 평가가 끝나면 `supabase/open-close.sql`의 윗부분을 SQL Editor에서 실행하면 더 이상 제출되지 않습니다. 다시 열 때는 아래쪽 주석을 풀어 실행하세요.
- **재제출**: 학생이 여러 번 제출하면 모두 저장되며, 교사용 화면에서 "N회 제출" 표시가 붙습니다. 기본값은 "학번별 마지막 제출만" 보기입니다.
- **임시저장**: 작성 중인 글(첨부파일 제외)은 학생 브라우저에 자동 임시저장되어, 새로고침해도 사라지지 않습니다. 공용 PC라면 다음 반 시작 전 "모두 지우기"를 안내하세요(제출 완료 시에는 자동으로 지워짐).
- **채점**: 교사용 화면에서 "엑셀(CSV) 내려받기"로 학생별 받는 사람·참조·숨은 참조·제목·본문이 정리된 표를 받을 수 있습니다.
- **첨부파일**: 학생당 최대 5개, 파일당 10MB (`config.js`와 `setup.sql`에서 변경 가능).

## 참고 / 주의

- Supabase 무료 플랜은 **1주일간 사용이 없으면 프로젝트가 일시정지**됩니다. 평가 하루 전 대시보드에 접속해 활성 상태인지 확인하세요(일시정지 시 Restore 클릭).
- 무료 플랜 저장 용량: DB 500MB, 파일 1GB — 한 학년 수행평가에는 충분합니다.
- 학생 화면의 형식 검사는 최소한(학번·이름·받는 사람 필수, 이메일 주소 형식)만 합니다. 제목·본문이 비어 있으면 경고만 하고 제출은 허용합니다. 수신자 배치(참조·숨은 참조 구분)나 첨부 누락 여부 등은 채점 요소로 남겨 두었습니다.
