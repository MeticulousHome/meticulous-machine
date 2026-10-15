# Future Codex Sessions: Image Build Workflows

This repo builds Meticulous machine images with GitHub Actions. Image builds now use the workflow branch as the selected image/config channel:

- `github.ref_name`: selected branch and image name for `.github/workflows/build-nightly-image.yml`.
- `image`: internal reusable-workflow input; passed as `github.ref_name`.
- `machine-ref`: internal reusable-workflow input that selects this repo branch for machine config, scripts, services, RAUC config, and workflow implementation; passed as `github.ref_name`.

## Branch Model

- `nightly`, `beta`, and `stable` are branch-backed machine config channels and image names.
- Any custom image branch, such as `factory`, `rel`, or a certification image, is also the image identifier for that build.
- `main` remains the central changelog and GitHub Pages branch, but it is no longer the manual image launcher.
- Manual image builds are dispatched from the branch to build. The branch name must be the image name.
- Custom images require their own branch with the same name as the image and a matching `images/<image>.versions.sh`.
- GitHub Actions schedules run from the default branch. A scheduled run on `nightly` builds directly; a scheduled run on any other branch (if `beta` or `stable` ever becomes the default) dispatches `build-nightly-image.yml` on `nightly` with `upload_emmc_to_hawkbit` and `skip-if-unchanged` set, and builds nothing itself.
- Manual builds can set only `no-cache`, `upload_emmc_to_hawkbit` and `skip-if-unchanged`.

## Workflow Roles

- `.github/workflows/build-nightly-image.yml` is the user-facing image build workflow on each build branch.
- `.github/workflows/build-nightly-image.yml` passes `github.ref_name` directly to `.github/workflows/build-image-channel.yml` through a local reusable workflow call.
- `.github/workflows/build-image-channel.yml` contains the real image build and accepts `image`, `machine-ref`, `no-cache`, `upload_emmc_to_hawkbit`, and `skip-if-unchanged`.
- `.github/workflows/build-all-components.yml` calls `.github/workflows/build-component.yml` by local reusable workflow path so the channel branch supplies the component workflow implementation.
- All checkouts of this repository inside the image build path must use `machine-ref`. Private repo checkouts, such as `rauc-secrets`, are separate and should not use `machine-ref`.
- Component builds receive `machine-ref` through `build-all-components.yml` and `build-component.yml`; `build-component.yml` falls back to `github.ref_name` only for direct/manual component runs.

## Unchanged-Image Skip

- `build-image-channel.yml` starts with a `fingerprint` job that checks out every component source and runs `scripts/image-fingerprint.sh <image>`.
- The fingerprint hashes this repo's commit, the URL, branch and checked-out commit of every repository declared in `config.sh` (overlaid by `images/<image>.versions.sh`) that `update-sources.sh` checked out, and the `InRelease` file of each Debian suite the rootfs upgrades against (`<distro>`, `-updates`, `-backports`, `-security`, and `trixie`). The suite list mirrors `debian-fika/create_rootfs.sh`; `make-rootfs.sh` runs `apt dist-upgrade`, so archive uploads change the image even when every component cache hits.
- There is no second list of repositories. `scripts/image-config.sh` discovers every `<NAME>_GIT` / `<NAME>_SRC_DIR` pair from `config.sh`, so adding or re-pointing a repository there is enough. A declared repository that is not checked out (the mobile app, the dashboard) is reported and left out.
- `scripts/component-cache-key.sh <component> <image>` keys each component build on the checked-out commits of its repositories, grouped the same way as the `update_<component>` functions in `update-sources.sh` (linux also covers mwifiex and mlanutl, bootloader covers ATF, imx-mkimage, the vendored `imx-boot-tools` and `rauc-config/u-boot.cmd`, rauc covers the hawkBit updater). Branch names are not part of the key, so a promotion that re-points a branch at the same commit keeps hitting the cache. `build-component.yml` uses the same script.
- `record-fingerprint` saves `image-fingerprint-<image>-<sha>` to actions/cache only after the deployment image was built and the hawkBit upload succeeded. A build without `upload_emmc_to_hawkbit`, or with a failed upload, leaves no fingerprint, so the next scheduled run builds and uploads it.
- When `skip-if-unchanged` is true and the fingerprint already exists, the `fingerprint` job sets `skip=true`, no component or image job runs, and the reusable workflow reports `skipped=true`; `build-nightly-image.yml` then skips tagging and the changelog commit too.
- `build-nightly-image.yml` enables `skip-if-unchanged` only on the `nightly` branch, for scheduled runs or when the dispatch input is checked. `beta`, `stable` and custom image branches always build, because those runs are requested by hand.
- If a Debian `InRelease` cannot be fetched, the fingerprint is made unique so the build proceeds rather than skipping on incomplete information.

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
- Changelog commit/deploy runs only when `upload_emmc_to_hawkbit` is true and the image build succeeds; if upload is disabled or the hawkBit upload fails, changelog publication is skipped.
- `.github/workflows/deploy-changelog.yml` explicitly checks out `main` before generating GitHub Pages.

## hawkBit Upload and Rollout Thresholds

- `deploy-emmc-bundle` runs `misc/hawkbit-upload.py`, which uploads the bundle, creates the rollout, and then pins that rollout's auto-resume thresholds. See `docs/hawkbit-rollout-thresholds.md`.
- The Rollout Manager lives in `MeticulousHome/hawkbit-docker-deployment` under `aux/rollout_manager/`; its contract is `docs/RolloutManagerContracts.md` in that repo.
- Its shipped default thresholds match `boot_smoke_version` and `post_update_shot_version` by regex, which accepts any well-formed version rather than the one being rolled out. The upload script rewrites those two matchers to `exact`.
- Both are pinned to `build_version_number`, which the script already receives as its `version` positional argument.
- The admin API is on the same host and port as hawkBit but outside `/rest/v1/`, at `/rollout-manager/`. nginx validates the `Authorization` header against hawkBit `/rest/v1/userinfo`, so `HAWKBIT_USER` and `HAWKBIT_PASSWORD` work unchanged.
- A failed threshold update does not abort the run. The remaining target filter setup still completes and the script exits non-zero, leaving the rollout on the default regex thresholds.

## Build Tags

- After the full image build succeeds, `.github/workflows/build-nightly-image.yml` checks out component sources again and runs `tag-controlled-repos.sh --tag "<image>/<BUILD_VERSION_NUMBER>"`.
- The tag is applied to this repo and to controlled component repos.
- Controlled component repos are URLs matching `github.com[:/]MeticulousHome/`; external repos are skipped.
- Build tags are lightweight tags pushed to this repo and each controlled component repo remote.
- Existing remote tags are safe only if they already point to the same commit; if a remote tag points elsewhere, tagging fails.
- Build tags are never force-updated.

## Component Branch Promotion

- `.github/workflows/pin_version.yml` keeps `image` as the destination image and `target_image` as the source image.
- Source image branches must already exist. Pinning from a non-existing source branch fails.
- If the destination image branch does not exist and the source image branch exists, the workflow creates the destination branch from the source branch before writing `images/<destination>.versions.sh`.
- If both source and destination image branches exist, the workflow checks out the destination branch and merges the source branch into it before pinning.
- Controlled component repos are URLs matching `github.com[:/]MeticulousHome/`.
- Controlled component defaults in `config.sh` use `nightly` branches at `HEAD`; external repos keep their upstream branches and pinned revisions.
- `pin_version.yml` promotes component branches only for `nightly -> beta` and `beta -> stable`.
- Direct `nightly -> stable` promotion is forbidden.
- Branch promotion uses `pin-versions.sh --promote <source> <destination>` after `update-sources.sh --image <source>` checks out the source component refs.
- During channel promotion, controlled component repo source commits are merged locally into the destination branch with `git merge --no-ff`.
- Destination branches are pushed with normal fast-forward pushes only after all controlled repo merges and version pins succeed.
- If the destination branch already contains the source commit, no merge commit is created and the current destination branch HEAD is pinned.
- `images/<destination>.versions.sh` records `*_BRANCH=<destination>` plus exact `*_REV=<destination HEAD sha>` pins for controlled repos.
- For `beta` and `stable`, existing `*_REV="HEAD"` entries in the destination versions file are preserved instead of being replaced with SHAs.
- Merge conflicts fail the workflow and the destination versions file is not replaced.
- The final push phase spans multiple repositories, so a network or permission failure during that phase can still require manual recovery.
- Custom destination images are file-only pins. They create or update `images/<custom>.versions.sh` and do not move component branches.

## Important Constraints

- Remote build branches must include `.github/workflows/build-nightly-image.yml`, `.github/workflows/build-image-channel.yml`, `.github/workflows/build-all-components.yml`, and `.github/workflows/build-component.yml`.
- If a custom image branch is added manually, add or update `images/<custom>.versions.sh` on that branch.
- If a custom image branch is created by `pin_version.yml`, the workflow writes `images/<custom>.versions.sh` on the newly created branch and pushes that branch to `origin`.
- `GH_ORG_WORKFLOW` must be able to push tags to this repo and controlled component repos for build tagging to succeed.
