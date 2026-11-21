-- A lieu-dit close to the point, shown under the commune of
-- place_derived (architecture §8). Optional and separate from the name; it
-- only qualifies a derived name, hence the check.
alter table public.observations
  add column place_detail text,
  add constraint observations_detail_needs_derived
    check (place_detail is null or place_derived is not null);
