// ===== 여기만 수정하세요 =====
// Supabase 대시보드 > Project Settings > API 에서 복사합니다.
window.APP_CONFIG = {
  SUPABASE_URL: "https://fdedhpggvwudnsnqowyw.supabase.co", // 예: "https://abcdefgh.supabase.co"
  SUPABASE_ANON_KEY: "sb_publishable_D4RZTU918ngD8anLdDVS_Q_ck35qEwO", // anon(public) 키 또는 publishable 키 (sb_publishable_...)

  TITLE: "업무용 이메일 작성 수행평가",
  MAX_FILES: 5,            // 첨부파일 최대 개수
  MAX_FILE_MB: 10,         // 첨부파일 1개당 최대 용량(MB) — setup.sql의 버킷 제한과 맞추세요

  // 학생 화면의 [과제 파일]에서 내려받을 파일 (files 폴더에 넣고 여기에 적기). 비우면 칸이 사라집니다.
  // path: 실제 파일 위치(영문), name: 학생이 내려받을 때의 파일 이름
  ASSIGNMENT_FILES: [
    { path: "files/quote_mirae.pdf", name: "견적서_미래상사_HB-1500_50대.pdf" },
    { path: "files/spec_hb1500.pdf", name: "제품사양서_HB-1500.pdf" },
    { path: "files/quote_daon.pdf",  name: "견적서_다온유통_모니터30대.pdf" }
  ]
};
