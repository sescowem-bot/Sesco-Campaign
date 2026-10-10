# Live acceptance record

Status: NOT ACCEPTED. No hosted session, live provider, payment, backup or deployment evidence was supplied. Fill this record in the approved staging environment. Source tests cannot substitute for these checks.

| Gate | Evidence required | Current result |
| --- | --- | --- |
| Hosted migrations and RLS | Applied 001–012, cross-company read/write denial and service-only RPC grants | Pending |
| Auth and roles | Confirmation, login, refresh, logout, owner/company/viewer permissions | Pending |
| CMS and branding | Draft privacy, publish visibility, concurrent edit rejection, responsive public navigation | Pending |
| Contacts and campaigns | Import replay, consent, independent approval and protected revisions | Pending |
| Payment acceptance | Test checkout, amount/currency matching, interval snapshot and callback replay | Pending |
| Email/DNS acceptance | Controlled consented send, provider acknowledgement and actual inbox delivery | Pending |
| Callback/suppression | Signed/replayed events, one-click unsubscribe, bounce/complaint suppression | Pending |
| Queue operations | Scheduler, lease recovery, pause/cancel/suspension races, quotas and unknown review | Pending |
| Browser/CSP acceptance | Desktop/mobile, keyboard use, hydration, forms, CSV and no unexpected CSP violations | Pending |
| Load and monitoring | Expected audience load, bounded reporting latency and operational alerts | Pending |
| Backup restore | Isolated successful restore with data, RLS and external object verification | Pending |
| Production authorization | Owner approval, reviewed policy content, supported-tooling assessment and rollback record | Pending |

Record date, environment, tester, observed result and evidence for each gate. Do not mark a gate passed from screenshots, source presence or configuration checks alone.

Known scope limits remain: SMS/WhatsApp unavailable; Platform Admin delegation/invitation emails not implemented; CMS is structured copy editing with remote logo URLs, not media uploading or full article publishing; contact enquiry collection and campaign sample test sending are not included. The existing ESLint 9 tooling emits a support deprecation despite clean lint and production audit results; assess a compatible supported toolchain upgrade before launch. Review these limits against the operator's launch scope.
