-- Source videos, extraction jobs, and immutable recipe source versions.

create table public.source_videos (
  id uuid primary key default gen_random_uuid(),
  platform text not null default 'YOUTUBE',
  platform_video_id text not null,
  canonical_url text not null,
  title text,
  channel_name text,
  thumbnail_url text,
  duration_seconds integer,
  availability text not null default 'UNKNOWN',
  metadata_checked_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint source_videos_platform_check check (platform in ('YOUTUBE')),
  constraint source_videos_platform_id_not_blank check (btrim(platform_video_id) <> ''),
  constraint source_videos_url_not_blank check (btrim(canonical_url) <> ''),
  constraint source_videos_duration_check check (
    duration_seconds is null or duration_seconds >= 0
  ),
  constraint source_videos_availability_check check (
    availability in ('PUBLIC', 'PRIVATE', 'DELETED', 'RESTRICTED', 'UNKNOWN')
  ),
  unique (platform, platform_video_id)
);

create trigger source_videos_set_updated_at
before update on public.source_videos
for each row execute function private.set_updated_at();

create table public.recipe_sources (
  id uuid primary key default gen_random_uuid(),
  source_video_id uuid not null references public.source_videos(id) on delete restrict,
  version integer not null,
  title text not null,
  servings_value numeric,
  servings_confidence text not null default 'UNKNOWN',
  total_time_minutes integer,
  total_time_confidence text not null default 'UNKNOWN',
  schema_version text not null,
  prompt_version text not null,
  validation_status text not null,
  created_at timestamptz not null default now(),
  constraint recipe_sources_version_check check (version >= 1),
  constraint recipe_sources_title_not_blank check (btrim(title) <> ''),
  constraint recipe_sources_servings_check check (
    servings_value is null or servings_value > 0
  ),
  constraint recipe_sources_time_check check (
    total_time_minutes is null or total_time_minutes >= 0
  ),
  constraint recipe_sources_servings_confidence_check check (
    servings_confidence in ('CONFIRMED', 'INFERRED', 'UNKNOWN')
  ),
  constraint recipe_sources_time_confidence_check check (
    total_time_confidence in ('CONFIRMED', 'INFERRED', 'UNKNOWN')
  ),
  constraint recipe_sources_validation_check check (
    validation_status in ('VALID', 'NEEDS_REVIEW', 'REJECTED')
  ),
  unique (source_video_id, version)
);

create table private.recipe_source_payloads (
  recipe_source_id uuid primary key references public.recipe_sources(id) on delete cascade,
  provider_payload jsonb,
  raw_result jsonb,
  expires_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.extraction_jobs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  source_video_id uuid not null references public.source_videos(id) on delete restrict,
  status text not null default 'QUEUED',
  progress_stage text,
  attempt_count integer not null default 0,
  idempotency_key uuid not null,
  cache_hit boolean not null default false,
  recipe_source_id uuid references public.recipe_sources(id) on delete set null,
  error_code text,
  retryable boolean,
  model_provider text,
  model_name text,
  model_version text,
  queued_at timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint extraction_jobs_status_check check (
    status in (
      'QUEUED',
      'FETCHING_SOURCE',
      'EXTRACTING',
      'VALIDATING',
      'COMPLETED',
      'NEEDS_REVIEW',
      'FAILED',
      'CANCELLED'
    )
  ),
  constraint extraction_jobs_attempt_count_check check (attempt_count >= 0),
  constraint extraction_jobs_result_check check (
    status not in ('COMPLETED', 'NEEDS_REVIEW') or recipe_source_id is not null
  ),
  unique (user_id, idempotency_key)
);

create trigger extraction_jobs_set_updated_at
before update on public.extraction_jobs
for each row execute function private.set_updated_at();

create unique index extraction_jobs_one_active_per_user_video_idx
on public.extraction_jobs (user_id, source_video_id)
where status in ('QUEUED', 'FETCHING_SOURCE', 'EXTRACTING', 'VALIDATING');

create index extraction_jobs_user_created_idx
on public.extraction_jobs (user_id, created_at desc);

create index extraction_jobs_source_video_idx
on public.extraction_jobs (source_video_id);

create table public.source_ingredients (
  id uuid primary key default gen_random_uuid(),
  recipe_source_id uuid not null references public.recipe_sources(id) on delete cascade,
  position integer not null,
  name text not null,
  quantity numeric,
  quantity_text text,
  unit text,
  preparation text,
  is_optional boolean not null default false,
  confidence text not null default 'UNKNOWN',
  evidence_text text,
  evidence_start_seconds integer,
  created_at timestamptz not null default now(),
  constraint source_ingredients_position_check check (position >= 1),
  constraint source_ingredients_name_not_blank check (btrim(name) <> ''),
  constraint source_ingredients_quantity_check check (quantity is null or quantity >= 0),
  constraint source_ingredients_confidence_check check (
    confidence in ('CONFIRMED', 'INFERRED', 'UNKNOWN')
  ),
  constraint source_ingredients_evidence_time_check check (
    evidence_start_seconds is null or evidence_start_seconds >= 0
  ),
  unique (id, recipe_source_id),
  unique (recipe_source_id, position)
);

create index source_ingredients_recipe_source_idx
on public.source_ingredients (recipe_source_id);

create table public.source_steps (
  id uuid primary key default gen_random_uuid(),
  recipe_source_id uuid not null references public.recipe_sources(id) on delete cascade,
  position integer not null,
  instruction text not null,
  duration_seconds integer,
  heat_level text,
  cautions text[] not null default '{}',
  start_timestamp_seconds integer,
  end_timestamp_seconds integer,
  confidence text not null default 'UNKNOWN',
  created_at timestamptz not null default now(),
  constraint source_steps_position_check check (position >= 1),
  constraint source_steps_instruction_not_blank check (btrim(instruction) <> ''),
  constraint source_steps_duration_check check (
    duration_seconds is null or duration_seconds >= 0
  ),
  constraint source_steps_start_time_check check (
    start_timestamp_seconds is null or start_timestamp_seconds >= 0
  ),
  constraint source_steps_end_time_check check (
    end_timestamp_seconds is null or end_timestamp_seconds >= 0
  ),
  constraint source_steps_time_order_check check (
    start_timestamp_seconds is null
    or end_timestamp_seconds is null
    or end_timestamp_seconds >= start_timestamp_seconds
  ),
  constraint source_steps_confidence_check check (
    confidence in ('CONFIRMED', 'INFERRED', 'UNKNOWN')
  ),
  unique (id, recipe_source_id),
  unique (recipe_source_id, position)
);

create index source_steps_recipe_source_idx
on public.source_steps (recipe_source_id);

create table public.source_step_ingredients (
  recipe_source_id uuid not null references public.recipe_sources(id) on delete cascade,
  source_step_id uuid not null,
  source_ingredient_id uuid not null,
  quantity_override numeric,
  quantity_text_override text,
  unit_override text,
  primary key (source_step_id, source_ingredient_id),
  foreign key (source_step_id, recipe_source_id)
    references public.source_steps(id, recipe_source_id)
    on delete cascade,
  foreign key (source_ingredient_id, recipe_source_id)
    references public.source_ingredients(id, recipe_source_id)
    on delete cascade,
  constraint source_step_ingredients_quantity_check check (
    quantity_override is null or quantity_override >= 0
  )
);

create index source_step_ingredients_recipe_source_idx
on public.source_step_ingredients (recipe_source_id);

alter table public.source_videos enable row level security;
alter table public.recipe_sources enable row level security;
alter table public.extraction_jobs enable row level security;
alter table public.source_ingredients enable row level security;
alter table public.source_steps enable row level security;
alter table public.source_step_ingredients enable row level security;

revoke all on table public.source_videos from anon, authenticated;
revoke all on table public.recipe_sources from anon, authenticated;
revoke all on table public.extraction_jobs from anon, authenticated;
revoke all on table public.source_ingredients from anon, authenticated;
revoke all on table public.source_steps from anon, authenticated;
revoke all on table public.source_step_ingredients from anon, authenticated;

grant select on table public.source_videos to authenticated;
grant select on table public.recipe_sources to authenticated;
grant select on table public.extraction_jobs to authenticated;
grant select on table public.source_ingredients to authenticated;
grant select on table public.source_steps to authenticated;
grant select on table public.source_step_ingredients to authenticated;

grant all on table public.source_videos to service_role;
grant all on table public.recipe_sources to service_role;
grant all on table public.extraction_jobs to service_role;
grant all on table public.source_ingredients to service_role;
grant all on table public.source_steps to service_role;
grant all on table public.source_step_ingredients to service_role;

create policy extraction_jobs_select_own
on public.extraction_jobs
for select
to authenticated
using ((select auth.uid()) = user_id);

create policy source_videos_select_from_own_job
on public.source_videos
for select
to authenticated
using (
  exists (
    select 1
    from public.extraction_jobs job
    where job.source_video_id = source_videos.id
      and job.user_id = (select auth.uid())
  )
);

create policy recipe_sources_select_from_own_job
on public.recipe_sources
for select
to authenticated
using (
  exists (
    select 1
    from public.extraction_jobs job
    where job.recipe_source_id = recipe_sources.id
      and job.user_id = (select auth.uid())
  )
);

create policy source_ingredients_select_from_own_job
on public.source_ingredients
for select
to authenticated
using (
  exists (
    select 1
    from public.extraction_jobs job
    where job.recipe_source_id = source_ingredients.recipe_source_id
      and job.user_id = (select auth.uid())
  )
);

create policy source_steps_select_from_own_job
on public.source_steps
for select
to authenticated
using (
  exists (
    select 1
    from public.extraction_jobs job
    where job.recipe_source_id = source_steps.recipe_source_id
      and job.user_id = (select auth.uid())
  )
);

create policy source_step_ingredients_select_from_own_job
on public.source_step_ingredients
for select
to authenticated
using (
  exists (
    select 1
    from public.extraction_jobs job
    where job.recipe_source_id = source_step_ingredients.recipe_source_id
      and job.user_id = (select auth.uid())
  )
);

comment on table public.source_videos is
  'Server-managed canonical metadata for supported source videos.';
comment on table public.extraction_jobs is
  'User-owned status records for asynchronous recipe extraction.';
comment on table public.recipe_sources is
  'Immutable, versioned recipe extraction results shared by source video.';
