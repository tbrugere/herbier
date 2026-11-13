-- Local development seed, loaded by `supabase start` and `supabase db reset`.
-- One dev user so rows have an owner, and two plants owned by it. The user
-- has no password and is not the account the app signs in with, so RLS hides
-- these plants from the app: they are for SQL by hand (the pgTAP tests create
-- their own users and pass with --no-seed). The token columns are '' because
-- GoTrue reads them as non-null strings. Nothing here reaches production.

insert into auth.users (
  instance_id, id, aud, role, email, email_confirmed_at,
  confirmation_token, recovery_token, email_change, email_change_token_new,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000000',
  '00000000-0000-0000-0000-00000000d001',
  'authenticated', 'authenticated', 'dev@herbier.local', now(),
  '', '', '', '',
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
);

insert into public.plants (
  id, owner_id, display_name, aliases, scientific_name, authorship, notes,
  created_at, updated_at
) values
  (
    '00000000-0000-0000-0000-00000000a001',
    '00000000-0000-0000-0000-00000000d001',
    'Digitale pourpre', '{Digitalis}', 'Digitalis purpurea', 'L.', '',
    now(), now()
  ),
  (
    '00000000-0000-0000-0000-00000000a002',
    '00000000-0000-0000-0000-00000000d001',
    'Plante du talus', '{}', null, null, '',
    now(), now()
  );
