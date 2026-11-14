### Added

- **Newer versions of a pinned Docker image**: for a tag like `redis:7.0.11`, Elio reads the tags of the repository and shows the last fix of its series (`7.0.15 available`, an update to make: Docker state, notification) and the newest version of its major (`newest 7.x: 7.4.12`, for information). Tags of the same shape only (`3.11.4-slim-bookworm` with `3.11.x-slim-bookworm`), never a pre-release nor a new major. Before, only a tag published again (same name, new digest) was seen.

### Upgrading

- One migration (two columns of `image_updates`), run on start as usual. Elio now also lists the tags of the repositories of your images (`GET /v2/<image>/tags/list`, read-only) on the registries it already asks.
