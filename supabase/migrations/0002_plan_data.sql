-- Baby Docs — the plan itself: household profile, children, tasks, documents,
-- receipts, notes.
--
-- Every table follows the same shape, because `SyncEngine` treats them
-- identically:
--   * `id uuid primary key` supplied by the client. Client-generated ids are
--     what make a retried push an idempotent upsert instead of a duplicate.
--   * `family_id` for the RLS scope and for the pull filter.
--   * `updated_at` written only by the trigger, never by the client.
--   * `deleted_at` for tombstones. Nothing is ever hard-deleted by a sync.
--
-- Writes are gated on `is_family_staff`, so a viewer (a grandparent helping
-- with an appointment) reads the plan and cannot change it. The client mirrors
-- these rules in its UI; it never *is* the enforcement.

-- ============================================================
-- Household answers. One row per family.
-- ============================================================
create table public.family_profiles (
    id                      uuid primary key,
    family_id               uuid not null references public.families(id) on delete cascade,
    residence_state         text not null default '',
    parentage               text not null default 'unknown',
    second_parent_on_record boolean not null default false,
    insurance_kind          text not null default 'unknown',
    employer_plan_name      text not null default '',
    has_dependent_care_fsa  boolean not null default false,
    wants_passport          boolean not null default false,
    wants_529               boolean not null default false,
    wants_trump_account     boolean not null default true,
    taking_parental_leave   boolean not null default true,
    updated_at              timestamptz not null default now(),
    deleted_at              timestamptz
);

-- One profile per family, enforced here rather than in the client, because two
-- devices completing the intake at once would otherwise produce two rows and
-- the rules engine would read whichever it fetched first.
create unique index family_profiles_one_per_family on public.family_profiles(family_id)
    where deleted_at is null;

-- ============================================================
-- Children
-- ============================================================
create table public.children (
    id                            uuid primary key,
    family_id                     uuid not null references public.families(id) on delete cascade,
    name                          text not null default '',
    birth_date                    timestamptz not null,
    birth_state                   text not null default '',
    birth_county                  text not null default '',
    is_us_citizen                 boolean not null default true,
    ssn_status                    text not null default 'unknown',
    ssn_received_at               timestamptz,
    birth_certificate_received_at timestamptz,
    certified_copies_on_hand      integer not null default 0,
    color_index                   integer not null default 0,
    notes                         text not null default '',
    updated_at                    timestamptz not null default now(),
    deleted_at                    timestamptz
);

-- Deliberately no column for a Social Security number. The app tracks whether
-- one has arrived, never what it is. Adding such a column later would be a
-- different product with a different threat model, and this comment is here so
-- that decision has to be made on purpose.

create index children_family_idx on public.children(family_id);

-- ============================================================
-- Tasks
-- ============================================================
create table public.requirement_tasks (
    id                  uuid primary key,
    family_id           uuid not null references public.families(id) on delete cascade,
    child_id            uuid not null references public.children(id) on delete cascade,
    catalog_key         text not null default '',
    title               text not null default '',
    detail              text not null default '',
    category            text not null default 'identity',
    due_at              timestamptz,
    deadline_kind       text not null default 'none',
    deadline_basis      text not null default '',
    official_url        text not null default '',
    official_link_label text not null default '',
    source_url          text not null default '',
    source_verified_on  timestamptz,
    assignee_user_id    uuid references public.profiles(id) on delete set null,
    assignee_name       text not null default '',
    completed_at        timestamptz,
    completed_by_name   text not null default '',
    dismissed_at        timestamptz,
    parent_notes        text not null default '',
    sort_weight         integer not null default 100,
    is_custom           boolean not null default false,
    updated_at          timestamptz not null default now(),
    deleted_at          timestamptz
);

create index requirement_tasks_family_idx on public.requirement_tasks(family_id);
create index requirement_tasks_child_idx  on public.requirement_tasks(child_id);

-- One generated task per (child, catalog key). The client derives the id from
-- exactly this pair, so both parents' devices produce the same id offline and
-- the second upsert is a no-op. This index is the backstop for the case where
-- that ever stops being true.
create unique index requirement_tasks_catalog_unique
    on public.requirement_tasks(child_id, catalog_key)
    where catalog_key <> '' and deleted_at is null;

-- ============================================================
-- Documents
-- ============================================================
create table public.document_items (
    id               uuid primary key,
    family_id        uuid not null references public.families(id) on delete cascade,
    task_id          uuid not null references public.requirement_tasks(id) on delete cascade,
    catalog_key      text not null default '',
    title            text not null default '',
    detail           text not null default '',
    is_on_hand       boolean not null default false,
    marked_on_hand_at timestamptz,
    sort_weight      integer not null default 100,
    updated_at       timestamptz not null default now(),
    deleted_at       timestamptz
);

create index document_items_task_idx   on public.document_items(task_id);
create index document_items_family_idx on public.document_items(family_id);

-- ============================================================
-- Receipts
-- ============================================================
create table public.receipts (
    id               uuid primary key,
    family_id        uuid not null references public.families(id) on delete cascade,
    task_id          uuid not null references public.requirement_tasks(id) on delete cascade,
    kind             text not null default 'note',
    value            text not null default '',
    recorded_at      timestamptz not null default now(),
    recorded_by_name text not null default '',
    updated_at       timestamptz not null default now(),
    deleted_at       timestamptz
);

create index receipts_task_idx   on public.receipts(task_id);
create index receipts_family_idx on public.receipts(family_id);

-- ============================================================
-- Notes
-- ============================================================
create table public.child_notes (
    id              uuid primary key,
    family_id       uuid not null references public.families(id) on delete cascade,
    child_id        uuid not null references public.children(id) on delete cascade,
    title           text not null default '',
    body            text not null default '',
    is_pinned       boolean not null default false,
    created_by_name text not null default '',
    updated_at      timestamptz not null default now(),
    deleted_at      timestamptz
);

create index child_notes_child_idx  on public.child_notes(child_id);
create index child_notes_family_idx on public.child_notes(family_id);

-- ============================================================
-- Triggers, RLS and policies, applied uniformly
-- ============================================================
do $$
declare
    t text;
begin
    foreach t in array array[
        'family_profiles', 'children', 'requirement_tasks',
        'document_items', 'receipts', 'child_notes'
    ]
    loop
        execute format('alter table public.%I enable row level security', t);

        execute format(
            'create trigger %I before insert or update on public.%I
             for each row execute function public.touch_updated_at()',
            t || '_touch', t
        );

        -- Every member reads. The pull is already filtered by family_id on the
        -- client; this is what makes that filter enforcement rather than
        -- politeness.
        execute format(
            'create policy %I on public.%I for select using (public.is_family_member(family_id))',
            t || '_member_select', t
        );

        execute format(
            'create policy %I on public.%I for insert with check (public.is_family_staff(family_id))',
            t || '_staff_insert', t
        );

        execute format(
            'create policy %I on public.%I for update
             using (public.is_family_staff(family_id))
             with check (public.is_family_staff(family_id))',
            t || '_staff_update', t
        );

        -- No delete policy anywhere. Deletion is a tombstone written by the
        -- update path, so a row the client has queued for deletion can still be
        -- read by the push that has to send it.
    end loop;
end;
$$;

notify pgrst, 'reload schema';
