.PHONY: build build-all up down test spec spec-all spec-matrix console shell redis-cli clean help

# Default Ruby version for the Docker image
RUBY_VERSION ?= 3.3

# Ruby versions to test (matching CI matrix)
RUBY_VERSIONS := 3.1 3.2 3.3 3.4

# Gemfiles to test (matching CI matrix)
GEMFILES := gemfiles/activejob_7.1.x.gemfile gemfiles/activejob_7.2.x.gemfile gemfiles/sidekiq_6.x.gemfile gemfiles/sidekiq_7.x.gemfile

# Build the Docker image for a specific Ruby version
# Usage: make build RUBY_VERSION=3.3
build:
	docker build --build-arg RUBY_VERSION=$(RUBY_VERSION) -t activejob-uniqueness:ruby-$(RUBY_VERSION) .

# Build Docker images for all Ruby versions
build-all:
	@for ruby in $(RUBY_VERSIONS); do \
		echo "Building image for Ruby $$ruby..."; \
		docker build --build-arg RUBY_VERSION=$$ruby -t activejob-uniqueness:ruby-$$ruby . ; \
	done

# Start services (Redis) in the background
up:
	docker compose up -d redis

# Stop all services
down:
	docker compose down

# Run the default rake task (specs + rubocop) - same as CI
test: up
	docker compose run --rm specs bundle exec rake

# Run specs only (without rubocop)
spec: up
	docker compose run --rm specs bundle exec rspec

# Run specific spec file(s)
# Usage: make spec-file FILE=spec/path/to_spec.rb
spec-file: up
	docker compose run --rm specs bundle exec rspec $(FILE)

# Run specs with a specific gemfile
# Usage: make spec-gemfile GEMFILE=gemfiles/activejob_7.1.x.gemfile
spec-gemfile: up
	docker compose run --rm -e BUNDLE_GEMFILE=$(GEMFILE) specs-appraisal

# Run specs for all gemfiles with current Ruby version
spec-all: up
	@echo "Running specs with ActiveJob 7.1.x..."
	docker compose run --rm -e BUNDLE_GEMFILE=gemfiles/activejob_7.1.x.gemfile specs-appraisal || true
	@echo ""
	@echo "Running specs with ActiveJob 7.2.x..."
	docker compose run --rm -e BUNDLE_GEMFILE=gemfiles/activejob_7.2.x.gemfile specs-appraisal || true
	@echo ""
	@echo "Running specs with Sidekiq 6.x..."
	docker compose run --rm -e BUNDLE_GEMFILE=gemfiles/sidekiq_6.x.gemfile specs-appraisal || true
	@echo ""
	@echo "Running specs with Sidekiq 7.x..."
	docker compose run --rm -e BUNDLE_GEMFILE=gemfiles/sidekiq_7.x.gemfile specs-appraisal || true

# Run the full CI matrix: all Ruby versions × all gemfiles
# This mirrors what GitHub Actions runs
spec-matrix: up build-all
	@echo "=============================================="
	@echo "Running full CI matrix locally"
	@echo "=============================================="
	@failed=0; \
	for ruby in $(RUBY_VERSIONS); do \
		for gemfile in $(GEMFILES); do \
			echo ""; \
			echo "----------------------------------------------"; \
			echo "Ruby $$ruby + $$gemfile"; \
			echo "----------------------------------------------"; \
			docker run --rm \
				--network activejob-uniqueness_default \
				-e REDIS_URL=redis://redis:6379 \
				-e BUNDLE_GEMFILE=$$gemfile \
				-v $(PWD):/app \
				-w /app \
				activejob-uniqueness:ruby-$$ruby \
				sh -c "bundle install --quiet && bundle exec rake" || failed=$$((failed + 1)); \
		done; \
	done; \
	echo ""; \
	echo "=============================================="; \
	if [ $$failed -gt 0 ]; then \
		echo "Matrix complete: $$failed job(s) failed"; \
		exit 1; \
	else \
		echo "Matrix complete: all jobs passed!"; \
	fi

# Open a Ruby console (IRB) in the container
console: up
	docker compose run --rm specs bundle exec irb -r ./lib/active_job/uniqueness

# Open a shell in the container
shell: up
	docker compose run --rm specs /bin/bash

# Open redis-cli
redis-cli: up
	docker compose exec redis redis-cli

# Run RuboCop
lint:
	docker compose run --rm specs bundle exec rubocop

# Run RuboCop with auto-correct
lint-fix:
	docker compose run --rm specs bundle exec rubocop -A

# Clean up Docker resources
clean:
	docker compose down -v --rmi local --remove-orphans

# Show help
help:
	@echo "Available targets:"
	@echo "  build        - Build Docker image for Ruby version (RUBY_VERSION=3.3)"
	@echo "  build-all    - Build Docker images for all Ruby versions"
	@echo "  up           - Start Redis service in the background"
	@echo "  down         - Stop all services"
	@echo "  test         - Run rake (specs + rubocop) - same as CI"
	@echo "  spec         - Run specs only (without rubocop)"
	@echo "  spec-file    - Run specific spec file (FILE=spec/path/to_spec.rb)"
	@echo "  spec-gemfile - Run specs with specific gemfile (GEMFILE=gemfiles/...)"
	@echo "  spec-all     - Run specs for all gemfiles (current Ruby)"
	@echo "  spec-matrix  - Run full CI matrix: all Ruby versions × all gemfiles"
	@echo "  console      - Open IRB console in container"
	@echo "  shell        - Open bash shell in container"
	@echo "  redis-cli    - Open redis-cli"
	@echo "  lint         - Run RuboCop"
	@echo "  lint-fix     - Run RuboCop with auto-correct"
	@echo "  clean        - Remove all Docker resources"
	@echo "  help         - Show this help message"
