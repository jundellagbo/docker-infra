# Release brief

Cut a release unless that version already exists — the repo's tags, releases and
commits since the last one are under "Scope" below, so read them first. Already
released? Show the existing tag/release and stop; don't duplicate or move it.

Otherwise: read the commits since the previous tag, because the notes come from
what actually changed rather than from the task description. Run `infra-llm
--verify` and confirm it passes — never tag a red tree. Suggest a version if none
was given and bump it everywhere this project declares it (the scope lists the
candidates). Tags are `vMAJOR.MINOR.PATCH`: `v1.0.1` bug fix, `v1.1.0` feature,
`v2.0.0` breaking — let the commits decide, and one breaking change makes it
major. Call out security fixes and dependency updates (the scope flags which
manifests changed) with their severity and whether installs must upgrade now, or
say there were none.

Then do it rather than handing commands back: running this command opened a short
window in which commit, push and tag are allowed, because asking for a release is
asking for those. Commit the version bump, cut the release with `gh release
create` (it creates and pushes the tag), and report the URL. Destructive git
stays blocked — no force push, no moving an existing tag, no history rewriting;
if you think one is needed, stop and say so. No AI/LLM attribution in the tag,
notes or commits.

Group the release notes by what changed for the user, not by commit order:
**Security** (fixes and dependency updates, or "none"), **Highlights**, **Bug
fixes**, **Breaking changes** (say "none" explicitly), **Migration notes** (what
an existing install must do), and a **Deployment checklist** of checks, artifacts
and data steps.
