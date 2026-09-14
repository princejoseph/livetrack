# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t livetrack .
# docker run -d -p 80:80 -e RAILS_MASTER_KEY=<value from config/master.key> --name livetrack livetrack

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=3.4.9
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app lives here
WORKDIR /rails

# Install base packages
# git is in this list on purpose. Bundler re-derives the spec of every
# git-sourced gem (Hyperstack, here) on *every* process boot, not just during
# bundle install, and that needs the git binary plus each gem's .git directory
# present at runtime -- see the matching note on the cleanup below.
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl git libjemalloc2 libvips sqlite3 && \
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
    apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY vendor/* ./vendor/
COPY Gemfile Gemfile.lock ./
# NOTE: the generated Dockerfile also deletes
# "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git here. That is fatal for this app.
# Bundler::Source::Git#load_gemspec re-derives each git-sourced gem's spec on
# every boot (bundler/setup -> Definition#materialize -> Source::Git#specs), so
# without those .git dirs the process dies before Rails loads with
# "Invalid gemspec ...: No such file or directory - git" followed by
# "NoMethodError: undefined method 'name' for nil". All eight Hyperstack gems
# come from git, so keep them.
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache && \
    bundle exec bootsnap precompile --gemfile

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times
RUN bundle exec bootsnap precompile app/ lib/

# Compile the Opal/Sprockets bundle. sprockets-rails sets
# config.assets.compile = false in production, so without this the app boots
# but every page 500s on a missing application.js. SECRET_KEY_BASE_DUMMY lets
# this run without the real master key at build time.
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile


# Final stage for app image
FROM base

# Copy built artifacts: gems, application
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

# Run and own only the runtime files as a non-root user for security.
#
# safe.directory is required, not optional: the git-sourced gem checkouts kept
# above are owned by root, and Bundler shells out to git against them on every
# boot as uid 1000. Without this, git refuses with "detected dubious ownership"
# and the boot fails. --system so it applies to the rails user.
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    git config --system --add safe.directory '*' && \
    chown -R rails:rails db log storage tmp
USER 1000:1000

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
