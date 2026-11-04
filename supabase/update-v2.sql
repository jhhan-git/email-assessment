-- =========================================================
-- 업데이트 v2 : 시험 마감(잠금) + 서버 자동저장·교사 복원
-- setup.sql 을 실행한 뒤, SQL Editor 에서 이 파일 전체를 한 번 실행하세요.
-- 여러 번 실행해도 안전합니다.
-- =========================================================

-- 1) 시험 상태 (한 줄짜리 설정 테이블)
create table if not exists public.exam_settings (
  id         int primary key default 1 check (id = 1),
  is_open    boolean not null default true,   -- 교사가 수동으로 열고 닫음
  closes_at  timestamptz,                     -- 예약 마감 시각 (없으면 수동으로만 마감)
  updated_at timestamptz not null default now()
);
insert into public.exam_settings (id) values (1) on conflict do nothing;
alter table public.exam_settings enable row level security;

create or replace function public.is_exam_open()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select coalesce(
    (select is_open and (closes_at is null or now() < closes_at) from public.exam_settings where id = 1),
    true);
$$;

create or replace function public.exam_status()
returns jsonb
language sql stable security definer
set search_path = public
as $$
  select jsonb_build_object(
    'open', public.is_exam_open(),
    'manual_open', s.is_open,
    'closes_at', s.closes_at,
    'now', now())
  from public.exam_settings s where s.id = 1;
$$;

create or replace function public.set_exam_status(p_open boolean, p_closes_at timestamptz)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
begin
  if not public.is_teacher() then
    raise exception '교사만 변경할 수 있습니다.';
  end if;
  update public.exam_settings
     set is_open = p_open, closes_at = p_closes_at, updated_at = now()
   where id = 1;
  return public.exam_status();
end;
$$;

-- 2) 마감되면 제출·첨부 업로드 차단
drop policy if exists "students can submit" on public.submissions;
create policy "students can submit" on public.submissions
  for insert to anon, authenticated
  with check (public.is_exam_open());

drop policy if exists "students can upload attachments" on storage.objects;
create policy "students can upload attachments" on storage.objects
  for insert to anon, authenticated
  with check (bucket_id = 'attachments' and public.is_exam_open());

-- 3) 서버 자동저장 (재부팅 대비)
--    학생 브라우저마다 무작위 번호(id)로 따로 저장되므로, 남의 학번을 입력해도 남의 글을 덮어쓰거나 볼 수 없습니다.
--    교사가 [복원 허용]을 누르면 10분 동안, 같은 학번·이름을 입력한 화면에서 한 번 불러올 수 있습니다.
create table if not exists public.drafts (
  id            uuid primary key,
  student_no    text not null check (char_length(student_no) between 1 and 20),
  student_name  text not null check (char_length(student_name) between 1 and 30),
  data          jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  restore_until timestamptz
);
create index if not exists drafts_student_idx on public.drafts (student_no, student_name);
alter table public.drafts enable row level security;

grant select, delete on public.drafts to authenticated;
drop policy if exists "teachers can read drafts" on public.drafts;
create policy "teachers can read drafts" on public.drafts
  for select to authenticated using (public.is_teacher());
drop policy if exists "teachers can delete drafts" on public.drafts;
create policy "teachers can delete drafts" on public.drafts
  for delete to authenticated using (public.is_teacher());

-- 학생은 테이블에 직접 접근하지 못하고 아래 함수로만 저장·복원합니다.
create or replace function public.save_draft(p_id uuid, p_no text, p_name text, p_data jsonb)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
begin
  p_no := btrim(coalesce(p_no, ''));
  p_name := btrim(coalesce(p_name, ''));
  if not public.is_exam_open() then
    return jsonb_build_object('ok', false, 'error', 'closed');
  end if;
  if p_id is null or p_no = '' or p_name = '' or char_length(p_no) > 20 or char_length(p_name) > 30 then
    return jsonb_build_object('ok', false, 'error', 'invalid');
  end if;
  if p_data is null or octet_length(p_data::text) > 100000 then
    return jsonb_build_object('ok', false, 'error', 'too_large');
  end if;
  insert into public.drafts (id, student_no, student_name, data)
  values (p_id, p_no, p_name, p_data)
  on conflict (id) do update
    set student_no = excluded.student_no, student_name = excluded.student_name,
        data = excluded.data, updated_at = now();
  return jsonb_build_object('ok', true, 'updated_at', now());
end;
$$;

create or replace function public.claim_restore(p_no text, p_name text)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  d public.drafts%rowtype;
begin
  if not public.is_exam_open() then
    return jsonb_build_object('ok', false);
  end if;
  select * into d from public.drafts
   where student_no = btrim(coalesce(p_no, '')) and student_name = btrim(coalesce(p_name, ''))
     and restore_until > now()
   order by updated_at desc limit 1
   for update;
  if not found then
    return jsonb_build_object('ok', false);
  end if;
  update public.drafts set restore_until = null where id = d.id;
  return jsonb_build_object('ok', true, 'id', d.id, 'data', d.data, 'updated_at', d.updated_at);
end;
$$;

-- 교사: 복원 허용 (10분간 유효, 한 번 불러가면 끝)
create or replace function public.allow_restore(p_id uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  if not public.is_teacher() then
    raise exception '교사만 변경할 수 있습니다.';
  end if;
  update public.drafts set restore_until = now() + interval '10 minutes' where id = p_id;
end;
$$;

-- 4) 함수 실행 권한
revoke execute on function public.set_exam_status(boolean, timestamptz) from public, anon;
revoke execute on function public.allow_restore(uuid) from public, anon;
grant execute on function public.set_exam_status(boolean, timestamptz) to authenticated;
grant execute on function public.allow_restore(uuid) to authenticated;
grant execute on function public.is_exam_open() to anon, authenticated;
grant execute on function public.exam_status() to anon, authenticated;
grant execute on function public.save_draft(uuid, text, text, jsonb) to anon, authenticated;
grant execute on function public.claim_restore(text, text) to anon, authenticated;
