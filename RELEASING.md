### Releasing

This document defines how we ship images, manage tags, and write changelogs.

#### Image tags (summary)
- Moving tags (mutable): `:8.3-latest`, `:8.4-latest`, `:8.3-dev-latest`, `:8.4-dev-latest`, `:8.x-stable`
- Immutable (per build): `:8.3-stable-<YYYYMMDDHHMMSS>`, `:8.4-stable-<YYYYMMDDHHMMSS>`, `:8.3-dev-stable-<YYYYMMDDHHMMSS>`, `:8.4-dev-stable-<YYYYMMDDHHMMSS>`, and full PHP engine tags like `:8.3.11` (prod) and `:8.3.11-dev` (dev)
  - CI sets `BUILD_DATE=$(date +%Y%m%d%H%M%S)` to generate the `<YYYYMMDDHHMMSS>` suffix

Production consumers should use immutable per-build tags (or digests). Moving tags are for convenience/testing.

#### Cadence
- Weekly maintenance (automated): A scheduled CI job builds fresh images to pull in upstream security/OS/PHP updates
  - Expected outputs: new `:8.x-latest` and `:8.x-dev-latest` and new immutable `:8.x-stable-<YYYYMMDDHHMMSS>`/`-dev-stable-<YYYYMMDDHHMMSS>`
  - Policy: keep a moving `:8.x-stable` pointing to the latest weekly build for each supported minor version
    - Result: there is always a stable tag available that reflects the most recent weekly build

- Feature release (manual): When notable changes land (features, hardening), cut a repository tag (e.g., `v2025.08.21` or `v1.2.0`)
  - Expected outputs: multi-arch images, update `:8.x-stable`, and create the full PHP engine version tags `:<full-php-version>` and `:<full-php-version>-dev`
  - Also publish a GitHub Release with the changelog section for that tag

Note: Production users should still pin to immutable tags even though `:8.x-stable` is maintained; stable remains a moving tag.

#### Changelogs
- Source of truth: `CHANGELOG.md` in the repo root
- Workflow:
  1) Keep an `Unreleased` section up to date during development
  2) On feature release, move items from `Unreleased` to a new dated/semver section and commit
  3) Create a Git tag for the release and publish a GitHub Release using the same notes

#### Tagging procedures
- Weekly maintenance (automated by CI):
  - CI builds both prod and dev images for each PHP minor (e.g., 8.3, 8.4)
  - CI publishes `:8.x-latest`/`:8.x-dev-latest` and date-stamped tags `:8.x-stable-<YYYYMMDDHHMMSS>`/`-dev-stable-<YYYYMMDDHHMMSS>`
  - CI updates `:8.x-stable` to point to the latest weekly build for each minor

- Feature release (manual):
  1) Update `CHANGELOG.md` moving `Unreleased` to a new section
  2) Tag the repo: `git tag -a vYYYY.MM.DD -m "Release vYYYY.MM.DD" && git push --tags`
  3) CI builds multi-arch images, updates `:8.x-stable`, and creates full PHP version tags `:<full-php-version>` and `:<full-php-version>-dev`
  4) Publish a GitHub Release using the changelog section

#### Rollback guidance
- Prefer switching production to a previously validated immutable tag `:8.x-stable-<YYYYMMDDHHMMSS>` (or a pinned digest)
- Avoid relying on moving tags (`:latest`, `:stable`) for rollbacks

#### Notes
- `:8.x-stable` is convenient for non-production environments and for consumers that want a maintained moving tag; it should not be used where strict immutability is required
- CI includes vulnerability scanning (Trivy). Security posture is primarily maintained via weekly rebuilds + upstream patches.


