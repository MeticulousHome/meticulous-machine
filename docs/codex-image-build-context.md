# Future Codex Sessions: Image Build Workflows

This repo builds Meticulous machine images with GitHub Actions. The image build uses two separate selectors:

- `image`: selects component pins from `images/<image>.versions.sh`; `nightly` is special and uses defaults from `config.sh`.
- `machine-ref`: internal reusable-workflow input that selects this repo branch for machine config, scripts, services, RAUC config, and workflow implementation.

## Branch Model

- `main` is the workflow launcher and central changelog branch.
- `nightly`, `beta`, and `stable` are branch-backed machine config channels.
- Custom images such as `factory`, `rel`, and certification images do not get their own branches in this model. They build from an explicitly selected config branch.
- The main launcher input is `config_branch`:
  - `auto` maps `nightly`, `beta`, and `stable` images to their matching branches.
  - custom images must choose `nightly`, `beta`, or `stable` explicitly.
- Scheduled builds run as `image=nightly`, `config_branch=auto`, `no-cache=false`, and `skip_emmc_upload_to_hawkbit=false`.
- Manual builds can set `image`, `config_branch`, `no-cache`, and `skip_emmc_upload_to_hawkbit`.

## Workflow Roles

- `.github/workflows/build-nightly-image.yml` is the user-facing launcher on `main`.
- `.github/workflows/build-nightly-image.yml` resolves inputs, then calls exactly one static branch workflow: `build-image-channel.yml@nightly`, `@beta`, or `@stable`.
- `.github/workflows/build-image-channel.yml` contains the real image build and accepts `image`, `machine-ref`, `no-cache`, and `skip_emmc_upload_to_hawkbit`.
- `.github/workflows/build-all-components.yml` calls `.github/workflows/build-component.yml` by local reusable workflow path so the channel branch supplies the component workflow implementation.
- All checkouts of this repository inside the image build path must use `machine-ref`. Private repo checkouts, such as `rauc-secrets`, are separate and should not use `machine-ref`.
- Component builds receive `machine-ref` through `build-all-components.yml` and `build-component.yml`; `build-component.yml` falls back to `github.ref_name` only for direct/manual component runs.

## Image Validation

- Image names must match `[A-Za-z0-9._-]+`.
- `nightly` does not require `images/nightly.versions.sh`; it uses `config.sh`.
- Any non-nightly image must have `images/<image>.versions.sh` on the selected `machine-ref` branch.
- A custom image with `config_branch=auto` fails early in the launcher before any reusable workflow is called.

## Changelog Behavior

- Changelog files are committed only to `main`, under `images/changes/<image>/`.
- The channel workflow fetches `images/changes` from `origin/main` before running `generate-build-info.sh`; otherwise channel branches would compare against stale changelog history.
- The channel workflow uploads a `version-info` artifact containing `components/repo-info/` and `images/changes/`.
- The main launcher downloads `version-info`, commits only `images/changes/<image>/` to `main`, then calls `.github/workflows/deploy-changelog.yml@main`.
- `.github/workflows/deploy-changelog.yml` explicitly checks out `main` before generating GitHub Pages.

## Component Branch Promotion

- Controlled component repos are URLs matching `github.com[:/]MeticulousHome/`.
- Controlled component defaults in `config.sh` use `nightly` branches at `HEAD`; external repos keep their upstream branches and pinned revisions.
- `pin_version.yml` promotes component branches only for `nightly -> beta` and `beta -> stable`.
- Direct `nightly -> stable` promotion is forbidden.
- Branch promotion uses `pin-versions.sh --promote <source> <destination>` after `update-sources.sh --image <source>` checks out the source component refs.
- During channel promotion, controlled component repo destination branches are pushed with `--force-with-lease`, and `images/<destination>.versions.sh` records `*_BRANCH=<destination>` plus exact promoted `*_REV=<sha>` pins.
- Custom destination images are file-only pins. They write exact SHAs to `images/<custom>.versions.sh` and do not push or record custom component branches.

## Important Constraints

- GitHub Actions reusable workflow refs are static in `jobs.<job_id>.uses`, so the launcher has one job per config branch instead of `@${{ inputs.config_branch }}`.
- Remote `nightly`, `beta`, and `stable` branches must exist and include `.github/workflows/build-image-channel.yml`, `.github/workflows/build-all-components.yml`, and `.github/workflows/build-component.yml`; otherwise the main launcher cannot call those branch workflows.
- If new machine config channels are added, update the launcher resolver, channel preflight, and static reusable workflow jobs together.
