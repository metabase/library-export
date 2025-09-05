-- METABASE_BEGIN
-- entity: model/Transform:v1
-- name: Pokemon Data
-- identifier: pokemon-data-transform
-- description: does the thing
-- tags: ["weekly"]
-- database: "Postgres 13"
-- target:
--   type: table
--   name: PUBLIC.super_cool_pokemon_data
-- METABASE_END

with cleaned as (
  select
    id,
    no,
    name,
    generation,
    lower(type1)        as type1,
    nullif(lower(type2),'') as type2,
    coalesce(ability_hidden, ability2, ability1) as signature_ability,
    category,
    coalesce(mega_evolution_flag = 'Mega', false) as is_mega,
    nullif(region_form,'') is not null              as is_regional,
    hp::int, attack::int, defense::int,
    sp_attack::int, sp_defense::int, speed::int,
    total::int,
    coalesce(gender_female::numeric, 0) as gender_female,
    coalesce(gender_male::numeric, 0)   as gender_male
  from pokedex_with_images_20250829153436
),
eligible as (
  select *
  from cleaned
  where not is_mega
    and not is_regional
),
scored as (
  select
    *,
    -- offense bias prefers glass cannons; add speed to break ties
    ((attack + sp_attack) - (defense + sp_defense)) as offense_bias,
    (attack + sp_attack + speed)                    as raw_sweeper_score
  from eligible
),
ranked as (
  select
    s.*,
    row_number() over (
      partition by generation, type1
      order by offense_bias desc, speed desc, total desc, no asc
    ) as rk
  from scored s
),
context as (
  select
    generation, type1,
    avg(total)::int        as avg_total,
    avg(speed)::int        as avg_speed,
    avg(attack)::int       as avg_attack,
    avg(sp_attack)::int    as avg_sp_attack,
    avg(defense)::int      as avg_defense,
    avg(sp_defense)::int   as avg_sp_defense
  from eligible
  group by generation, type1
)
select
  r.generation,
  r.type1,
  r.name                         as top_sweeper,
  r.no                           as dex_no,
  r.signature_ability,
  jsonb_build_object(
    'hp', r.hp,
    'atk', r.attack,
    'def', r.defense,
    'spa', r.sp_attack,
    'spd', r.sp_defense,
    'spe', r.speed,
    'total', r.total
  )                               as base_stats,
  r.offense_bias,
  r.raw_sweeper_score,
  round(100 * nullif(r.gender_female,0), 1)       as pct_female,
  round(100 * nullif(r.gender_male,0), 1)         as pct_male,
  jsonb_build_object(
    'avg_total', c.avg_total,
    'avg_speed', c.avg_speed,
    'avg_attack', c.avg_attack,
    'avg_sp_attack', c.avg_sp_attack,
    'avg_defense', c.avg_defense,
    'avg_sp_defense', c.avg_sp_defense
  )                               as gen_type_context
from ranked r
join context c using (generation, type1)
where r.rk = 1
order by r.generation, r.type1;
