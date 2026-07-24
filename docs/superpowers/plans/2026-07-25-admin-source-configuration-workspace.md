# 管理员信息来源配置工作台与 X 博主安全移除 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** 让管理员在独立的 Discord/X 工作区中管理来源，并安全移除 X 博主。

**Architecture:** sources 是唯一来源身份表。新迁移为来源增加归档记录与原子移除 RPC；repository 产生不含私密字段的来源卡片 DTO；管理员页按类型分区、以来源卡和详情面板替代表格。数据库而非客户端决定来源是删除、归档或被活动任务阻断。

**Tech Stack:** Next.js App Router、TypeScript、React、Vitest、Supabase/Postgres/pgTAP、现有 RLS 和 CSS token。

## Global Constraints

- Discord 与 X 保持独立来源、任务、checkpoint、事实和 Reader 投影。
- 仅管理员能读取或操作配置、归档和删除。
- 不向组件、HTML、API 或测试 fixture 暴露 URL、Cookie、Profile、原始正文、内部证据、Prompt、Provider 或完整 UUID。
- X 仅在不存在任何任务、覆盖、原始/Canonical 帖子或每日观点段时物理删除；有历史任务或事实时归档。
- queued、leased、running、retryable_failed 任务阻断删除及归档；不得绕过 lease 或删除运行证据。
- 归档停用来源与 X profile，保留事实、摘要、任务、coverage 和证据关系。
- 不执行远程 migration、部署或真实来源操作；都需后续独立授权。

---

## File Structure

- supabase/migrations/20260725090000_admin_x_source_lifecycle.sql: archive columns and atomic source-removal RPC.
- supabase/tests/020_admin_x_source_lifecycle.sql: pgTAP lifecycle matrix.
- apps/control-plane/src/lib/db/repositories/sources.ts: AdminSourceCard and grouped safe projections.
- apps/control-plane/src/lib/db/repositories/x-sources.ts: removeXSource RPC wrapper.
- apps/control-plane/src/lib/db/repositories/sources.test.ts and x-sources.test.ts: projection and RPC parser tests.
- apps/control-plane/src/app/api/admin/x/sources/[sourceId]/route.ts: administrator DELETE endpoint.
- apps/control-plane/src/app/api/api.integration.test.ts: role, confirmation and payload tests.
- apps/control-plane/src/components/admin/SourceConfigurationWorkspace.tsx: type tabs and selected source state.
- apps/control-plane/src/components/admin/SourceConfigurationCard.tsx: source summary and lifecycle track.
- apps/control-plane/src/components/admin/XSourceRemovalControl.tsx: confirmation and result messaging.
- apps/control-plane/src/components/admin/source-configuration-workspace.test.tsx and x-source-removal-control.test.tsx: component tests.
- apps/control-plane/src/app/admin/sources/page.tsx and page.test.tsx: grouped server page.
- apps/control-plane/src/app/globals.css: scoped workspace and responsive styles.

## Task 1: Create the retention-safe database lifecycle

**Files:**

- Create: supabase/migrations/20260725090000_admin_x_source_lifecycle.sql
- Create: supabase/tests/020_admin_x_source_lifecycle.sql

**Interfaces:**

- public.remove_x_source(source ID, actor ID, confirmation name) returns action deleted or archived plus source ID/display name.
- sources gains archived_at, archived_by (referencing public.profiles(id) on delete set null) and archive_reason.
- The function reads sources, x_source_profiles, sync_tasks, source_collection_coverage, raw_messages, canonical_messages and x_daily_viewpoint_segments.

- [ ] **Step 1: Add failing pgTAP lifecycle cases.**

    select plan(12);
    select throws_ok(
      $$ select public.remove_x_source(x_empty_source_id(), admin_id(), 'Wrong') $$,
      'confirmation_mismatch',
      'mismatched confirmation is rejected'
    );
    select results_eq(
      $$ select (public.remove_x_source(x_empty_source_id(), admin_id(), 'Empty X')).action $$,
      array['deleted'::text],
      'empty X source is deleted'
    );
    select results_eq(
      $$ select (public.remove_x_source(x_persisted_source_id(), admin_id(), 'Persisted X')).action $$,
      array['archived'::text],
      'persisted X source is archived'
    );
    select ok(
      exists(select 1 from public.x_daily_viewpoint_segments where source_id = x_persisted_source_id()),
      'archive retains viewpoint facts'
    );
    select throws_ok(
      $$ select public.remove_x_source(x_running_source_id(), admin_id(), 'Running X') $$,
      'source_has_active_task',
      'active task blocks removal'
    );

- [ ] **Step 2: Run the focused database failure.**

Run: supabase test db supabase/tests/020_admin_x_source_lifecycle.sql

Expected: FAIL because archive fields and remove_x_source do not yet exist.

- [ ] **Step 3: Implement the atomic RPC.**

    alter table public.sources
      add column archived_at timestamptz,
      add column archived_by uuid references public.profiles(id) on delete set null,
      add column archive_reason text;

    create or replace function public.remove_x_source(
      p_source_id uuid, p_actor_id uuid, p_confirmation_name text
    ) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
    declare v_source public.sources%rowtype;
    begin
      if not exists (select 1 from public.profiles where id = p_actor_id and role = 'admin') then
        raise exception 'actor_not_authorized' using errcode = '42501';
      end if;
      -- The source row lock serializes this transition with existing X task
      -- creators, which lock the same row before checking source.enabled.
      select * into v_source from public.sources where id = p_source_id for update;
      if not found then raise exception 'source_not_found'; end if;
      if v_source.source_type <> 'x' then raise exception 'source_not_x'; end if;
      if btrim(p_confirmation_name) <> v_source.display_name then raise exception 'confirmation_mismatch'; end if;
      if exists (select 1 from public.sync_tasks where source_id = p_source_id and status in ('queued','leased','running','retryable_failed')) then
        raise exception 'source_has_active_task';
      end if;
      if exists (select 1 from public.sync_tasks where source_id = p_source_id)
        or exists (select 1 from public.source_collection_coverage where source_id = p_source_id)
        or exists (select 1 from public.raw_messages where source_id = p_source_id)
        or exists (select 1 from public.canonical_messages where source_id = p_source_id)
        or exists (select 1 from public.x_daily_viewpoint_segments where source_id = p_source_id) then
        update public.sources set enabled = false, archived_at = timezone('utc', now()), archived_by = p_actor_id,
          archive_reason = 'administrator_removed' where id = p_source_id;
        update public.x_source_profiles set enabled = false where source_id = p_source_id;
        return jsonb_build_object('action','archived','source_id',v_source.id,'display_name',v_source.display_name);
      end if;
      delete from public.sources where id = p_source_id;
      return jsonb_build_object('action','deleted','source_id',v_source.id,'display_name',v_source.display_name);
    end;
    $$;

    revoke all on function public.remove_x_source(uuid, uuid, text) from public, anon, authenticated;
    grant execute on function public.remove_x_source(uuid, uuid, text) to service_role;

Grant only the current authenticated administrator RPC path; do not add a general table-delete policy. Include a migration comment that archived facts remain under existing retention.

- [ ] **Step 4: Verify and commit the database contract.**

Run: supabase test db

Expected: PASS, including the existing Discord/X migration tests.

    git add supabase/migrations/20260725090000_admin_x_source_lifecycle.sql supabase/tests/020_admin_x_source_lifecycle.sql && git commit -m 'feat: add safe X source removal lifecycle'

## Task 2: Expose safe source lifecycle data and DELETE API

**Files:**

- Modify: apps/control-plane/src/lib/db/repositories/sources.ts
- Modify: apps/control-plane/src/lib/db/repositories/x-sources.ts
- Modify: apps/control-plane/src/lib/db/repositories/sources.test.ts
- Create: apps/control-plane/src/lib/db/repositories/x-sources.test.ts
- Create: apps/control-plane/src/app/api/admin/x/sources/[sourceId]/route.ts
- Modify: apps/control-plane/src/app/api/api.integration.test.ts

**Interfaces:**

    export type AdminSourceCard = {
      id: string; sourceType: 'discord' | 'x'; displayName: string;
      enabled: boolean; archivedAt: string | null;
      lifecycle: 'ready' | 'identity_pending' | 'coverage_uninitialized' | 'active_task' | 'archived';
      workerName: string | null; latestCompletedAt: string | null;
    };

    export function listAdminSources(input: { sourceType: 'discord' | 'x'; includeArchived: boolean }): Promise<AdminSourceCard[]>;
    export function removeXSource(input: { sourceId: string; actorId: string; confirmationName: string }): Promise<{ action: 'deleted' | 'archived'; sourceId: string; displayName: string }>;

- [ ] **Step 1: Write failing repository and route tests.**

    it('fails closed for an unknown removal result', async () => {
      databaseMocks.rpc.mockResolvedValue({ data: { action: 'purged' }, error: null });
      await expect(removeXSource({ sourceId: 'source-x', actorId: 'admin-1', confirmationName: 'X' }))
        .rejects.toMatchObject({ message: 'invalid_x_source_removal' });
    });

    it('requires exact confirmation on the DELETE route', async () => {
      const response = await deleteXSource(jsonRequest('/api/admin/x/sources/source-x', { confirmation_name: 'Wrong' }), params('source-x'));
      expect(response.status).toBe(409);
      await expect(response.json()).resolves.toEqual({ error: 'confirmation_mismatch' });
    });

- [ ] **Step 2: Run the focused failure.**

Run: cd apps/control-plane && npm test -- --run src/lib/db/repositories/sources.test.ts src/lib/db/repositories/x-sources.test.ts src/app/api/api.integration.test.ts

Expected: FAIL because the DTO, RPC wrapper and DELETE route do not exist.

- [ ] **Step 3: Implement safe mapping and API error handling.**

    export async function removeXSource(input: { sourceId: string; actorId: string; confirmationName: string }) {
      const { data, error } = await createSupabaseAdminClient().rpc('remove_x_source', {
        p_source_id: input.sourceId, p_actor_id: input.actorId, p_confirmation_name: input.confirmationName,
      });
      if (error) rethrow(error);
      const row = record(data, 'invalid_x_source_removal');
      if ((row.action !== 'deleted' && row.action !== 'archived') || typeof row.source_id !== 'string' || typeof row.display_name !== 'string') {
        throw new XSourceError('invalid_x_source_removal');
      }
      return { action: row.action, sourceId: row.source_id, displayName: row.display_name };
    }

The DELETE route accepts exactly confirmation_name, requires the admin role, returns 422 for malformed input, 409 for confirmation_mismatch/source_has_active_task and 503 for unexpected failures. listAdminSources projects only AdminSourceCard fields; raw content, local references, Worker IDs and provider data never enter client payloads.

- [ ] **Step 4: Verify and commit.**

Run: cd apps/control-plane && npm test -- --run src/lib/db/repositories/sources.test.ts src/lib/db/repositories/x-sources.test.ts src/app/api/api.integration.test.ts

Expected: PASS. Add assertions that API JSON excludes raw text, protected URL, local ref, authorized_worker_id and provider/prompt fields.

    git add apps/control-plane/src/lib/db/repositories/sources.ts apps/control-plane/src/lib/db/repositories/x-sources.ts apps/control-plane/src/lib/db/repositories/sources.test.ts apps/control-plane/src/lib/db/repositories/x-sources.test.ts apps/control-plane/src/app/api/admin/x/sources/[sourceId]/route.ts apps/control-plane/src/app/api/api.integration.test.ts && git commit -m 'feat: expose safe X source removal controls'

## Task 3: Build Discord/X configuration workspaces and source cards

**Files:**

- Create: apps/control-plane/src/components/admin/SourceConfigurationWorkspace.tsx
- Create: apps/control-plane/src/components/admin/SourceConfigurationCard.tsx
- Create: apps/control-plane/src/components/admin/source-configuration-workspace.test.tsx
- Modify: apps/control-plane/src/app/admin/sources/page.tsx
- Create: apps/control-plane/src/app/admin/sources/page.test.tsx

**Interfaces:**

    <SourceConfigurationWorkspace
      discordSources={discordSources}
      xSources={xSources}
      workers={workers}
      initialSourceType='discord'
    />

The workspace owns active source type, archived visibility and selected source ID. Cards display safe source facts and lifecycle only. Existing Discord forms are passed only to Discord detail; existing X coverage/manual-refresh/history forms are passed only to X detail.

- [ ] **Step 1: Write failing workspace and page tests.**

    it('separates Discord and X controls', () => {
      render(<SourceConfigurationWorkspace discordSources={[discord]} xSources={[x]} workers={[]} initialSourceType='discord' />);
      expect(screen.getByRole('tab', { name: 'Discord 配置 · 1' })).toHaveAttribute('aria-selected', 'true');
      expect(screen.queryByText('X 覆盖水位')).not.toBeInTheDocument();
      fireEvent.click(screen.getByRole('tab', { name: 'X 配置 · 1' }));
      expect(screen.getByText('X 覆盖水位')).toBeInTheDocument();
      expect(screen.queryByText('作者配置')).not.toBeInTheDocument();
    });

    it('uses lifecycle facts rather than a percentage', () => {
      render(<SourceConfigurationCard source={{ ...x, lifecycle: 'identity_pending' }} onManage={() => {}} />);
      expect(screen.getByText('身份验证')).toHaveAttribute('data-state', 'current');
      expect(screen.queryByText(/%/)).not.toBeInTheDocument();
    });

- [ ] **Step 2: Run the focused failure.**

Run: cd apps/control-plane && npm test -- --run src/components/admin/source-configuration-workspace.test.tsx src/app/admin/sources/page.test.tsx

Expected: FAIL because grouped workspaces and cards do not exist.

- [ ] **Step 3: Implement accessible tabs, cards and isolated details.**

    <div className='source-workspace' data-source-type={activeSourceType}>
      <div role='tablist' aria-label='来源配置类型' className='source-workspace-tabs'>
        {(['discord', 'x'] as const).map((sourceType) => (
          <button key={sourceType} role='tab' aria-selected={activeSourceType === sourceType} onClick={() => setActiveSourceType(sourceType)}>
            {sourceType === 'discord' ? 'Discord 配置 · ' + discordSources.length : 'X 配置 · ' + xSources.length}
          </button>
        ))}
      </div>
      <section role='tabpanel' aria-label={activeSourceType === 'discord' ? 'Discord 配置' : 'X 配置'}>
        {visibleSources.map((source) => <SourceConfigurationCard key={source.id} source={source} onManage={setSelectedSourceId} />)}
      </section>
    </div>

Render SourceCreateForm only in Discord and XSourceForm only in X. The server reads ?type=discord|x for initial selection; on tab selection replace only the type query parameter with window.history.replaceState so refresh and sharing preserve the selection; invalid values fall back to discord. Replace the eight-column table entirely and do not serialize non-selected source details to the initial client payload.

- [ ] **Step 4: Verify and commit.**

Run: cd apps/control-plane && npm test -- --run src/components/admin/source-configuration-workspace.test.tsx src/app/admin/sources/page.test.tsx src/app/admin/layout.test.tsx

Expected: PASS. Verify tab keyboard navigation, exactly one selected tab, URL selection persistence, named tabpanel and absence of non-selected forms.

    git add apps/control-plane/src/components/admin/SourceConfigurationWorkspace.tsx apps/control-plane/src/components/admin/SourceConfigurationCard.tsx apps/control-plane/src/components/admin/source-configuration-workspace.test.tsx apps/control-plane/src/app/admin/sources/page.tsx apps/control-plane/src/app/admin/sources/page.test.tsx && git commit -m 'feat: separate Discord and X source workspaces'

## Task 4: Add X dangerous action and responsive detail presentation

**Files:**

- Create: apps/control-plane/src/components/admin/XSourceRemovalControl.tsx
- Create: apps/control-plane/src/components/admin/x-source-removal-control.test.tsx
- Modify: apps/control-plane/src/components/admin/SourceAdministrationForm.tsx
- Modify: apps/control-plane/src/components/admin/XCoverageForm.tsx
- Modify: apps/control-plane/src/components/admin/XManualRefreshForm.tsx
- Modify: apps/control-plane/src/components/admin/XHistoryBackfillForm.tsx
- Modify: apps/control-plane/src/components/admin/SourceAuthorProfilesForm.tsx
- Modify: apps/control-plane/src/components/admin/SourceRuleForm.tsx
- Modify: apps/control-plane/src/app/globals.css

**Interfaces:**

    <XSourceRemovalControl sourceId={source.id} displayName={source.displayName} canRemove={source.lifecycle !== 'active_task' && source.lifecycle !== 'archived'} />

The control sends only confirmation_name after exact typed confirmation. Success text is 已删除空 X 来源。 or 已停止并归档 X 来源；历史事实仍按保留策略保存。 Active tasks show 存在进行中或待恢复任务，暂不能移除。 and render no confirmation button.

- [ ] **Step 1: Write failing confirmation tests.**

    it('requires exact typed confirmation', () => {
      render(<XSourceRemovalControl sourceId='source-x' displayName='AllInvestHK' canRemove />);
      expect(screen.getByRole('button', { name: '确认移除博主' })).toBeDisabled();
      fireEvent.change(screen.getByLabelText('输入 AllInvestHK 以确认'), { target: { value: 'AllInvestHK' } });
      expect(screen.getByRole('button', { name: '确认移除博主' })).toBeEnabled();
    });

    it('has no action while an X task is active', () => {
      render(<XSourceRemovalControl sourceId='source-x' displayName='AllInvestHK' canRemove={false} />);
      expect(screen.getByText('存在进行中或待恢复任务，暂不能移除。'));
      expect(screen.queryByRole('button', { name: '确认移除博主' })).not.toBeInTheDocument();
    });

- [ ] **Step 2: Run the focused failure.**

Run: cd apps/control-plane && npm test -- --run src/components/admin/x-source-removal-control.test.tsx src/components/admin/source-author-profiles-form.test.tsx src/components/admin/source-coverage-form.test.tsx src/components/admin/source-rule-form.test.tsx

Expected: FAIL because confirmation and detail-slot layout do not exist.

- [ ] **Step 3: Implement the detail zone and responsive styles.**

    <section className='source-danger-zone' aria-labelledby='remove-x-source-heading'>
      <h3 id='remove-x-source-heading'>危险操作</h3>
      <p>空来源会被删除；已有任务或事实的来源会停止并归档，历史内容不会被删除。</p>
      <label>输入 {displayName} 以确认
        <input value={confirmationName} onChange={(event) => setConfirmationName(event.target.value)} />
      </label>
      <button type='button' className='source-danger-action' disabled={confirmationName !== displayName || pending} onClick={() => void remove()}>
        {pending ? '正在移除…' : '确认移除博主'}
      </button>
    </section>

Add only source-workspace, source-card, source-detail and source-danger selectors. Desktop cards use named grid areas rather than a table. At max-width 767px use one column, make the tab strip itself scrollable if needed, keep controls at least 44px tall and remove document horizontal overflow. Preserve visible focus and disable decorative transitions under prefers-reduced-motion: reduce.

- [ ] **Step 4: Verify and commit.**

Run: cd apps/control-plane && npm test -- --run src/components/admin/x-source-removal-control.test.tsx src/components/admin/source-configuration-workspace.test.tsx src/components/admin/source-author-profiles-form.test.tsx src/components/admin/source-coverage-form.test.tsx src/components/admin/source-rule-form.test.tsx && npm run lint && npm run build

Expected: PASS. Inspect 1280px and 375px renders: no form appears in a table cell, tab labels stay readable and the dangerous action appears only in X detail.

    git add apps/control-plane/src/components/admin/XSourceRemovalControl.tsx apps/control-plane/src/components/admin/x-source-removal-control.test.tsx apps/control-plane/src/components/admin/SourceAdministrationForm.tsx apps/control-plane/src/components/admin/XCoverageForm.tsx apps/control-plane/src/components/admin/XManualRefreshForm.tsx apps/control-plane/src/components/admin/XHistoryBackfillForm.tsx apps/control-plane/src/components/admin/SourceAuthorProfilesForm.tsx apps/control-plane/src/components/admin/SourceRuleForm.tsx apps/control-plane/src/app/globals.css && git commit -m 'feat: add responsive source detail controls'

## Task 5: Cross-layer verification and controlled handoff

**Files:**

- Create: docs/engineering-journal/2026-07-25-admin-source-configuration-workspace.md
- Modify: docs/project-status.md only after all deterministic evidence exists

**Interfaces:**

- The only new external mutation is administrator-only DELETE /api/admin/x/sources/:sourceId with exact confirmation and safe result JSON.
- Existing Discord/X collection and Reader interfaces remain unchanged.

- [ ] **Step 1: Add final integration failures.**

    it('does not expose X removal to an ordinary user', async () => {
      authMocks.requireRole.mockResolvedValue({ status: 403 });
      authMocks.isCurrentUser.mockReturnValue(false);
      const response = await deleteXSource(jsonRequest('/api/admin/x/sources/source-x', { confirmation_name: 'AllInvestHK' }), params('source-x'));
      expect(response.status).toBe(403);
    });

    it('does not change Discord administration when an X source is archived', async () => {
      const sources = await listAdminSources({ sourceType: 'discord', includeArchived: false });
      expect(sources).toEqual([expect.objectContaining({ sourceType: 'discord' })]);
    });

- [ ] **Step 2: Run the complete deterministic stack.**

Run:

    supabase test db
    cd apps/control-plane && npm test && npm run lint && npm run build
    cd ../.. && bash scripts/v0/redact-check.sh && git diff --check

Expected: all tests pass; no credential, source URL, private profile, raw content or prompt appears in fixtures, snapshots or logs.

- [ ] **Step 3: Record only observed evidence and commit.**

Write commands, test counts, responsive review result and limitations in the journal. Update project status only if the prior command actually passes. Do not claim remote migration, deployment or real source removal unless separately authorized and performed.

    git add docs/project-status.md docs/engineering-journal/2026-07-25-admin-source-configuration-workspace.md && git commit -m 'test: verify admin source workspace'

## Final authorization gates

This Plan does not authorize remote state change. After local implementation and deterministic verification, request separate explicit approval for applying 20260725090000_admin_x_source_lifecycle.sql remotely, deploying the control-plane and operating delete/archive against a real X source. Before either remote action, run the redaction and Git checks, verify the exact Supabase/Vercel binding, and retain the additive rollback: archived X sources stay disabled, unfinished tasks use the existing recovery/cancellation path and completed facts are never deleted.

## Plan self-review

- **Spec coverage:** Task 1 implements retention-safe lifecycle; Task 2 provides administrator API and DTOs; Task 3 separates Discord/X configuration; Task 4 implements detail and responsive interaction; Task 5 verifies permissions and isolation.
- **Completeness:** Every code task has a failing test, a focused run command, implementation detail and commit.
- **Type consistency:** AdminSourceCard, removeXSource, SourceConfigurationWorkspace, SourceConfigurationCard and XSourceRemovalControl are declared before later tasks consume them. RPC success is only deleted or archived; active-task blocking remains the explicit source_has_active_task error.
