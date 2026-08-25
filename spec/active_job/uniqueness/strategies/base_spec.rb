# frozen_string_literal: true

describe ActiveJob::Uniqueness::Strategies::Base do
  describe '.locks_on_enqueue?' do
    it 'is true for built-in strategies that lock on enqueue', :aggregate_failures do
      expect(ActiveJob::Uniqueness::Strategies::UntilExecuting.locks_on_enqueue?).to be(true)
      expect(ActiveJob::Uniqueness::Strategies::UntilExecuted.locks_on_enqueue?).to be(true)
      expect(ActiveJob::Uniqueness::Strategies::UntilExpired.locks_on_enqueue?).to be(true)
      expect(ActiveJob::Uniqueness::Strategies::UntilAndWhileExecuting.locks_on_enqueue?).to be(true)
    end

    it 'is false for :while_executing, whose #lock_key is a runtime guard' do
      expect(ActiveJob::Uniqueness::Strategies::WhileExecuting.locks_on_enqueue?).to be(false)
    end

    it 'lets a custom strategy that locks on enqueue by other means opt in' do
      custom_strategy = Class.new(described_class) do
        def before_enqueue
          lock(resource: lock_key, ttl: lock_ttl)
        end

        def self.locks_on_enqueue?
          true
        end
      end

      expect(custom_strategy.locks_on_enqueue?).to be(true)
    end
  end
end
