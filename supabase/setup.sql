-- =========================================================
-- 업무용 이메일 작성 수행평가 : Supabase 초기 설정
-- Supabase 대시보드 > SQL Editor 에 전체를 붙여넣고 Run 하세요.
-- ※ 맨 아래 선생님 이메일을 꼭 본인 것으로 바꾸세요.
-- =========================================================

-- 1) 제출물 테이블
create table if not exists public.submissions (
  id           uuid primary key default gen_random_uuid(),
  created_at   timestamptz not null default now(),
  student_no   text not null check (char_length(student_no) between 1 and 20),
  student_name text not null check (char_length(student_name) between 1 and 30),
  sender       text check (char_length(sender) <= 200),
  to_addrs     text[] not null default '{}',
  cc_addrs     text[] not null default '{}',
  bcc_addrs    text[] not null default '{}',
  subject      text check (char_length(subject) <= 300),
  body         text check (char_length(body) <= 20000),
  signature    text check (char_length(signature) <= 2000),
  attachments  jsonb not null default '[]'::jsonb,
  check (cardinality(to_addrs) between 1 and 30),
  check (cardinality(cc_addrs) <= 30),
  check (cardinality(bcc_addrs) <= 30)
);

-- 2) 선생님 명단 (여기 등록된 이메일로 로그인한 사람만 제출물 열람 가능)
create table if not exists public.teachers (
  email text primary key
);

alter table public.submissions enable row level security;
alter table public.teachers    enable row level security;

create or replace function public.is_teacher()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.teachers
    where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;
grant execute on function public.is_teacher() to anon, authenticated;

-- 3) 권한: 학생(비로그인)은 "제출"만, 선생님은 "열람·삭제"만
grant insert on public.submissions to anon, authenticated;
grant select, delete on public.submissions to authenticated;

drop policy if exists "students can submit" on public.submissions;
create policy "students can submit" on public.submissions
  for insert to anon, authenticated
  with check (true);

drop policy if exists "teachers can read" on public.submissions;
create policy "teachers can read" on public.submissions
  for select to authenticated
  using (public.is_teacher());

drop policy if exists "teachers can delete" on public.submissions;
create policy "teachers can delete" on public.submissions
  for delete to authenticated
  using (public.is_teacher());

-- 4) 첨부파일 저장소 (비공개, 파일당 10MB)
insert into storage.buckets (id, name, public, file_size_limit)
values ('attachments', 'attachments', false, 10485760)
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit;

drop policy if exists "students can upload attachments" on storage.objects;
create policy "students can upload attachments" on storage.objects
  for insert to anon, authenticated
  with check (bucket_id = 'attachments');

drop policy if exists "teachers can read attachments" on storage.objects;
create policy "teachers can read attachments" on storage.objects
  for select to authenticated
  using (bucket_id = 'attachments' and public.is_teacher());

drop policy if exists "teachers can delete attachments" on storage.objects;
create policy "teachers can delete attachments" on storage.objects
  for delete to authenticated
  using (bucket_id = 'attachments' and public.is_teacher());

-- 5) ★ 선생님 이메일 등록 (Authentication에서 만든 계정 이메일과 같아야 함)
insert into public.teachers (email) values ('teacher@example.com')
on conflict do nothing;
