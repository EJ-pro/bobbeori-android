begin;

select plan(19);

select has_table('public', 'profiles', 'profiles table exists');
select has_table('public', 'user_preferences', 'user_preferences table exists');
select has_table('public', 'source_videos', 'source_videos table exists');
select has_table('public', 'extraction_jobs', 'extraction_jobs table exists');
select has_table('public', 'recipe_sources', 'recipe_sources table exists');
select has_table('public', 'source_ingredients', 'source_ingredients table exists');
select has_table('public', 'source_steps', 'source_steps table exists');
select has_table('public', 'source_step_ingredients', 'source_step_ingredients table exists');

select col_is_pk('public', 'profiles', 'id', 'profiles.id is the primary key');
select col_is_pk('public', 'extraction_jobs', 'id', 'extraction_jobs.id is the primary key');

select ok(
  (select relrowsecurity from pg_class where oid = 'public.profiles'::regclass),
  'profiles has RLS enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.user_preferences'::regclass),
  'user_preferences has RLS enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.source_videos'::regclass),
  'source_videos has RLS enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.extraction_jobs'::regclass),
  'extraction_jobs has RLS enabled'
);
select ok(
  (select relrowsecurity from pg_class where oid = 'public.recipe_sources'::regclass),
  'recipe_sources has RLS enabled'
);

select has_index(
  'public',
  'source_videos',
  'source_videos_platform_platform_video_id_key',
  'source video identity is unique'
);
select has_index(
  'public',
  'extraction_jobs',
  'extraction_jobs_one_active_per_user_video_idx',
  'one active extraction per user and video is enforced'
);
select has_trigger(
  'auth',
  'users',
  'on_auth_user_created',
  'auth user creation provisions app profile'
);
select has_function(
  'public',
  'complete_extraction_job',
  array['uuid', 'uuid', 'jsonb', 'text', 'text', 'text'],
  'recipe extraction completion RPC exists'
);

select * from finish();
rollback;
