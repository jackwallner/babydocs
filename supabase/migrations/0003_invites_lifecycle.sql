-- Baby Docs — invitations and the membership lifecycle.
--
-- Every mutation here is a security-definer RPC, because `family_members` has
-- no client write policy at all. That is the whole point: there is exactly one
-- code path that can change a role, and it is this file.

-- ============================================================
-- Invite codes
-- ============================================================
create table public.invite_codes (
    code           text primary key,
    family_id      uuid not null references public.families(id) on delete cascade,
    role_to_grant  text not null check (role_to_grant in ('parent', 'viewer')),
    intended_email text,
    created_by     uuid references public.profiles(id) on delete set null,
    created_at     timestamptz not null default now(),
    expires_at     timestamptz not null,
    used_at        timestamptz,
    used_by        uuid references public.profiles(id) on delete set null,
    revoked_at     timestamptz
);

-- An invitation can never grant ownership. There is exactly one owner and the
-- only way to become one is `transfer_ownership`, which the current owner has
-- to call.

create index invite_codes_family_idx on public.invite_codes(family_id)
    where used_at is null and revoked_at is null;

alter table public.invite_codes enable row level security;

create policy "invite_codes_staff_select"
    on public.invite_codes for select
    using (public.is_family_staff(family_id));

-- No client insert, update or delete. Codes are minted and revoked by RPC.

-- Emails are stored normalized, and the constraint is here rather than only in
-- the client so a client-side "looks fine" and a server-side rejection cannot
-- disagree about what an address is.
alter table public.invite_codes
    add constraint invite_email_is_normalized
    check (intended_email is null or intended_email = lower(btrim(intended_email)));

-- ============================================================
-- Redemption rate limiting
-- ============================================================
-- Codes are eight characters, which is guessable given enough attempts, and an
-- invitation is a read/write grant over a family's records. This table is
-- written by `accept_invite` before it decides anything, which is why that
-- function returns failures as values rather than raising: a raised exception
-- rolls back the very row that records the attempt.
create table public.invite_attempts (
    id         uuid primary key default gen_random_uuid(),
    user_id    uuid not null references public.profiles(id) on delete cascade,
    code       text not null,
    attempted_at timestamptz not null default now(),
    succeeded  boolean not null default false
);

create index invite_attempts_user_idx on public.invite_attempts(user_id, attempted_at desc);

alter table public.invite_attempts enable row level security;
-- No policy at all: only the security-definer functions touch this.

-- ============================================================
-- Code generation
-- ============================================================
-- The alphabet excludes 0/O and 1/I/L, because reading a code out loud across
-- a room is the realistic delivery mechanism in the first fortnight after a
-- birth.
create or replace function public.random_invite_code()
returns text
language plpgsql
as $$
declare
    alphabet constant text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
    result text := '';
    i integer;
begin
    for i in 1..8 loop
        result := result || substr(alphabet, 1 + floor(random() * length(alphabet))::int, 1);
    end loop;
    return result;
end;
$$;

create or replace function public.generate_invite_code(
    p_family_id text,
    p_role      text,
    p_ttl_hours text default '48',
    p_email     text default null
)
returns text
language plpgsql security definer set search_path = public
as $$
declare
    v_family_id uuid := p_family_id::uuid;
    v_code text;
    v_attempts integer := 0;
begin
    if not public.is_family_staff(v_family_id) then
        raise exception 'not permitted' using errcode = '42501';
    end if;
    if p_role not in ('parent', 'viewer') then
        raise exception 'invalid role' using errcode = '22023';
    end if;

    loop
        v_code := public.random_invite_code();
        exit when not exists (select 1 from public.invite_codes where code = v_code);
        v_attempts := v_attempts + 1;
        if v_attempts > 20 then
            raise exception 'could not allocate a code' using errcode = '55000';
        end if;
    end loop;

    insert into public.invite_codes (
        code, family_id, role_to_grant, intended_email, created_by, expires_at
    )
    values (
        v_code,
        v_family_id,
        p_role,
        nullif(lower(btrim(coalesce(p_email, ''))), ''),
        (select auth.uid()),
        now() + (greatest(1, least(p_ttl_hours::int, 168)) || ' hours')::interval
    );

    return v_code;
end;
$$;

create or replace function public.revoke_invite_code(p_code text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
    v_family_id uuid;
begin
    select family_id into v_family_id from public.invite_codes where code = upper(btrim(p_code));
    if v_family_id is null then
        return;
    end if;
    if not public.is_family_staff(v_family_id) then
        raise exception 'not permitted' using errcode = '42501';
    end if;
    update public.invite_codes set revoked_at = now()
    where code = upper(btrim(p_code)) and used_at is null and revoked_at is null;
end;
$$;

-- ============================================================
-- Redemption
-- ============================================================
-- Returns a row rather than raising, so the rate-limit insert above survives a
-- refusal. The client turns `error_code` back into a sentence.
create or replace function public.accept_invite(p_code text)
returns table (ok boolean, joined_family_id uuid, error_code text)
language plpgsql security definer set search_path = public
as $$
declare
    v_user uuid := (select auth.uid());
    v_code text := upper(btrim(p_code));
    v_invite public.invite_codes;
    v_recent integer;
begin
    if v_user is null then
        raise exception 'not signed in' using errcode = '42501';
    end if;

    select count(*) into v_recent
    from public.invite_attempts
    where user_id = v_user
      and attempted_at > now() - interval '1 hour'
      and succeeded = false;

    insert into public.invite_attempts (user_id, code) values (v_user, v_code);

    if v_recent >= 10 then
        return query select false, null::uuid, 'rate_limited';
        return;
    end if;

    select * into v_invite
    from public.invite_codes
    where code = v_code
      and used_at is null
      and revoked_at is null
      and expires_at > now();

    if v_invite.code is null then
        return query select false, null::uuid, 'invalid_code';
        return;
    end if;

    -- An address on the invitation locks it to that person. Checked against the
    -- authenticated user's own email, not against anything the client sends.
    if v_invite.intended_email is not null
       and v_invite.intended_email <> lower((select email from auth.users where id = v_user)) then
        return query select false, null::uuid, 'invalid_code';
        return;
    end if;

    -- One family per account. Two would mean two plans, two sets of deadlines
    -- and no way for the app to say which baby a notification is about.
    if exists (
        select 1 from public.family_members
        where user_id = v_user and removed_at is null
    ) then
        return query select false, null::uuid, 'already_in_group';
        return;
    end if;

    insert into public.family_members (family_id, user_id, role, invited_by)
    values (v_invite.family_id, v_user, v_invite.role_to_grant, v_invite.created_by)
    on conflict (family_id, user_id) do update
        set removed_at = null, role = excluded.role;

    update public.invite_codes
    set used_at = now(), used_by = v_user
    where code = v_code;

    update public.invite_attempts
    set succeeded = true
    where user_id = v_user and code = v_code and succeeded = false;

    return query select true, v_invite.family_id, null::text;
end;
$$;

-- ============================================================
-- Family lifecycle
-- ============================================================
create or replace function public.create_family(p_name text)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
    v_user uuid := (select auth.uid());
    v_id uuid;
begin
    if v_user is null then
        raise exception 'not signed in' using errcode = '42501';
    end if;
    if exists (select 1 from public.family_members where user_id = v_user and removed_at is null) then
        raise exception 'already in a family' using errcode = '23505';
    end if;

    insert into public.families (name, created_by)
    values (coalesce(nullif(btrim(p_name), ''), 'Our family'), v_user)
    returning id into v_id;

    insert into public.family_members (family_id, user_id, role)
    values (v_id, v_user, 'owner');

    return v_id;
end;
$$;

create or replace function public.change_role(
    p_family_id text,
    p_user_id   text,
    p_role      text
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
    v_family_id uuid := p_family_id::uuid;
    v_user_id uuid := p_user_id::uuid;
begin
    if not public.is_family_owner(v_family_id) then
        raise exception 'not permitted' using errcode = '42501';
    end if;
    if p_role not in ('parent', 'viewer') then
        raise exception 'invalid role' using errcode = '22023';
    end if;
    -- The owner cannot demote themselves. Ownership moves by transfer, so a
    -- family can never end up with nobody able to manage it.
    if v_user_id = (select auth.uid()) then
        raise exception 'transfer ownership instead' using errcode = '22023';
    end if;

    update public.family_members
    set role = p_role
    where family_id = v_family_id and user_id = v_user_id and removed_at is null;
end;
$$;

create or replace function public.remove_member(p_family_id text, p_user_id text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
    v_family_id uuid := p_family_id::uuid;
    v_user_id uuid := p_user_id::uuid;
begin
    if not public.is_family_owner(v_family_id) then
        raise exception 'not permitted' using errcode = '42501';
    end if;
    if v_user_id = (select auth.uid()) then
        raise exception 'the owner cannot remove themselves' using errcode = '22023';
    end if;

    update public.family_members
    set removed_at = now()
    where family_id = v_family_id and user_id = v_user_id and removed_at is null;
end;
$$;

create or replace function public.transfer_ownership(p_family_id text, p_new_owner_id text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
    v_family_id uuid := p_family_id::uuid;
    v_new_owner uuid := p_new_owner_id::uuid;
begin
    if not public.is_family_owner(v_family_id) then
        raise exception 'not permitted' using errcode = '42501';
    end if;
    if not exists (
        select 1 from public.family_members
        where family_id = v_family_id and user_id = v_new_owner and removed_at is null
    ) then
        raise exception 'not a member' using errcode = '22023';
    end if;

    update public.family_members set role = 'parent'
    where family_id = v_family_id and user_id = (select auth.uid());

    update public.family_members set role = 'owner'
    where family_id = v_family_id and user_id = v_new_owner;
end;
$$;

create or replace function public.leave_family(p_family_id text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
    v_family_id uuid := p_family_id::uuid;
    v_user uuid := (select auth.uid());
    v_remaining integer;
begin
    if public.is_family_owner(v_family_id) then
        select count(*) into v_remaining
        from public.family_members
        where family_id = v_family_id and removed_at is null and user_id <> v_user;

        if v_remaining > 0 then
            raise exception 'transfer ownership before leaving' using errcode = '22023';
        end if;
    end if;

    update public.family_members
    set removed_at = now()
    where family_id = v_family_id and user_id = v_user and removed_at is null;
end;
$$;

create or replace function public.delete_family(p_family_id text)
returns void
language plpgsql security definer set search_path = public
as $$
declare
    v_family_id uuid := p_family_id::uuid;
begin
    if not public.is_family_owner(v_family_id) then
        raise exception 'not permitted' using errcode = '42501';
    end if;
    delete from public.families where id = v_family_id;
end;
$$;

-- App Review 5.1.1(v). Hands off or cleans up any family this user owns, then
-- removes the account. Rows they authored keep their name snapshot, so the
-- other parent's plan still reads "recorded by Sam" after Sam has gone.
create or replace function public.delete_account()
returns void
language plpgsql security definer set search_path = public
as $$
declare
    v_user uuid := (select auth.uid());
    r record;
    v_heir uuid;
begin
    if v_user is null then
        raise exception 'not signed in' using errcode = '42501';
    end if;

    for r in
        select family_id from public.family_members
        where user_id = v_user and role = 'owner' and removed_at is null
    loop
        select user_id into v_heir
        from public.family_members
        where family_id = r.family_id and removed_at is null and user_id <> v_user
        order by joined_at
        limit 1;

        if v_heir is null then
            delete from public.families where id = r.family_id;
        else
            update public.family_members set role = 'owner'
            where family_id = r.family_id and user_id = v_heir;
        end if;
    end loop;

    update public.family_members set removed_at = now()
    where user_id = v_user and removed_at is null;

    delete from auth.users where id = v_user;
end;
$$;

grant execute on function public.generate_invite_code(text, text, text, text) to authenticated;
grant execute on function public.revoke_invite_code(text)                     to authenticated;
grant execute on function public.accept_invite(text)                          to authenticated;
grant execute on function public.create_family(text)                          to authenticated;
grant execute on function public.change_role(text, text, text)                to authenticated;
grant execute on function public.remove_member(text, text)                    to authenticated;
grant execute on function public.transfer_ownership(text, text)               to authenticated;
grant execute on function public.leave_family(text)                           to authenticated;
grant execute on function public.delete_family(text)                          to authenticated;
grant execute on function public.delete_account()                             to authenticated;

-- Never callable by a client: these are the internals of the functions above.
revoke execute on function public.random_invite_code() from authenticated, anon;

notify pgrst, 'reload schema';
