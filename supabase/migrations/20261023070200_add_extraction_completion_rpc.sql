-- Atomically persist one validated recipe extraction and complete its job.

create or replace function public.complete_extraction_job(
  p_job_id uuid,
  p_user_id uuid,
  p_recipe jsonb,
  p_model_provider text,
  p_model_name text,
  p_model_version text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job public.extraction_jobs%rowtype;
  v_recipe_source_id uuid;
  v_version integer;
begin
  select * into v_job
  from public.extraction_jobs
  where id = p_job_id and user_id = p_user_id
  for update;

  if not found then
    raise exception 'EXTRACTION_JOB_NOT_FOUND';
  end if;
  if v_job.status not in ('QUEUED', 'FETCHING_SOURCE', 'EXTRACTING', 'VALIDATING') then
    raise exception 'EXTRACTION_JOB_NOT_ACTIVE';
  end if;

  select coalesce(max(version), 0) + 1 into v_version
  from public.recipe_sources
  where source_video_id = v_job.source_video_id;

  insert into public.recipe_sources (
    source_video_id, version, title, servings_value, servings_confidence,
    total_time_minutes, total_time_confidence, schema_version, prompt_version,
    validation_status
  ) values (
    v_job.source_video_id,
    v_version,
    p_recipe->>'title',
    nullif(p_recipe->>'servingsValue', '')::numeric,
    p_recipe->>'servingsConfidence',
    nullif(p_recipe->>'totalTimeMinutes', '')::integer,
    p_recipe->>'totalTimeConfidence',
    'recipe.v1',
    'extractor.v1',
    p_recipe->>'validationStatus'
  ) returning id into v_recipe_source_id;

  insert into private.recipe_source_payloads (recipe_source_id, raw_result)
  values (v_recipe_source_id, p_recipe);

  insert into public.source_ingredients (
    recipe_source_id, position, name, quantity, quantity_text, unit,
    preparation, is_optional, confidence, evidence_text, evidence_start_seconds
  )
  select
    v_recipe_source_id,
    ingredient.ordinality::integer,
    ingredient.value->>'name',
    nullif(ingredient.value->>'quantity', '')::numeric,
    ingredient.value->>'quantityText',
    ingredient.value->>'unit',
    ingredient.value->>'preparation',
    coalesce((ingredient.value->>'isOptional')::boolean, false),
    ingredient.value->>'confidence',
    ingredient.value->>'evidenceText',
    nullif(ingredient.value->>'evidenceStartSeconds', '')::integer
  from jsonb_array_elements(p_recipe->'ingredients') with ordinality as ingredient(value, ordinality);

  insert into public.source_steps (
    recipe_source_id, position, instruction, duration_seconds, heat_level,
    cautions, start_timestamp_seconds, end_timestamp_seconds, confidence
  )
  select
    v_recipe_source_id,
    step.ordinality::integer,
    step.value->>'instruction',
    nullif(step.value->>'durationSeconds', '')::integer,
    step.value->>'heatLevel',
    coalesce(array(select jsonb_array_elements_text(step.value->'cautions')), '{}'),
    nullif(step.value->>'startTimestampSeconds', '')::integer,
    nullif(step.value->>'endTimestampSeconds', '')::integer,
    step.value->>'confidence'
  from jsonb_array_elements(p_recipe->'steps') with ordinality as step(value, ordinality);

  update public.extraction_jobs
  set status = case
        when p_recipe->>'validationStatus' = 'NEEDS_REVIEW' then 'NEEDS_REVIEW'
        else 'COMPLETED'
      end,
      progress_stage = 'COMPLETED',
      recipe_source_id = v_recipe_source_id,
      model_provider = p_model_provider,
      model_name = p_model_name,
      model_version = p_model_version,
      completed_at = now()
  where id = p_job_id;

  return v_recipe_source_id;
end;
$$;

revoke all on function public.complete_extraction_job(uuid, uuid, jsonb, text, text, text)
from public, anon, authenticated;
grant execute on function public.complete_extraction_job(uuid, uuid, jsonb, text, text, text)
to service_role;
