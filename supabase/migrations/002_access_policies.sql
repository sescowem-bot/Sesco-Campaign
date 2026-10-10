-- Apply AFTER 001_foundation.sql in a new Supabase project.
-- SECURITY: Only the platform super admin can modify global branding.
create or replace function public.is_platform_super_admin() returns boolean language sql stable security definer set search_path = '' as $$select exists(select 1 from public.platform_staff where user_id=(select auth.uid()) and role='super_admin')$$;
revoke all on function public.is_platform_super_admin() from public;
grant execute on function public.is_platform_super_admin() to authenticated;
create or replace function public.is_organization_member(org uuid) returns boolean language sql stable security definer set search_path = '' as $$select exists(select 1 from public.organization_members where user_id=(select auth.uid()) and organization_id=org)$$;
revoke all on function public.is_organization_member(uuid) from public;
grant execute on function public.is_organization_member(uuid) to authenticated;
create policy "platform staff can view own role" on public.platform_staff for select to authenticated using (user_id=(select auth.uid()));
create policy "members can view own memberships" on public.organization_members for select to authenticated using (user_id=(select auth.uid()) or public.is_platform_super_admin());
create policy "members can view own organizations" on public.organizations for select to authenticated using (public.is_organization_member(id) or public.is_platform_super_admin());
create policy "super admin can view branding" on public.platform_branding for select to authenticated using (public.is_platform_super_admin());
create policy "super admin can update branding" on public.platform_branding for update to authenticated using (public.is_platform_super_admin()) with check (public.is_platform_super_admin());
create policy "members can view organization branding" on public.organization_branding for select to authenticated using (public.is_organization_member(organization_id) or public.is_platform_super_admin());
create policy "members can view subscriptions" on public.organization_subscriptions for select to authenticated using (public.is_organization_member(organization_id) or public.is_platform_super_admin());
create policy "members can view templates" on public.email_templates for select to authenticated using (organization_id is not null and public.is_organization_member(organization_id) or public.is_platform_super_admin());
create policy "members can view footers" on public.email_footers for select to authenticated using (public.is_organization_member(organization_id) or public.is_platform_super_admin());
create policy "members can view sender domains" on public.sending_domains for select to authenticated using (public.is_organization_member(organization_id) or public.is_platform_super_admin());
create policy "public plans visible" on public.subscription_plans for select to anon,authenticated using (is_public and is_active or public.is_platform_super_admin());
-- Do not expose mutation policies for organizations, subscriptions, domains or campaigns yet.
-- Bootstrap the FIRST super admin using Supabase SQL editor ONLY after account verification:
-- insert into public.platform_staff(user_id,role) select id,'super_admin' from auth.users where email='YOUR_VERIFIED_OWNER_EMAIL' on conflict(user_id) do update set role='super_admin';
