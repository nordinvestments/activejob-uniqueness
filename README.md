# Job uniqueness for ActiveJob

> **Maintained fork of [veeqo/activejob-uniqueness](https://github.com/veeqo/activejob-uniqueness)**
>
> This gem is published as `activejob-uniqueness-2026` on RubyGems. The API is fully compatible with the original gem — just update your Gemfile.

[![Build Status](https://github.com/nordinvestments/activejob-uniqueness/actions/workflows/main.yml/badge.svg?branch=main)](https://github.com/nordinvestments/activejob-uniqueness/actions/workflows/main.yml) [![Gem Version](https://badge.fury.io/rb/activejob-uniqueness-2026.svg)](https://badge.fury.io/rb/activejob-uniqueness-2026)

## Requirements

| Dependency | Version |
|------------|---------|
| Ruby | >= 3.1 |
| Rails (ActiveJob) | >= 7.1, < 7.3 |
| Redis | >= 2.8 |

> **Note:** This fork targets modern Ruby and Rails versions. For older Ruby (2.5-3.0) or Rails (4.2-7.0) support, use the [original gem](https://github.com/veeqo/activejob-uniqueness).

## Overview

The gem allows to protect job uniqueness with next strategies:

| Strategy | The job is locked | The job is unlocked |
|-|-|-|
| `until_executing` | when **pushed** to the queue | when **processing starts** |
| `until_executed` | when **pushed** to the queue | when the job is **processed successfully** |
| `until_expired` | when **pushed** to the queue | when the lock is **expired** |
| `until_and_while_executing` | when **pushed** to the queue | when **processing starts**<br>a runtime lock is acquired to **prevent simultaneous jobs**<br>*has extra options: `runtime_lock_ttl`, `on_runtime_conflict`* |
| `while_executing` | when **processing starts** | when the job is **processed**<br>with any result including an error |

Inspired by [SidekiqUniqueJobs](https://github.com/mhenrixon/sidekiq-unique-jobs), uses [Redlock](https://github.com/leandromoreira/redlock-rb) under the hood.

<p align="center">
  <a href="https://www.veeqo.com/" title="Sponsored by Veeqo">
    <img src="https://static.veeqo.com/assets/sponsored_by_veeqo.png" width="360" />
  </a>
</p>

## Installation

Add the `activejob-uniqueness-2026` gem to your Gemfile.

```ruby
gem 'activejob-uniqueness-2026'
```

If you want jobs unlocking for Sidekiq Web UI, require the patch explicitly. [**Queues cleanup becomes slower!**](#sidekiq-api-support)
```ruby
gem 'activejob-uniqueness-2026', require: 'active_job/uniqueness/sidekiq_patch'
```

And run `bundle install` command.

### Migrating from `activejob-uniqueness`

If you're switching from the original gem, simply replace in your Gemfile:

```ruby
# Before
gem 'activejob-uniqueness'

# After
gem 'activejob-uniqueness-2026'
```

No code changes required — the `ActiveJob::Uniqueness` module namespace is unchanged.

## Configuration

ActiveJob::Uniqueness is ready to work without any configuration. It will use `REDIS_URL` to connect to Redis instance.
To override the defaults, create an initializer `config/initializers/active_job_uniqueness.rb` using the following command:

```sh
rails generate active_job:uniqueness:install
```

This gem relies on `redlock` for it's Redis connection, that means **it will not inherit global configuration of `Sidekiq`**. To configure the connection, you can use `config.redlock_servers`, for example to disable SSL verification for Redis/Key-Value cloud providers:

```ruby
ActiveJob::Uniqueness.configure do |config|
  config.redlock_servers = [
    RedisClient.new(
      url: ENV['REDIS_URL'],
      ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE }
    )
  ]
end
```

## Usage


### Make the job to be unique

```ruby
class MyJob < ActiveJob::Base
  # new jobs with the same args will raise error until existing one is executed
  unique :until_executed

  def perform(args)
    # work
  end
end
```

### Tune uniqueness settings per job

```ruby
class MyJob < ActiveJob::Base
  # new jobs with the same args will be logged within 3 hours or until existing one is being executing
  unique :until_executing, lock_ttl: 3.hours, on_conflict: :log

  def perform(args)
    # work
  end
end
```

You can set defaults globally with [the configuration](#configuration)

### Control lock conflicts

```ruby
class MyJob < ActiveJob::Base
  # Proc gets the job instance including its arguments
  unique :until_executing, on_conflict: ->(job) { job.logger.info "Oops: #{job.arguments}" }

  def perform(args)
    # work
  end
end
```

### Control redis connection errors

```ruby
class MyJob < ActiveJob::Base
  # Proc gets the job instance including its arguments, and as keyword arguments the resource(lock key) `resource` and the original error `error`
  unique :until_executing, on_redis_connection_error: ->(job, resource: _, error: _) { job.logger.info "Oops: #{job.arguments}" }

  def perform(args)
    # work
  end
end
```

### Control lock key arguments

```ruby
class MyJob < ActiveJob::Base
  unique :until_executed

  def perform(foo, bar, baz)
    # work
  end

  def lock_key_arguments
    arguments.first(2) # baz is ignored
  end
end
```

### Control the lock key

```ruby
class MyJob < ActiveJob::Base
  unique :until_executed

  def perform(foo, bar, baz)
    # work
  end

  def lock_key
    'qux' # completely custom lock key
  end

  def runtime_lock_key
    'quux' # completely custom runtime lock key for :until_and_while_executing
  end
end
```

### Unlock jobs manually

The selected strategy automatically unlocks jobs, but in some cases (e.g. the queue is purged) it is handy to unlock jobs manually.

```ruby
# Remove the lock for particular arguments:
MyJob.unlock!(foo: 'bar')
# or
ActiveJob::Uniqueness.unlock!(job_class_name: 'MyJob', arguments: [{foo: 'bar'}])

# Remove all locks of MyJob
MyJob.unlock!
# or
ActiveJob::Uniqueness.unlock!(job_class_name: 'MyJob')

# Remove all locks
ActiveJob::Uniqueness.unlock!
```

## Test mode

Most probably you don't want jobs to be locked in tests. Add this line to your test suite (`rails_helper.rb`):

```ruby
ActiveJob::Uniqueness.test_mode!
```

## Logging

ActiveJob::Uniqueness instruments `ActiveSupport::Notifications` with next events:
* `lock.active_job_uniqueness`
* `runtime_lock.active_job_uniqueness`
* `unlock.active_job_uniqueness`
* `runtime_unlock.active_job_uniqueness`
* `conflict.active_job_uniqueness`
* `runtime_conflict.active_job_uniqueness`

And then writes to `ActiveJob::Base.logger`.

**ActiveJob prior to version `6.1` will always log `Enqueued MyJob (Job ID) ...` even if the callback chain is halted. [Details](https://github.com/rails/rails/pull/37830)**

## Testing

Run redis server (in separate console):
```
docker run --rm -p 6379:6379 redis
```

Run tests with:

```sh
bundle
rake
```

## Sidekiq API support

ActiveJob::Uniqueness supports Sidekiq API to unset job locks on queues cleanup (e.g. via Sidekiq Web UI). Starting Sidekiq 5.1 job death also triggers locks cleanup.
Take into account that **[big queues cleanup becomes much slower](https://github.com/nordinvestments/activejob-uniqueness/issues/16)** because each job is being unlocked individually. In order to activate Sidekiq API patch require it explicitly in your Gemfile:

```ruby
gem 'activejob-uniqueness-2026', require: 'active_job/uniqueness/sidekiq_patch'
```

## Why this fork?

The [original gem](https://github.com/veeqo/activejob-uniqueness) by Veeqo is excellent, but maintenance has slowed. This fork aims to:

- Keep up with new Rails and Ruby versions
- Merge useful PRs from the community
- Provide timely security updates
- Maintain backwards compatibility

We're grateful to the original authors and contributors. This fork preserves the MIT license and full attribution.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/nordinvestments/activejob-uniqueness.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

Originally created by [Veeqo](https://www.veeqo.com). Maintained by [Nord Investments](https://github.com/nordinvestments).
