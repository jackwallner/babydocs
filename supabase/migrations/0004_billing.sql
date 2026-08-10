-- Baby Docs — family-scoped entitlement.
--
-- One parent pays and the other is covered. Charging the second parent to see
-- the same deadline would be the fastest way to make the app useless, so the
-- entitlement is a property of the family, not of the member.
--
-- The row is written by the RevenueCat webhook running as the service role.
-- Clients read it and never write it: an entitlement a client can PATCH is not
-- an entitlement.

create table public.family_billing (
    family_id     uuid primary key references public.families(id) on delete cascade,
    entitlement   text not null default 'free' check (entitlement in ('free', 'plus')),
    expires_at    timestamptz,
    is_lifetime   boolean not null default false,
    rc_app_user_id text,
    updated_at    timestamptz not null default now()
);

alter table public.family_billing enable row level security;

create trigger family_billing_touch
    before insert or update on public.family_billing
    for each row execute function public.touch_updated_at();

create policy "family_billing_member_select"
    on public.family_billing for select
    using (public.is_family_member(family_id));

-- No client insert, update or delete.

-- The webhook knows the RevenueCat app user id, which `StoreService.identify()`
-- set to the Supabase user id. This is how it finds the family to credit, and
-- it is the reason `identify()` is not optional: without it the webhook sees an
-- anonymous id, has nobody to credit, and the other parent silently never gets
-- Plus.
create or replace function public.apply_billing(
    p_user_id     text,
    p_entitlement text,
    p_expires_at  text default null,
    p_is_lifetime text default 'false'
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
    v_user uuid := p_user_id::uuid;
    v_family uuid;
begin
    select family_id into v_family
    from public.family_members
    where user_id = v_user and removed_at is null
    order by joined_at
    limit 1;

    if v_family is null then
        -- The purchase happened before the family existed, which is the normal
        -- order for someone who buys Plus in order to invite the other parent.
        -- Nothing to credit yet; the next webhook or the next foreground
        -- refresh picks it up once the family exists.
        return;
    end if;

    insert into public.family_billing (family_id, entitlement, expires_at, is_lifetime, rc_app_user_id)
    values (
        v_family,
        p_entitlement,
        nullif(p_expires_at, '')::timestamptz,
        p_is_lifetime::boolean,
        p_user_id
    )
    on conflict (family_id) do update set
        entitlement    = excluded.entitlement,
        expires_at     = excluded.expires_at,
        is_lifetime    = excluded.is_lifetime,
        rc_app_user_id = excluded.rc_app_user_id;
end;
$$;

-- Service role only. Never granted to `authenticated`.
revoke execute on function public.apply_billing(text, text, text, text) from authenticated, anon;

notify pgrst, 'reload schema';
