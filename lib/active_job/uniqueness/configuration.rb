# frozen_string_literal: true

module ActiveJob
  module Uniqueness
    # Use /config/initializer/activejob_uniqueness.rb to configure ActiveJob::Uniqueness
    #
    # ActiveJob::Uniqueness.configure do |c|
    #   c.lock_ttl = 3.hours
    # end
    #
    class Configuration
      class_attribute :lock_ttl, default: 86_400 # 1.day
      class_attribute :lock_prefix, default: 'activejob_uniqueness'
      class_attribute :_on_conflict, default: :raise
      class_attribute :_on_redis_connection_error, default: :raise
      class_attribute :redlock_servers, default: [ENV.fetch('REDIS_URL', 'redis://localhost:6379')]
      class_attribute :redlock_options, default: { retry_count: 0 }
      class_attribute :lock_strategies, default: {}
      class_attribute :digest_method

      def on_conflict
        _on_conflict
      end

      def on_conflict=(action)
        validate_on_conflict_action!(action)

        self._on_conflict = action
      end

      def on_redis_connection_error
        _on_redis_connection_error
      end

      def on_redis_connection_error=(action)
        validate_on_redis_connection_error!(action)

        self._on_redis_connection_error = action
      end

      def validate_on_conflict_action!(action)
        return if action.nil? || %i[log raise].include?(action) || action.respond_to?(:call)

        raise ActiveJob::Uniqueness::InvalidOnConflictAction, "Unexpected '#{action}' action on conflict"
      end

      def validate_on_redis_connection_error!(action)
        return if action.nil? || action == :raise || action.respond_to?(:call)

        raise ActiveJob::Uniqueness::InvalidOnConflictAction, "Unexpected '#{action}' action on_redis_connection_error"
      end
    end
  end
end

# Set default digest_method after class is defined
ActiveJob::Uniqueness::Configuration.digest_method = begin
  require 'openssl'
  OpenSSL::Digest::MD5
end
