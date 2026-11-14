# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t elio .
# docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value from config/master.key> --name elio elio

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=3.4.12
FROM docker.io/library/ruby:$RUBY_VERSION-slim-trixie AS base

# Rails app lives here
WORKDIR /rails

# Install base packages, with the security updates published since the base
# image was built (it is not rebuilt for each Debian fix). APT_REFRESH (a date
# in the CI, the run in a release) makes a cached build take them again.
ARG APT_REFRESH=none
RUN echo "packages of ${APT_REFRESH}" && apt-get update -qq && \
    apt-get upgrade -y --no-install-recommends && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips postgresql-client && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Set production environment
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libpq-dev libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY vendor/* ./vendor/
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times
RUN bundle exec bootsnap precompile app/ lib/

# Precompiling assets for production without requiring secret RAILS_MASTER_KEY.
# Then the Tailwind CSS executable (about 100 MB) goes: it only builds the
# stylesheet, now in public/assets. The runtime directories are given to the
# user that runs Elio here, as COPY --from keeps owners: a chown in the final
# stage would copy them (bootsnap's cache, about 80 MB) into one more layer.
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile && \
    rm -rf "${BUNDLE_PATH}"/ruby/*/gems/tailwindcss-ruby-*/exe/*/ && \
    chown -R 1000:1000 db log storage tmp

# Final stage for app image
FROM base

# Copy built artifacts: gems, application
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

# Run as a non-root user, that owns only the runtime files (db log storage tmp)
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash
USER 1000:1000

# Docker (and docker compose ps) shows whether Elio answers. Thruster listens
# on 80; /up answers without a database query nor a host check.
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --start-interval=2s --retries=3 \
  CMD curl -fsS -o /dev/null http://localhost/up || exit 1

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
