# Future Codex Sessions: Image Build Workflows

This repo builds Meticulous machine images with GitHub Actions. Image builds now use the workflow branch as the selected image/config channel:

- `github.ref_name`: selected branch and image name for `.github/workflows/build-nightly-image.yml`.
- `image`: internal reusable-workflow input; passed as `github.ref_name`.
- `machine-ref`: internal reusable-workflow input that selects this repo branch for machine config, scripts, services, RAUC config, and workflow implementation; passed as `github.ref_name`.

## Branch Model

- `nightly`, `beta`, and `stable` are branch-backed machine config channels and image names.
- `main` remains the central changelog and GitHub Pages branch, but it is no longer the manual image launcher.
- Manual image builds are dispatched from the branch to build. The branch name must be the image name.
- Custom images such as `factory`, `rel`, and certification images require their own branch with the same name as the image and a matching `images/<image>.versions.sh`.
- Scheduled builds assume the repository default branch is `nightly`, because GitHub Actions schedules run from the default branch.
- Manual builds can set only `no-cache` and `skip_emmc_upload_to_hawkbit`.

## Workflow Roles

- `.github/workflows/build-nightly-image.yml` is the user-facing image build workflow on each build branch.
- `.github/workflows/build-nightly-image.yml` passes `github.ref_name` directly to `.github/workflows/build-image-channel.yml` through a local reusable workflow call.
- `.github/workflows/build-image-channel.yml` contains the real image build and accepts `image`, `machine-ref`, `no-cache`, and `skip_emmc_upload_to_hawkbit`.
- `.github/workflows/build-all-components.yml` calls `.github/workflows/build-component.yml` by local reusable workflow path so the channel branch supplies the component workflow implementation.
- All checkouts of this repository inside the image build path must use `machine-ref`. Private repo checkouts, such as `rauc-secrets`, are separate and should not use `machine-ref`.
- Component builds receive `machine-ref` through `build-all-components.yml` and `build-component.yml`; `build-component.yml` falls back to `github.ref_name` only for direct/manual component runs.

## Image Validation

- Image names must match `[A-Za-z0-9._-]+`.
- Machine refs must match `[A-Za-z0-9._-]+`; branch names with slashes are intentionally rejected by the image build path.
- `nightly` does not require `images/nightly.versions.sh`; it uses `config.sh`.
- Any non-nightly image must have `images/<image>.versions.sh` on the selected `machine-ref` branch.

## Changelog Behavior

- Changelog files are committed only to `main`, under `images/changes/<image>/`.
- The channel workflow fetches `images/changes` from `origin/main` before running `generate-build-info.sh`; otherwise channel branches would compare against stale changelog history.
- The channel workflow uploads a `version-info` artifact containing `components/repo-info/` and `images/changes/`.
- The branch workflow downloads `version-info`, commits only `images/changes/<image>/` to `main`, then calls `.github/workflows/deploy-changelog.yml@main`.
- `.github/workflows/deploy-changelog.yml` explicitly checks out `main` before generating GitHub Pages.

## Build Tags

- After the full image build succeeds, `.github/workflows/build-nightly-image.yml` checks out component sources again and runs `tag-controlled-repos.sh --tag "<image>/<BUILD_VERSION_NUMBER>"`.
- Controlled component repos are URLs matching `github.com[:/]MeticulousHome/`; external repos are skipped.
- Build tags are lightweight tags pushed to each controlled component repo remote.
- Existing remote tags are safe only if they already point to the same commit; if a remote tag points elsewhere, tagging fails.
- Build tags are never force-updated.

## Component Branch Promotion

- Controlled component repos are URLs matching `github.com[:/]MeticulousHome/`.
- Controlled component defaults in `config.sh` use `nightly` branches at `HEAD`; external repos keep their upstream branches and pinned revisions.
- `pin_version.yml` promotes component branches only for `nightly -> beta` and `beta -> stable`.
- Direct `nightly -> stable` promotion is forbidden.
- Branch promotion uses `pin-versions.sh --promote <source> <destination>` after `update-sources.sh --image <source>` checks out the source component refs.
- During channel promotion, controlled component repo destination branches are pushed with `--force-with-lease`, and `images/<destination>.versions.sh` records `*_BRANCH=<destination>` plus exact promoted `*_REV=<sha>` pins.
- Custom destination images are file-only pins. They write exact SHAs to `images/<custom>.versions.sh` and do not push or record custom component branches.

## Important Constraints

- Remote build branches must include `.github/workflows/build-nightly-image.yml`, `.github/workflows/build-image-channel.yml`, `.github/workflows/build-all-components.yml`, and `.github/workflows/build-component.yml`.
- If a custom image branch is added, add or update `images/<custom>.versions.sh` on that branch.
- `GH_REPO_WORKFLOW` must be able to push tags to controlled component repos for build tagging to succeed.
