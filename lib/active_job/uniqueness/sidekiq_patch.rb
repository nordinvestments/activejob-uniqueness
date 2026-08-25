# frozen_string_literal: true

require 'activejob/uniqueness'
require 'sidekiq/api'

module ActiveJob
  module Uniqueness
    SIDEKIQ_JOB_WRAPPERS = %w[
      ActiveJob::QueueAdapters::SidekiqAdapter::JobWrapper
      Sidekiq::ActiveJob::Wrapper
    ].freeze

    def self.unlock_sidekiq_job!(job_data)
      return unless SIDEKIQ_JOB_WRAPPERS.include?(job_data['class'])

      job = deserialize_sidekiq_job(job_data)

      return unless job&.class&.lock_strategy_class
      return unless locks_on_enqueue?(job)

      lock_key = enqueue_lock_key(job)
      return unless lock_key

      ActiveJob::Uniqueness.lock_manager.delete_lock(lock_key)
    end

    # Only strategies that lock on enqueue store an enqueue lock under #lock_key.
    # :while_executing does not lock on enqueue: its #lock_key holds the *runtime*
    # guard of a currently-executing instance, so cleaning up a queued duplicate
    # must not touch it. Strategies advertise this via #locks_on_enqueue?, which
    # custom strategies can override.
    def self.locks_on_enqueue?(job)
      job.class.lock_strategy_class.locks_on_enqueue?
    end
    private_class_method :locks_on_enqueue?

    def self.deserialize_sidekiq_job(job_data)
      serialized_job = job_data.fetch('args').first

      # ActiveJob only wraps a missing job class in UnknownJobClassError as of version 8.1
      return unless serialized_job.fetch('job_class').safe_constantize

      ActiveJob::Base.deserialize(serialized_job)
    end
    private_class_method :deserialize_sidekiq_job

    # Returns the enqueue lock key to release, or nil when it cannot be rebuilt.
    #
    # The key is rebuilt from the job's own #lock_key, so custom overrides are
    # honored (a class + arguments wildcard never matched them). ActiveJob does
    # not deserialize arguments until asked, so we trigger it explicitly: if a
    # referenced record no longer exists (e.g. a deleted GlobalID) it raises
    # DeserializationError and we skip the unlock, letting the lock expire by its
    # TTL. Rebuilding a key from an incomplete argument list and deleting it could
    # free another job's live lock, so skipping is the safe choice. Any other
    # error is a genuine bug (e.g. in a custom #lock_key) and is left to surface.
    def self.enqueue_lock_key(job)
      job.send(:deserialize_arguments_if_needed)
      job.lock_key
    rescue ActiveJob::DeserializationError
      nil
    end
    private_class_method :enqueue_lock_key

    module SidekiqPatch
      module SortedEntry
        def delete
          ActiveJob::Uniqueness.unlock_sidekiq_job!(item) if super
          item
        end
      end

      module ScheduledSet
        def delete(score, job_id)
          entry = find_job(job_id)
          ActiveJob::Uniqueness.unlock_sidekiq_job!(entry.item) if super
          entry
        end
      end

      module Job
        def delete
          ActiveJob::Uniqueness.unlock_sidekiq_job!(item)
          super
        end
      end

      module Queue
        def clear
          each(&:delete)
          super
        end
      end

      module JobSet
        def clear
          each(&:delete)
          super
        end

        def delete_by_value(name, value)
          ActiveJob::Uniqueness.unlock_sidekiq_job!(Sidekiq.load_json(value)) if super
        end
      end
    end
  end
end

Sidekiq::SortedEntry.prepend ActiveJob::Uniqueness::SidekiqPatch::SortedEntry
Sidekiq::ScheduledSet.prepend ActiveJob::Uniqueness::SidekiqPatch::ScheduledSet
Sidekiq::Queue.prepend ActiveJob::Uniqueness::SidekiqPatch::Queue
Sidekiq::JobSet.prepend ActiveJob::Uniqueness::SidekiqPatch::JobSet

sidekiq_version = Gem::Version.new(Sidekiq::VERSION)

# Sidekiq 6.2.2 renames Sidekiq::Job to Sidekiq::JobRecord
# https://github.com/mperham/sidekiq/issues/4955
if sidekiq_version >= Gem::Version.new('6.2.2')
  Sidekiq::JobRecord.prepend ActiveJob::Uniqueness::SidekiqPatch::Job
else
  Sidekiq::Job.prepend ActiveJob::Uniqueness::SidekiqPatch::Job
end

# Global death handlers are introduced in Sidekiq 5.1
# https://github.com/mperham/sidekiq/blob/e7acb124fbeb0bece0a7c3d657c39a9cc18d72c6/Changes.md#510
if sidekiq_version >= Gem::Version.new('7.0')
  Sidekiq.default_configuration.death_handlers << ->(job, _ex) { ActiveJob::Uniqueness.unlock_sidekiq_job!(job) }
elsif sidekiq_version >= Gem::Version.new('5.1')
  Sidekiq.death_handlers << ->(job, _ex) { ActiveJob::Uniqueness.unlock_sidekiq_job!(job) }
end
