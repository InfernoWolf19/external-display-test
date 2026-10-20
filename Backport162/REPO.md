# Sileo / Zebra repository (GitHub Pages)

URL: `https://infernowolf19.github.io/external-display-test/` (one tap: `sileo://source/https://infernowolf19.github.io/external-display-test/`, also linked from the page itself).

How it works: every successful CI build of `claude/backport162` runs the `publish` job of `.github/workflows/build-backport162.yml`: `.github/scripts/publish-apt-repo.sh` -> `aptrepo.py` re-versions the build as `<control version>+<CI run number>.<short commit>` (e.g. `0.7.5+197.1ec6584`), appends `Build N, commit <sha>: <commit subject>` to the extended description, adds it to `debs/` on the `gh-pages` branch and regenerates `Packages`, `Packages.gz`, `Packages.bz2`, `Release`, `index.html` (history table with commit links) and `history.json`. All versions stay in `Packages` (the newest 60 are kept), so Sileo lists them when you long-press Get / Modify and choose a version; the newest one is the update candidate.

One-time setup (repository settings, cannot be done from CI): Settings -> Pages -> Build and deployment -> Source: *Deploy from a branch* -> Branch `gh-pages`, folder `/ (root)`.

Version history of builds made before the repo existed: run the workflow once by hand (Actions -> Build Backport162 -> Run workflow on `claude/backport162`, tick *backfill*): the previous successful builds whose artifacts still exist (CI keeps them 90 days) are added with their own run number / commit.

Notes: the version order is `base+run.sha`; raise `Version:` in `control` when a new release line starts. Install after a reboot of userspace (backboardd part).
