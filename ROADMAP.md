### WordPress Azure Docker – Roadmap

This document tracks the improvements and release steps for `bluegrassdigital/wordpress-azure-sync`.

#### Legend
- [ ] To do
- [x] Done

### Now (ship next)
- [x] Update image names to Docker Hub repo
  - [x] Replace `yourdockerhub/wordpress-azure` with `bluegrassdigital/wordpress-azure-sync` in `docker-bake.hcl`
  - [x] Set `IMAGE_NAME: bluegrassdigital/wordpress-azure-sync` in `.github/workflows/docker.yml`
- [x] Confirm/adjust OCI labels in `Dockerfile`
  - [x] `org.opencontainers.image.source` → Docker Hub repo URL
  - [x] `org.opencontainers.image.vendor` → `Bluegrass Digital`
- [x] Add/verify `.dockerignore` to shrink build context (keep `.github/` included)
  - [x] Exclude `example/src/**`, `**/.git`, `**/.DS_Store`, `**/node_modules`, `**/.cache`, `**/vendor/*`
- [x] Tagging policy in CI
  - [x] Push `:8.3-latest`, `:8.4-latest` on every merge to `main`/`master`
  - [x] Only push `:8.x-stable` and full PHP version tags when `github.ref_type == tag`
  - [x] Add workflow trigger for tag pushes (e.g. `on: push: tags: ['v*']`)
- [x] Example Docker Compose
  - [x] Default to Hub image with commented instructions to build local dev image
  - [x] Remove auto-install; keep optional auto-activate
  - [x] Add snippet for manual `wp core install` (in `DEV.md`)
- [x] Documentation split
  - [x] Add `DEV.md` (local dev, WP-CLI, xdebug, file paths `/home` vs `/homelive`)
  - [x] Add `OPERATIONS.md` (Azure env vars, logs, New Relic, CI tags, upgrade policy)
  - [x] Update root `README.md` to link to both

### Next (hardening and automation)
- [x] CI security scan with Trivy after pushing images
- [x] Weekly scheduled rebuild workflow (to pick up base image CVEs)
- [ ] Smoke tests in CI: run container, `curl http://localhost`, `php -v`, `wp --version`
- [x] Dependabot/Renovate for GitHub Actions and base images
- [ ] Add `CHANGELOG.md`, confirm `LICENSE` contents, and add `CODEOWNERS`
- [ ] Define release process: cut git tag → publish `stable` + full PHP version tags
 - [x] Define release process: cut git tag → publish `stable` + full PHP version tags
 - [ ] Enhance release workflow: attach Trivy reports and link Docker image tags (`:8.x-stable`, `:<full-php-version>`, digests) in GitHub Release body

### Later (enhancements)
- [ ] Add PHP 8.5 targets when GA
- [ ] Consider dropping supervisor privileges per-program where possible
- [ ] Revisit Unison `repeat` vs `fsmonitor` once stable on target platforms
- [ ] Integration tests for example stack (MySQL + basic WP install scenario)
- [ ] Plugin improvements: async tailing via AJAX, settings screen for paths, basic health checks
- [ ] Azure App Service deployment guide with screenshots

### Operational Notes
- Image variants: `8.3`, `8.4`, plus `-dev` for developer tooling (composer, xdebug); multi-arch (amd64/arm64)
- Sync model: Azure `/home` ↔ `/homelive` via initial rsync + Unison; logs in `/home/LogFiles/sync`
- New Relic: best-effort install; enable with env vars; document opt-out


