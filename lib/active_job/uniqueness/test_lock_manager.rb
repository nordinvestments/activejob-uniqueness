# frozen_string_literal: true

module ActiveJob
  module Uniqueness
    # Mocks the full public API of ActiveJob::Uniqueness::LockManager so that
    # enabling ActiveJob::Uniqueness.test_mode! never raises NoMethodError for a
    # method the real manager (a Redlock::Client subclass) responds to.
    #
    # Return values are consistent with "no lock is ever actually held": locking
    # always succeeds, nothing is ever locked, and TTL lookups are nil.
    #
    # See ActiveJob::Uniqueness.test_mode!
    class TestLockManager
      def lock(*_args)
        block_given? ? yield(true) : true
      end

      def lock!(*args, &block)
        return lock(*args, &block) if block

        true
      end

      def unlock(*_args)
        nil
      end

      def locked?(*_args)
        false
      end

      def valid_lock?(*_args)
        false
      end

      def get_remaining_ttl_for_lock(*_args)
        nil
      end

      def get_remaining_ttl_for_resource(*_args)
        nil
      end

      def delete_lock(*_args)
        true
      end

      def delete_locks(*_args)
        true
      end
    end
  end
end
