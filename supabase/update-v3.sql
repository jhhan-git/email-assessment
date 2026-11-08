-- =========================================================
-- 업데이트 v3 : 반별 사이트 (반마다 제출물·자동저장·시험 마감을 따로 관리)
-- setup.sql, update-v2.sql 을 실행한 뒤, SQL Editor 에서 이 파일 전체를 한 번 실행하세요.
-- 여러 번 실행해도 안전합니다. 기존 제출물은 지워지지 않습니다('반 없음'으로 보임).
-- =========================================================

-- 1) 제출물·자동저장에 반 표시
alter table public.submissions add column if not exists class_id text not null default '';
alter table public.drafts      add column if not exists class_id text not null default '';

-- 2) 반별 시험 상태
create table if not exists public.class_settings (
  class_id   text primary key check (class_id ~ '^[A-Za-z0-9_-]{1,20}$'),
  is_open    boolean not null default true,
  closes_at  timestamptz,
  updated_at timestamptz not null default now()
);
alter table public.class_settings enable row level security;

create or replace function public.is_class_open(p_class text)
returns boolean
language sql stable security definer
set search_path = public
as $$
  select coalesce(
    (select is_open and (closes_at is null or now() < closes_at)
       from public.class_settings where class_id = coalesce(p_class, '')),
    true);  -- 아직 한 번도 설정하지 않은 반은 '진행 중'
$$;

create or replace function public.exam_status(p_class text)
returns jsonb
language sql stable security definer
set search_path = public
as $$
  select jsonb_build_object(
    'class_id', coalesce(p_class, ''),
    'open', public.is_class_open(p_class),
    'manual_open', coalesce(s.is_open, true),
    'closes_at', s.closes_at,
    'now', now())
  from (select 1) one
  left join public.class_settings s on s.class_id = coalesce(p_class, '');
$$;

create or replace function public.set_exam_status(p_class text, p_open boolean, p_closes_at timestamptz)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
begin
  if not public.is_teacher() then
    raise exception '교사만 변경할 수 있습니다.';
  end if;
  insert into public.class_settings (class_id, is_open, closes_at, updated_at)
  values (p_class, p_open, p_closes_at, now())
  on conflict (class_id) do update
    set is_open = excluded.is_open, closes_at = excluded.closes_at, updated_at = now();
  return public.exam_status(p_class);
end;
$$;

-- 3) 제출·첨부 업로드: 그 반이 열려 있을 때만
--    반별 사이트의 첨부파일은 "반/제출번호/파일" 경로에 저장됩니다.
drop policy if exists "students can submit" on public.submissions;
create policy "students can submit" on public.submissions
  for insert to anon, authenticated
  with check (
    case when class_id = '' then public.is_exam_open() else public.is_class_open(class_id) end
  );

drop policy if exists "students can upload attachments" on storage.objects;
create policy "students can upload attachments" on storage.objects
  for insert to anon, authenticated
  with check (
    bucket_id = 'attachments' and (
      case when (storage.foldername(name))[1] ~ '^[0-9a-f]{8}-'   -- 예전 방식(반 없음)
           then public.is_exam_open()
           else public.is_class_open((storage.foldername(name))[1]) end)
  );

-- 4) 반별 자동저장·복원
create or replace function public.save_draft(p_id uuid, p_class text, p_no text, p_name text, p_data jsonb)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
begin
  p_class := coalesce(p_class, '');
  p_no := btrim(coalesce(p_no, ''));
  p_name := btrim(coalesce(p_name, ''));
  if p_class !~ '^[A-Za-z0-9_-]{1,20}$' then
    return jsonb_build_object('ok', false, 'error', 'invalid');
  end if;
  if not public.is_class_open(p_class) then
    return jsonb_build_object('ok', false, 'error', 'closed');
  end if;
  if p_id is null or p_no = '' or p_name = '' or char_length(p_no) > 20 or char_length(p_name) > 30 then
    return jsonb_build_object('ok', false, 'error', 'invalid');
  end if;
  if p_data is null or octet_length(p_data::text) > 100000 then
    return jsonb_build_object('ok', false, 'error', 'too_large');
  end if;
  insert into public.drafts (id, class_id, student_no, student_name, data)
  values (p_id, p_class, p_no, p_name, p_data)
  on conflict (id) do update
    set student_no = excluded.student_no, student_name = excluded.student_name,
        data = excluded.data, updated_at = now()
    where public.drafts.class_id = excluded.class_id;   -- 다른 반 칸은 덮어쓰지 않음
  return jsonb_build_object('ok', true, 'updated_at', now());
end;
$$;

create or replace function public.claim_restore(p_class text, p_no text, p_name text)
returns jsonb
language plpgsql security definer
set search_path = public
as $$
declare
  d public.drafts%rowtype;
begin
  if not public.is_class_open(p_class) then
    return jsonb_build_object('ok', false);
  end if;
  select * into d from public.drafts
   where class_id = coalesce(p_class, '')
     and student_no = btrim(coalesce(p_no, '')) and student_name = btrim(coalesce(p_name, ''))
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

-- 5) 함수 실행 권한
revoke execute on function public.set_exam_status(text, boolean, timestamptz) from public, anon;
grant execute on function public.set_exam_status(text, boolean, timestamptz) to authenticated;
grant execute on function public.is_class_open(text) to anon, authenticated;
grant execute on function public.exam_status(text) to anon, authenticated;
grant execute on function public.save_draft(uuid, text, text, text, jsonb) to anon, authenticated;
grant execute on function public.claim_restore(text, text, text) to anon, authenticated;
