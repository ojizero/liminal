# Releasing

The release workflow runs on pushes to `main`. It publishes only when `VERSION` changed in that push and is greater than the latest GitHub release tag.

## Repository configuration

The GitHub repository must provide:

- Variable `DOCKERHUB_USERNAME`
- Secret `DOCKERHUB_TOKEN`
- Environment `production`
- Workflow permission to publish GitHub Packages and releases

The workflow publishes:

- `<DOCKERHUB_USERNAME>/liminal:<version>` and `latest`
- `ghcr.io/<owner>/<repository>:<version>` and `latest`
- GitHub release and tag `v<version>`

## Release procedure

1. Ensure all intended commits use Conventional Commits.
2. Choose a version greater than the latest `v*` GitHub release and update `VERSION`.
3. Preview generated notes with `mise run changelog`.
4. Commit the bump as `chore(release): version X.Y.Z`.
5. Open a pull request and wait for commit, version, test, and lint checks.
6. Merge to `main`.
7. Verify that the Release workflow completed and both registries contain the versioned image.

The workflow tests before publishing, builds `linux/amd64` and `linux/arm64` images, pushes both registries, then creates the GitHub release.

Release notes include non-merge Conventional Commits since the previous lower `v*` tag. The release bump commit is excluded.

## Failure behavior

- An unchanged `VERSION` runs tests but does not publish.
- A version equal to the latest release does not publish.
- A version behind the latest release fails validation.
- Docker publication must succeed before the GitHub release is created.

Do not create the tag manually; the release task creates `v<version>`.
