# Batch 5: Brand Studio and Email Template Builder

## Installation
1. Use this package as the updated project. Keep a backup of any local configuration and custom changes.
2. Apply SQL migrations 001 through 005 in numerical order on a new Supabase project. On an existing Batch 4 database apply only `005_brand_templates.sql`.
3. Set up Supabase Auth and Super Admin using `MD/BATCH2_SETUP.md`.
4. Create a company and assign its company administrator in `/admin/companies`.
5. Sign in as the company administrator. On `/dashboard`, use the links under the company membership to open Brand Studio, Templates and Footers.
6. Create a company template, save it, then select Edit in the library to change the draft.

## Access controls
- All mutations call Postgres functions that verify the authenticated user belongs to the specified company and has `company_admin`, `manager`, or `designer` role, or is the Platform Super Admin.
- All company template updates require the template's original organization ID to match the selected organization. Company templates are isolated by the existing RLS policy.
- Platform templates are read-only for company users; this batch does not include a Super Admin UI for creating platform templates.
- Templates are stored as structured JSON blocks, not raw HTML. Text is rendered escaped by React in the editor preview.

## Not yet implemented
- Image/logo upload and media library; rich drag-and-drop editing; full HTML email export; responsive email-client rendering; personalization resolution; real unsubscribe links; approval workflow; sending and test emails.
- Existing footers can be listed and new footers created. Editing/deleting a saved footer will follow.
- Brand Studio persists text/colors/links but does not yet propagate branding into every public website or email renderer.
- A Supabase migration and Next.js production build have not been executed against real infrastructure in this environment. Test before deploying.
