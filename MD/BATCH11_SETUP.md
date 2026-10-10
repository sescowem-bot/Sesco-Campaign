# Batch 11 setup

Version 0.11.0 adds structured public CMS and administration controls. Use Node 24 and npm ci. Back up first, then apply only migration 011 when 001 through 010 are already installed. New databases apply 001 through 011 in order. There are no new environment variables. Existing provider/payment setup still requires acceptance.

## Website CMS

Open /admin/cms as Super Admin. Select Identity & navigation or a public page. Edit structured headings, descriptions and content sections; add, remove or reorder sections. Home also exposes action labels/routes, feature introduction and brand highlight text. Identity settings include platform name, tagline, HTTPS logo URL, primary color, font, public support email, footer description, operator name and main navigation. Prices remain in Plans & pricing. Company campaign branding is separate from website identity.

Save draft persists content without changing public pages. Publish saved draft applies the stored draft; unsaved edits are not published. Revisions prevent concurrent editors from silently overwriting changes. Recent history and audit records show save, publish and unpublish operations. Unpublish restores source defaults; it does not remove the route. A malformed published document also falls back to source defaults. The initial website identity preserves the previous platform_branding name, tagline and color. After migration 011, use Website CMS for published identity; the legacy platform_branding table is retained for compatibility and is no longer the website source of truth.

Public requests read only the published JSON through cms_public. Draft tables and revision history have Super Admin select policies and no authenticated mutation policies; updates go through cms_edit. Both server action and database enforce owner authorization. Server actions validate structured content; rendering validates again and escapes plain text. Arbitrary HTML, executable links, injected fonts and scripts are unsupported. Navigation and action links use existing public routes. Legal footer links remain present. Logos must be HTTPS image URLs without credentials; they load directly without a server image proxy and use no-referrer. Ensure the operator controls the chosen image host. Built-in font choices make no external font request. Public content fetches use the public Supabase key, a five-second timeout and no cache; root rendering is dynamic so publication appears on subsequent requests. During setup or a database outage, source defaults remain available and may differ from the last published copy.

Auth forms, subscription pricing, unsubscribe confirmation and campaign tools cannot be removed through page copy editing. Legal content remains draft material until reviewed by the operator. Homepage decorative previews remain explicitly illustrative. The CMS is a structured content editor, not arbitrary HTML page construction, image uploading or a blog article publishing system.

## Company administration

In /admin/companies, open company controls to set pending, active or suspended status. Non-active status pauses queued/running runs. Provider requests already in flight may finish. Reactivation does not resume paused campaigns automatically. Monthly email overrides apply only to the active subscription; blank removes that override and uses plan allowance, zero blocks dispatch. Other override keys are preserved.

Company administrators can use /dashboard/team?org=<uuid> to assign verified existing accounts and change roles. Super Admin can manage any company team, including suspended companies. Other company roles cannot read or manage this team directory; company administrators need an active company. No invite or notification email is sent. Last administrator removal/demotion is blocked, with organization-row locking to serialize role changes. Removing company access does not delete the person's account or other company memberships.

/admin/audit shows the latest 100 recorded operations, optionally filtered by company ID. It is owner-only and read-only; no export or complete historical search is claimed. The platform owner also has a My company workspaces link and can use ordinary campaign tools after assignment to a company.

## Documentation and release acceptance

All authored Markdown lives in MD. README.md is the only root Markdown file, for GitHub. The engineering handoff is MD/AGENTS.md; tools that auto-discover only root AGENTS.md should explicitly read that relocated file. Existing historical Markdown was moved and documentation references updated. Non-Markdown review fixtures remain in docs/preview.

Run npm run lint, npm run typecheck, npm test, npm run build, npm run test:smoke and npm audit --omit=dev. Before production, validate hosted RLS and signed-in CMS/team flows, desktop/mobile layout, external logo availability, provider callbacks, payment handling and worker operations. Platform staff creation still uses reviewed owner bootstrap; granular Platform Admin delegation, invitations, contact enquiry collection and full media/blog workflows are not added in this release.

For rollback, restore Batch 10 code before removing migration 011 objects. Export CMS content and history first. The migration is additive and leaves historical branding/data intact; prefer a forward fix. Do not drop unrelated tables.
