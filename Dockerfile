# syntax=docker/dockerfile:1
ARG RUBY_VERSION=3.3
FROM ruby:${RUBY_VERSION}-slim

# Install dependencies
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    build-essential \
    git \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy gemspec and Gemfile first for better layer caching
COPY activejob-uniqueness-2026.gemspec Gemfile ./
COPY lib/active_job/uniqueness/version.rb ./lib/active_job/uniqueness/version.rb

# Install bundler and gems (don't use lock file to allow flexibility across Ruby versions)
# Pin to bundler 2.6.9 to avoid bundler 4.x compatibility issues
RUN gem install bundler -v '2.6.9' && bundle install --jobs 4

# Copy the rest of the application
COPY . .

# Default command
CMD ["bundle", "exec", "rspec"]
