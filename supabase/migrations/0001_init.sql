-- Baby Docs — foundation: profiles, families, membership, RLS helpers.
--
-- Order matters here. The security-definer helper functions are created before
-- any policy that needs them, because a policy on `family_members` that queries
-- `family_members` inline recurses and errors on the very first "list my
-- family" query.
--
-- Conventions used in every migration in this directory:
--   * `(select auth.uid())`, never bare `auth.uid()`. The bare form is
--     re-evaluated per row.
--   * RPC parameters are `text`, cast to uuid inside the body, so PostgREST
--     never has to choose between a (uuid) and a (text) overload (PGRST203).
--   * Every file ends with `notify pgrst, 'reload schema';`.
--   * Migrations are append-only once applied anywhere. Fix forward.

create extension if not exists "pgcrypto";

-- ============================================================
-- Shared trigger: server-authoritative updated_at
-- ============================================================
-- Clients never set updated_at. The sync cursor compares against this column,
-- so a device with a wrong clock must not be able to write a timestamp that
-- makes its rows invisible (or permanently re-fetched) for everyone else.
create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

-- ============================================================
-- Profiles — 1:1 with auth.users. Parents and helpers only.
-- A child is NOT a profile; see public.children in 0002.
-- ============================================================
create table public.profiles (
    id           uuid primary key references auth.users(id) on delete cascade,
    display_name text not null default '',
    apns_token   text,
    created_at   timestamptz not null default now(),
    updated_at   timestamptz not null default now()
);

alter table public.profiles enable row level security;

create trigger profiles_touch
    before insert or update on public.profiles
    for each row execute function public.touch_updated_at();

create policy "profiles_self_rw"
    on public.profiles for all
    using (id = (select auth.uid()))
    with check (id = (select auth.uid()));

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
    insert into public.profiles (id, display_name)
    values (
        new.id,
        coalesce(new.raw_user_meta_data->>'display_name',
                 new.raw_user_meta_data->>'full_name',
                 '')
    )
    on conflict (id) do nothing;
    return new;
end;
$$;

create trigger on_auth_user_created
    after insert on auth.users
    for each row execute procedure public.handle_new_user();

-- ============================================================
-- Families
-- ============================================================
create table public.families (
    id          uuid primary key default gen_random_uuid(),
    name        text not null default 'Our family',
    created_by  uuid references public.profiles(id) on delete set null,
    created_at  timestamptz not null default now(),
    updated_at  timestamptz not null default now()
);

alter table public.families enable row level security;

create trigger families_touch
    before insert or update on public.families
    for each row execute function public.touch_updated_at();

-- ============================================================
-- Family members — role lives HERE, never on profiles or children.
-- ============================================================
create table public.family_members (
    id          uuid primary key default gen_random_uuid(),
    family_id   uuid not null references public.families(id) on delete cascade,
    user_id     uuid not null references public.profiles(id) on delete cascade,
    role        text not null check (role in ('owner', 'parent', 'viewer')),
    invited_by  uuid references public.profiles(id) on delete set null,
    joined_at   timestamptz not null default now(),
    removed_at  timestamptz,
    updated_at  timestamptz not null default now(),
    unique (family_id, user_id)
);

-- `role` is text + check, deliberately not a native enum: ALTER TYPE ADD VALUE
-- cannot be used in the same transaction that uses the new value, and each
-- migration file is one transaction. Adding a role later is a constraint swap,
-- not a rewrite.

create index family_members_user_idx   on public.family_members(user_id)   where removed_at is null;
create index family_members_family_idx on public.family_members(family_id) where removed_at is null;

alter table public.family_members enable row level security;

create trigger family_members_touch
    before insert or update on public.family_members
    for each row execute function public.touch_updated_at();

-- ============================================================
-- Security-definer helpers. These break the RLS recursion cycle: they run as
-- the function owner and are not themselves subject to RLS, so a policy on
-- family_members may call them without re-entering family_members' own policy.
--
-- Chosen over JWT custom claims on purpose: removing someone must take effect
-- immediately, not at the next token refresh, and a family is two or three
-- people, so the live lookup costs nothing.
-- ============================================================
create or replace function public.is_family_member(p_family_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
    select exists (
        select 1 from public.family_members
        where family_id = p_family_id
          and user_id = (select auth.uid())
          and removed_at is null
    );
$$;

create or replace function public.family_role(p_family_id uuid)
returns text
language sql stable security definer set search_path = public
as $$
    select role from public.family_members
    where family_id = p_family_id
      and user_id = (select auth.uid())
      and removed_at is null;
$$;

create or replace function public.is_family_staff(p_family_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
    select coalesce(public.family_role(p_family_id) in ('owner', 'parent'), false);
$$;

create or replace function public.is_family_owner(p_family_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
    select coalesce(public.family_role(p_family_id) = 'owner', false);
$$;

-- Do I share any family with this user? Used by the profiles select policy so
-- members can see each other's display names without exposing the whole table.
create or replace function public.shares_family_with(p_user_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
    select exists (
        select 1
        from public.family_members mine
        join public.family_members theirs on theirs.family_id = mine.family_id
        where mine.user_id = (select auth.uid())
          and mine.removed_at is null
          and theirs.user_id = p_user_id
          and theirs.removed_at is null
    );
$$;

grant execute on function public.is_family_member(uuid)   to authenticated;
grant execute on function public.family_role(uuid)        to authenticated;
grant execute on function public.is_family_staff(uuid)    to authenticated;
grant execute on function public.is_family_owner(uuid)    to authenticated;
grant execute on function public.shares_family_with(uuid) to authenticated;

-- ============================================================
-- Policies that depend on the helpers
-- ============================================================
create policy "profiles_family_visible_select"
    on public.profiles for select
    using (public.shares_family_with(id));

create policy "families_member_select"
    on public.families for select
    using (public.is_family_member(id));

create policy "families_owner_update"
    on public.families for update
    using (public.is_family_owner(id))
    with check (public.is_family_owner(id));

-- No client insert on families: creation goes through create_family() in 0003.
-- No client delete on families: deletion goes through delete_family() in 0003.

create policy "family_members_select"
    on public.family_members for select
    using (public.is_family_member(family_id));

-- Deliberately NO insert/update/delete policy on family_members. Every write is
-- a security-definer RPC (accept_invite, change_role, remove_member,
-- transfer_ownership, leave_family). Without this, a viewer could promote
-- themselves to owner with a single PATCH.

notify pgrst, 'reload schema';
