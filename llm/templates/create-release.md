# Release brief

Cut a release — unless that version already exists. The repo's tags, releases
and commits since the last one are under "Scope" below; read them first.

**Already released?** Show the existing tag/release, don't duplicate or move it.

**Otherwise:**

1. Read the commits since the previous tag — the notes come from what actually
   changed, not from the task description.
2. Run `infra-llm --verify` and confirm it passes. Never tag a red tree.
3. Suggest a version if none was given, and bump it everywhere this project
   declares it — the scope lists the candidates. Tags are `vMAJOR.MINOR.PATCH`:

   | `v1.0.0` production | `v1.0.1` bug fix | `v1.1.0` feature | `v2.0.0` breaking |
   | ------------------- | ---------------- | ---------------- | ----------------- |

   Let the commits decide the bump: one breaking change makes it major.
4. Call out security fixes and dependency updates — the scope flags which
   manifests changed. Note severity and whether installs must upgrade now, or
   say there were none.
5. Do it — don't hand commands back. Running this command opened a short window
   in which commit, push and tag are allowed, because asking for a release is
   asking for those. Commit the version bump, then cut the release with
   `gh release create` (it creates and pushes the tag). Report the URL.
6. Destructive git stays blocked and always will be — no force push, no moving
   an existing tag, no history rewriting. If you think one is needed, stop and
   say so.
7. No AI/LLM attribution in the tag, notes or commits.

**Release notes** — grouped by what changed for the user, not by commit order:

- **Security** — fixes and dependency updates, or "none"
- **Highlights** · **Bug fixes** · **Breaking changes** (say "none" explicitly)
- **Migration notes** — what an existing install must do
- **Deployment checklist** — checks, artifacts and data steps
