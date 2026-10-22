begin;

select plan(11);

insert into auth.users (
  id,
  instance_id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
values
  (
    '00000000-0000-0000-0000-000000000101',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'rls-user-1@example.com',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000202',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'rls-user-2@example.com',
    '',
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{}'::jsonb,
    now(),
    now()
  );

select is(
  (select count(*)::integer from public.profiles where id in (
    '00000000-0000-0000-0000-000000000101',
    '00000000-0000-0000-0000-000000000202'
  )),
  2,
  'auth trigger creates profiles'
);

select is(
  (select count(*)::integer from public.user_preferences where user_id in (
    '00000000-0000-0000-0000-000000000101',
    '00000000-0000-0000-0000-000000000202'
  )),
  2,
  'auth trigger creates preferences'
);

insert into public.source_videos (
  id,
  platform_video_id,
  canonical_url,
  title,
  availability
)
values (
  '00000000-0000-0000-0000-000000000301',
  'test-video',
  'https://www.youtube.com/watch?v=test-video',
  'Test video',
  'PUBLIC'
);

insert into public.recipe_sources (
  id,
  source_video_id,
  version,
  title,
  schema_version,
  prompt_version,
  validation_status
)
values (
  '00000000-0000-0000-0000-000000000401',
  '00000000-0000-0000-0000-000000000301',
  1,
  'Test recipe',
  '1.0',
  'extractor-v1',
  'VALID'
);

insert into public.extraction_jobs (
  id,
  user_id,
  source_video_id,
  status,
  idempotency_key,
  recipe_source_id,
  completed_at
)
values (
  '00000000-0000-0000-0000-000000000501',
  '00000000-0000-0000-0000-000000000101',
  '00000000-0000-0000-0000-000000000301',
  'COMPLETED',
  '00000000-0000-0000-0000-000000000601',
  '00000000-0000-0000-0000-000000000401',
  now()
);

set local role authenticated;
set local "request.jwt.claims" =
  '{"sub":"00000000-0000-0000-0000-000000000101","role":"authenticated"}';

select is(
  (select count(*)::integer from public.profiles),
  1,
  'user 1 sees only own profile'
);
select is(
  (select count(*)::integer from public.user_preferences),
  1,
  'user 1 sees only own preferences'
);
select is(
  (select count(*)::integer from public.extraction_jobs),
  1,
  'job owner sees extraction job'
);
select is(
  (select count(*)::integer from public.source_videos),
  1,
  'job owner sees referenced source video'
);
select is(
  (select count(*)::integer from public.recipe_sources),
  1,
  'job owner sees extraction result'
);
select throws_ok(
  $$
    insert into public.source_videos (platform_video_id, canonical_url)
    values ('client-write', 'https://www.youtube.com/watch?v=client-write')
  $$,
  '42501',
  null,
  'authenticated client cannot create source video'
);

set local "request.jwt.claims" =
  '{"sub":"00000000-0000-0000-0000-000000000202","role":"authenticated"}';

select is(
  (select count(*)::integer from public.extraction_jobs),
  0,
  'other user cannot see extraction job'
);
select is(
  (select count(*)::integer from public.source_videos),
  0,
  'other user cannot see source video through another user job'
);
select is(
  (select count(*)::integer from public.recipe_sources),
  0,
  'other user cannot see recipe result through another user job'
);

select * from finish();
rollback;
