# Session: 2026-05-30 — GitHub authentication troubleshooting

## Objective
Diagnose why git push to GitHub stopped working.

## Findings
- Remote: HTTPS (`https://github.com/emilkeetui/mining_wq.git`)
- Credential helper: Windows Git Credential Manager (`manager`)
- Stored credential: `git:https://github.com` — **"Saved for this logon only"** (session credential, not persistent)
- This is why pushes stop working after logoff/session reset — common in Windows multi-session/VDI environments

## Recommendations Given
1. Delete session credential: `cmdkey /delete:git:https://github.com`
2. Use a **fine-grained PAT** scoped to `Contents: Read and Write` on this repo only
3. Store persistently via `cmdkey /generic:git:https://github.com /user:emilkeetui /pass:<PAT>`
4. Optionally: enable GitHub branch protection on `master` to block force-push/branch deletion

## Open Questions
- User has not yet applied the fix — awaiting decision on fine-grained PAT approach
