# syntax=docker/dockerfile:1

# ---- Builder: toolchain + gems + assets ----
FROM ruby:4.0.0-slim AS builder

ENV LANG=C.UTF-8 \
    BUNDLE_PATH=vendor/bundle \
    BUNDLE_WITHOUT=development:test \
    BUNDLE_DEPLOYMENT=1 \
    RAILS_ENV=production

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
      build-essential git libpq-dev libyaml-dev libicu-dev pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Node 22 toolchain for Shakapacker asset compilation (build stage only).
COPY --from=node:22.14.0-slim /usr/local /usr/local

# Gemfile.lock is locked to Bundler 4.0.19.
RUN gem install bundler -v 4.0.19

WORKDIR /app

# Gemfile layer first for docker-layer caching.
COPY Gemfile Gemfile.lock ./
# The engine gem lives in a private repo; the token is injected as a BuildKit
# secret mount (not a build arg) and never persisted to any layer.
RUN --mount=type=secret,id=github_token,required=true \
    printf '[url "https://x-access-token:%s@github.com/"]\n\tinsteadOf = https://github.com/\n' "$(cat /run/secrets/github_token)" > /tmp/gitconfig \
    && GIT_CONFIG_GLOBAL=/tmp/gitconfig bundle install \
    && rm -f /tmp/gitconfig \
    && rm -rf vendor/bundle/ruby/*/cache

COPY package.json package-lock.json ./
RUN npm ci

COPY . .

# Assets precompile must not bake any secret into the layer.
RUN SECRET_KEY_BASE_DUMMY=1 bundle exec rails assets:precompile \
    && rm -rf node_modules tmp/* log/*

# ---- Runtime: slim, non-root, no build tools ----
FROM ruby:4.0.0-slim AS runtime

ENV LANG=C.UTF-8 \
    RAILS_ENV=production \
    RAILS_LOG_TO_STDOUT=1 \
    BUNDLE_PATH=vendor/bundle \
    BUNDLE_WITHOUT=development:test \
    BUNDLE_DEPLOYMENT=1

RUN apt-get update -qq && apt-get install -y --no-install-recommends \
      libpq5 libjemalloc2 tzdata libicu72 imagemagick libvips42 \
    && rm -rf /var/lib/apt/lists/* \
    && gem install bundler -v 4.0.19 \
    && groupadd -r -g 1000 rails \
    && useradd --system -u 1000 -g rails -d /app -s /bin/bash rails

WORKDIR /app
COPY --from=builder --chown=rails:rails /app /app
RUN chown rails:rails /app \
    && mkdir -p tmp/pids log storage \
    && chown -R rails:rails tmp log storage

USER rails
ENV HOME=/app
EXPOSE 3000
ENTRYPOINT ["/app/bin/docker-entrypoint"]
CMD ["./bin/rails", "server"]
