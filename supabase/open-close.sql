-- ===== 제출 마감 (평가 종료 후 실행) =====
drop policy if exists "students can submit" on public.submissions;
drop policy if exists "students can upload attachments" on storage.objects;

-- ===== 제출 다시 열기 =====
-- create policy "students can submit" on public.submissions
--   for insert to anon, authenticated with check (true);
-- create policy "students can upload attachments" on storage.objects
--   for insert to anon, authenticated with check (bucket_id = 'attachments');
