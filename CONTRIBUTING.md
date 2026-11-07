# Contributing to Elio

Thanks for your interest! Issues, ideas and pull requests are welcome.

## Before you start

- **Bugs and ideas**: open an [issue](https://github.com/elio-fleet/elio/issues/new/choose). For a larger change, discuss it in an issue first.
- **Security issues**: never in a public issue, see [SECURITY.md](SECURITY.md).
- The interface is in **English and French** (see [Translating Elio](#translating-elio)); code, comments, commit messages and tests are in **English**.

## Running Elio locally

Requirements: Ruby (version in [`.ruby-version`](.ruby-version)), PostgreSQL, Chrome for the system tests.

```sh
bin/setup          # gems, database, then starts the app (bin/dev) on http://localhost:3000
```

The first visit creates the first (administrator) account. Background jobs (Solid Queue) run inside the web server in development.

To try Elio without any server, fill the development database with the fictitious fleet of the screenshots: `bin/rails dev:demo`, then sign in as `demo@example.test` / `password1234` (it refuses a database that already has servers; `FORCE=1` deletes them first).

To try Elio on real machines, add a server whose `~/.ssh/authorized_keys` holds Elio's public key (Settings → General). Disposable virtual machines or containers with `sshd` are ideal.

## Tests

Every change comes with its tests (Minitest): models, controllers (integration), services, jobs, and system tests for the interface.

```sh
bin/rails test            # unit and integration tests
bin/rails test:system     # browser tests (Chrome)
bin/ci                    # everything the CI runs: style, security audits, tests
```

Rules that keep Elio safe and readable:

- **Every command sent to a server is in [`config/ssh_commands.yml`](config/ssh_commands.yml)**, read-only unless it is one of the `keys.*` commands. Values are inserted with `@{name}` and always shell-escaped. A test fails if a command is sent from elsewhere.
- Parsers of command outputs are tested on **real outputs** recorded in `test/fixtures/files/`, anonymized (no real hostname, IP, customer name).
- No network access in the tests: external services (registries, vulnerability feeds, extensions) are stubbed or served by a local test server.
- Secrets are encrypted in the database (Active Record Encryption) and never sent back to the browser.

## Code layout

Models, controllers and jobs are grouped by domain (`app/models/fleet`, `access`, `security`, `operations`…; the folders are not namespaces). Inventory collectors live in `app/services/inventory/collectors`, one per category, with a pure Ruby parser.

## Translating Elio

Every text of the interface is in `config/locales/<language>/`, one file per domain of the application (`fleet.yml`, `inventory.yml`, `security.yml`, `access.yml`, `activity.yml`, `operations.yml`, `extensions.yml`, `settings.yml`, `accounts.yml`, `core.yml`), plus `rails.yml` (models, errors, formats) and `js.yml` (the texts of the JavaScript controllers). Views use relative keys (`t(".title")`, the key follows the path of the view); models and services use full keys.

**To add a language**, copy `config/locales/en/` to `config/locales/<code>/` (for example `de`), translate the values (not the keys), and set `elio.language_name` in `meta.yml` to the name of the language in that language. That's all: the languages are read from the folders, and the language appears in *My account* and *Settings → General*. Dates, numbers and Devise's texts come from `rails-i18n` and `devise-i18n`, which already know most languages.

`test/i18n/locale_files_test.rb` checks that every language has the same keys and `%{variables}` as English, and a missing translation fails the tests. Plural forms (`one`, `other`, and `few` / `many` where the language has them) follow the [CLDR rules](https://www.unicode.org/cldr/charts/latest/supplemental/language_plural_rules.html).

## Writing an extension

Extensions (Uptime Kuma, OVHcloud) bring what another tool knows next to each server. A new one:

- a class that inherits `Integrations::Base` in `app/services/integrations/`, registered in `Integration::REGISTRY`, with its `fields` (form of the settings, secrets encrypted), `test_connection`, `sync`, and the hooks it needs: `server_tabs` (partial `integrations/<key>/server_tab`), `sidebar_links`, `health_reasons`, `help_partial`;
- an automation (`Automation::KINDS`, with `integration:`) for its synchronization;
- **read-only**: requests go through `Integrations::Http`, which only knows `GET`; ask the user for a key with the fewest rights, and say so in the help;
- every alert optional (a setting each), activities declared in `Activity::KINDS` with their summary;
- tests on recorded and anonymized API answers (see `test/support/uptime_kuma_helpers.rb`, `ovh_helpers.rb`): no network in the tests.

## Pull requests

- One topic per pull request, with its tests; `bin/ci` green.
- [Conventional Commits](https://www.conventionalcommits.org/) (`feat(inventory): …`, `fix: …`), with a body that explains *why*.
- Describe your change in a new file of [`changelog.d/`](changelog.d/README.md) (not in `CHANGELOG.md` itself): `bin/changelog` shows what the next release notes will look like.

By contributing, you agree that your contribution is licensed under the [AGPL-3.0](LICENSE).
