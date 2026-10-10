# Batch 12 release notes

Release candidate 0.12.0 adds bounded request readers, browser mutation origin checks, dynamic nonced script policy, security headers, private route indexing controls, network timeouts, generic page errors and an updated health response. Checkout now uses the documented HTTPS application origin. Payment finalization authenticates exact callback bytes, preserves the purchased billing interval, validates service identity and limits checkout starts.

Additional tests exercise financial replay/mismatch/snapshot behavior, request limits/timeouts, signed bytes, CSP and configuration key-role validation. Read-only release checks, an optional private database dump helper, CI production advisory checking, deployment/backup procedures and an unfilled hosted acceptance record are included. Documentation remains in MD with README.md at root.

All 12 source packages are delivered. Production acceptance is still pending. No remote deployment, GitHub update, hosted migration, payment, actual send or backup was performed.
