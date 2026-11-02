# Notes for Claude

- Keep the top-level `README.md` current. When a lab or platform phase is completed,
  update the **Completed labs** table and the **Platform lab** phase status (✅ Done /
  ⏭️ Next / Planned) in `README.md`, and the build order table in `platform/README.md`.
- Every platform phase gets simple, numbered build steps in `platform/README.md`
  (→ How to build each phase), saying where each step runs (Mac or utility server),
  plus a link to its detailed runbook. Keep "Rebuilding the platform from scratch" current.
- When a phase adds components, update the **MacBook requirements** table in
  `platform/README.md` (worker RAM and Mac disk) if the estimates change.
- Problems hit while building go into a Troubleshooting section (symptoms, cause, fix).
- New labs get their own folder with a `README.md` in the same style as the others
  (author line, requirements, usage, verification), and a row in the top-level README.
- Lab-only shortcuts (default passwords, long-lived certs, public repos) are fine but
  must be called out as lab-only in the README.
- Never commit generated credentials (`admin.conf`, join commands, `*.key`) — see `.gitignore`.
