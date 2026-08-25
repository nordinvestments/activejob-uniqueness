# frozen_string_literal: true

describe 'Sidekiq patch', :sidekiq, type: :integration do
  shared_examples_for 'locks release' do
    let(:sidekiq_worker) { stub_sidekiq_class }

    after { Sidekiq::Queue.all.each(&:clear) }

    context 'when queue adapter is Sidekiq', active_job_adapter: :sidekiq do
      context 'when job class has unique strategy enabled' do
        let!(:activejob_worker) do
          stub_active_job_class do
            unique :until_executed
          end
        end

        it 'releases the lock' do
          expect { subject }.to change { locks(job_class_name: activejob_worker.name).count }.by(-1)
        end
      end

      context 'when job class has custom lock key arguments' do
        let!(:activejob_worker) do
          stub_active_job_class do
            unique :until_executed

            def lock_key_arguments
              [arguments.first]
            end
          end
        end

        it 'releases the lock' do
          expect { subject }.to change { locks(job_class_name: activejob_worker.name).count }.by(-1)
        end
      end

      context 'when job class has no unique strategy enabled' do
        let!(:activejob_worker) do
          stub_active_job_class
        end

        include_examples 'no unlock attempts'
      end
    end

    context 'when queue adapter is not Sidekiq', active_job_adapter: :test do
      context 'when job class has unique strategy enabled' do
        let!(:activejob_worker) do
          stub_active_job_class do
            unique :until_executed
          end
        end

        include_examples 'no unlock attempts'
      end
    end
  end

  shared_examples_for 'locks preserved when moved' do
    it 'preserves the lock' do
      expect { move_job }.not_to change { locks(job_class_name: activejob_worker.name).count }.from(1)
    end

    it 'prevents a duplicate enqueue' do
      move_job

      expect do
        activejob_worker.perform_later(:lock_argument, :ignored_argument)
      end.to raise_error(ActiveJob::Uniqueness::JobNotUnique)
    end
  end

  describe 'scheduled set item delete' do
    subject { Sidekiq::ScheduledSet.new.each(&:delete) }

    before do
      Sidekiq::ScheduledSet.new.clear
      sidekiq_worker.perform_in(3.minutes, 123)
      activejob_worker.set(wait: 3.minutes).perform_later(:lock_argument, :ignored_argument)
    end

    include_examples 'locks release'
  end

  describe 'scheduled set item add_to_queue', active_job_adapter: :sidekiq do
    subject(:move_job) { scheduled_entry.add_to_queue }

    before do
      Sidekiq::ScheduledSet.new.clear
      Sidekiq::Queue.new('default').clear
      activejob_worker.set(wait: 3.minutes).perform_later(:lock_argument, :ignored_argument)
    end

    after do
      Sidekiq::ScheduledSet.new.clear
      Sidekiq::Queue.new('default').clear
    end

    let(:scheduled_entry) { Sidekiq::ScheduledSet.new.first }
    let!(:activejob_worker) do
      stub_active_job_class('ScheduledJob') do
        unique :until_executed
      end
    end

    include_examples 'locks preserved when moved'
  end

  describe 'retry set item retry', active_job_adapter: :sidekiq do
    subject(:move_job) { Sidekiq::RetrySet.new.first.retry }

    before do
      Sidekiq::ScheduledSet.new.clear
      Sidekiq::RetrySet.new.clear
      Sidekiq::Queue.new('default').clear
      activejob_worker.set(wait: 3.minutes).perform_later(:lock_argument, :ignored_argument)

      scheduled_entry = Sidekiq::ScheduledSet.new.first
      Sidekiq::RetrySet.new.schedule(3.minutes.from_now, scheduled_entry.item.merge('retry_count' => 1))
    end

    after do
      Sidekiq::ScheduledSet.new.clear
      Sidekiq::RetrySet.new.clear
      Sidekiq::Queue.new('default').clear
    end

    let!(:activejob_worker) do
      stub_active_job_class('RetryJob') do
        unique :until_executed
      end
    end

    include_examples 'locks preserved when moved'
  end

  describe 'scheduled set clear' do
    subject { Sidekiq::ScheduledSet.new.clear }

    before do
      Sidekiq::ScheduledSet.new.clear
      sidekiq_worker.perform_in(3.minutes, 123)
      activejob_worker.set(wait: 3.minutes).perform_later(:lock_argument, :ignored_argument)
    end

    include_examples 'locks release'
  end

  describe 'job delete' do
    subject { Sidekiq::Queue.new('default').each(&:delete) }

    before do
      Sidekiq::Queue.new('default').clear
      sidekiq_worker.perform_async(123)
      activejob_worker.perform_later(:lock_argument, :ignored_argument)
    end

    include_examples 'locks release'
  end

  describe 'queue clear' do
    subject { Sidekiq::Queue.new('default').clear }

    before do
      Sidekiq::Queue.new('default').clear
      sidekiq_worker.perform_async(123)
      activejob_worker.perform_later(:lock_argument, :ignored_argument)
    end

    include_examples 'locks release'
  end

  context 'when the ActiveJob class no longer exists', active_job_adapter: :sidekiq do
    let(:queue) { Sidekiq::Queue.new('default') }
    let!(:activejob_worker) do
      stub_active_job_class('RemovedJob') do
        unique :until_executed
      end
    end

    before do
      queue.clear
      activejob_worker.perform_later(:lock_argument, :ignored_argument)
      hide_const(activejob_worker.name)
    end

    after do
      stub_const(activejob_worker.name, activejob_worker)
      queue.clear
      ActiveJob::Uniqueness.unlock!(
        job_class_name: activejob_worker.name,
        arguments: %i[lock_argument ignored_argument]
      )
    end

    describe 'job delete' do
      subject(:delete_job) { queue.first.delete }

      it 'deletes the job' do
        expect { delete_job }.to change(queue, :size).from(1).to(0)
      end
    end

    describe 'queue clear' do
      subject(:clear_queue) { queue.clear }

      it 'deletes the job' do
        expect { clear_queue }.to change(queue, :size).from(1).to(0)
      end
    end
  end

  describe 'job set clear' do
    subject { Sidekiq::JobSet.new('schedule').clear }

    before do
      Sidekiq::JobSet.new('schedule').clear
      sidekiq_worker.perform_in(3.minutes, 123)
      activejob_worker.set(wait: 3.minutes).perform_later(:lock_argument, :ignored_argument)
    end

    include_examples 'locks release'
  end

  describe 'job death', sidekiq: :job_death do
    subject do
      Sidekiq::Queue.new('default').each do |job|
        Sidekiq::DeadSet.new.kill(job.value)
      end
    end

    before do
      Sidekiq::Queue.new('default').clear
      sidekiq_worker.perform_async(123)
      activejob_worker.perform_later(:lock_argument, :ignored_argument)
    end

    include_examples 'locks release'
  end

  describe 'releasing a fully custom lock key on delete', active_job_adapter: :sidekiq do
    let(:custom_lock_key) { 'my_custom_lock_key' }
    let!(:activejob_worker) do
      key = custom_lock_key
      stub_active_job_class('CustomLockKeyJob') do
        unique :until_executed

        define_method(:lock_key) { key }
      end
    end

    before do
      Sidekiq::Queue.new('default').clear
      activejob_worker.perform_later(:foo)
    end

    after do
      Sidekiq::Queue.new('default').clear
      redis.call('DEL', custom_lock_key)
    end

    it 'locks under the custom key' do
      expect(redis.call('EXISTS', custom_lock_key)).to eq(1)
    end

    it 'releases the custom key, which a class + arguments wildcard would never match' do
      expect { Sidekiq::Queue.new('default').each(&:delete) }
        .to change { redis.call('EXISTS', custom_lock_key) }.from(1).to(0)
    end
  end

  describe '.unlock_sidekiq_job! with an argument that no longer deserializes' do
    # Simulates a GlobalID whose record has been deleted.
    let(:missing_global_id) { { '_aj_globalid' => 'gid://ajutest/Widget/1' } }

    around do |example|
      locators = GlobalID::Locator.instance_variable_get(:@locators)
      had_locator = locators.key?('ajutest')
      previous_locator = locators['ajutest']

      GlobalID::Locator.use('ajutest') { |_gid| raise ActiveJob::DeserializationError }
      example.run
    ensure
      if had_locator
        locators['ajutest'] = previous_locator
      else
        locators.delete('ajutest')
      end
    end

    def job_data_with(arguments)
      serialized = activejob_worker.new.serialize
      serialized['arguments'] = arguments

      { 'class' => ActiveJob::Uniqueness::SIDEKIQ_JOB_WRAPPERS.first, 'args' => [serialized] }
    end

    context 'when the missing argument is not used by the lock key' do
      let!(:activejob_worker) do
        stub_active_job_class('MissingIgnoredArgJob') do
          unique :until_executed

          def lock_key_arguments
            [arguments.first]
          end
        end
      end

      it 'still skips, since reading #arguments deserializes them all-or-nothing' do
        allow(ActiveJob::Uniqueness.lock_manager).to receive(:delete_lock)

        ActiveJob::Uniqueness.unlock_sidekiq_job!(job_data_with(['keep', missing_global_id]))

        expect(ActiveJob::Uniqueness.lock_manager).not_to have_received(:delete_lock)
      end
    end

    context 'when the missing argument is part of the lock key' do
      let!(:activejob_worker) do
        stub_active_job_class('MissingUsedArgJob') do
          unique :until_executed
        end
      end

      it 'does not attempt to unlock, since the key cannot be rebuilt' do
        allow(ActiveJob::Uniqueness.lock_manager).to receive(:delete_lock)

        ActiveJob::Uniqueness.unlock_sidekiq_job!(job_data_with([missing_global_id, 'x']))

        expect(ActiveJob::Uniqueness.lock_manager).not_to have_received(:delete_lock)
      end
    end

    context 'when a custom lock key calls a method on the missing argument' do
      let!(:activejob_worker) do
        stub_active_job_class('CustomKeyOnMissingArgJob') do
          unique :until_executed

          def lock_key_arguments
            [arguments.first.id]
          end
        end
      end

      it 'skips the unlock instead of raising', :aggregate_failures do
        allow(ActiveJob::Uniqueness.lock_manager).to receive(:delete_lock)

        expect { ActiveJob::Uniqueness.unlock_sidekiq_job!(job_data_with([missing_global_id])) }
          .not_to raise_error

        expect(ActiveJob::Uniqueness.lock_manager).not_to have_received(:delete_lock)
      end
    end

    context 'when a custom lock key raises for reasons unrelated to a missing argument' do
      let!(:activejob_worker) do
        stub_active_job_class('BrokenCustomKeyJob') do
          unique :until_executed

          def lock_key
            raise 'boom'
          end
        end
      end

      it 'lets the error surface instead of masking a genuine bug' do
        expect { ActiveJob::Uniqueness.unlock_sidekiq_job!(job_data_with(['present'])) }
          .to raise_error('boom')
      end
    end

    context 'when the lock key is fully custom and does not depend on the missing argument' do
      let!(:activejob_worker) do
        stub_active_job_class('ConstantKeyMissingArgJob') do
          unique :until_executed

          def lock_key
            'activejob_uniqueness:constant'
          end
        end
      end

      it 'still skips: cleanup deserializes arguments up front and never risks a wrong key' do
        allow(ActiveJob::Uniqueness.lock_manager).to receive(:delete_lock)

        ActiveJob::Uniqueness.unlock_sidekiq_job!(job_data_with([missing_global_id]))

        expect(ActiveJob::Uniqueness.lock_manager).not_to have_received(:delete_lock)
      end
    end

    context 'when only a nested value inside a hash argument is missing' do
      let!(:activejob_worker) do
        stub_active_job_class('NestedMissingArgJob') do
          unique :until_executed

          def lock_key_arguments
            [arguments.first[:account_id]]
          end
        end
      end

      # A Hash argument whose :account_id survives but whose :widget GlobalID is gone.
      let(:nested_argument) do
        { 'account_id' => 7, 'widget' => missing_global_id, '_aj_symbol_keys' => %w[account_id widget] }
      end

      it 'skips, since the whole argument list still fails to deserialize' do
        allow(ActiveJob::Uniqueness.lock_manager).to receive(:delete_lock)

        ActiveJob::Uniqueness.unlock_sidekiq_job!(job_data_with([nested_argument]))

        expect(ActiveJob::Uniqueness.lock_manager).not_to have_received(:delete_lock)
      end
    end

    context 'when a custom lock key compares the missing argument' do
      let!(:activejob_worker) do
        stub_active_job_class('ComparisonKeyMissingArgJob') do
          unique :until_executed

          def lock_key
            arguments.first == 'expected' ? 'activejob_uniqueness:branch_a' : 'activejob_uniqueness:branch_b'
          end
        end
      end

      it 'skips the unlock instead of picking a branch from a missing value' do
        allow(ActiveJob::Uniqueness.lock_manager).to receive(:delete_lock)

        ActiveJob::Uniqueness.unlock_sidekiq_job!(job_data_with([missing_global_id]))

        expect(ActiveJob::Uniqueness.lock_manager).not_to have_received(:delete_lock)
      end
    end

    context 'when a custom lock key interpolates the missing argument' do
      let!(:activejob_worker) do
        stub_active_job_class('InterpolatedKeyMissingArgJob') do
          unique :until_executed

          def lock_key
            "activejob_uniqueness:interpolated:#{arguments.first}"
          end
        end
      end

      it 'skips the unlock instead of deleting a wrong, plausible-looking key' do
        allow(ActiveJob::Uniqueness.lock_manager).to receive(:delete_lock)

        ActiveJob::Uniqueness.unlock_sidekiq_job!(job_data_with([missing_global_id]))

        expect(ActiveJob::Uniqueness.lock_manager).not_to have_received(:delete_lock)
      end
    end
  end

  describe 'cleanup of an :until_and_while_executing job' do
    let!(:activejob_worker) do
      stub_active_job_class('UntilAndWhileExecutingJob') do
        unique :until_and_while_executing
      end
    end

    let(:enqueue_lock_key) { activejob_worker.new('arg').lock_key }
    let(:runtime_lock_key) { activejob_worker.new('arg').runtime_lock_key }

    def job_data
      { 'class' => ActiveJob::Uniqueness::SIDEKIQ_JOB_WRAPPERS.first, 'args' => [activejob_worker.new('arg').serialize] }
    end

    before do
      redis.call('SET', enqueue_lock_key, '1')
      redis.call('SET', runtime_lock_key, '1')
    end

    after do
      redis.call('DEL', enqueue_lock_key)
      redis.call('DEL', runtime_lock_key)
    end

    it 'releases the enqueue lock' do
      expect { ActiveJob::Uniqueness.unlock_sidekiq_job!(job_data) }
        .to change { redis.call('EXISTS', enqueue_lock_key) }.from(1).to(0)
    end

    it 'preserves the runtime lock, which belongs to a currently executing instance' do
      expect { ActiveJob::Uniqueness.unlock_sidekiq_job!(job_data) }
        .not_to change { redis.call('EXISTS', runtime_lock_key) }.from(1)
    end
  end

  describe 'cleanup of a :while_executing job' do
    let!(:activejob_worker) do
      stub_active_job_class('WhileExecutingJob') do
        unique :while_executing
      end
    end

    # :while_executing does not lock on enqueue; #lock_key is the runtime guard
    # held by a currently executing instance.
    let(:runtime_guard_key) { activejob_worker.new('arg').lock_key }

    def job_data
      { 'class' => ActiveJob::Uniqueness::SIDEKIQ_JOB_WRAPPERS.first, 'args' => [activejob_worker.new('arg').serialize] }
    end

    before { redis.call('SET', runtime_guard_key, '1') }
    after { redis.call('DEL', runtime_guard_key) }

    it 'does not touch the lock key, which guards a currently executing instance' do
      expect { ActiveJob::Uniqueness.unlock_sidekiq_job!(job_data) }
        .not_to change { redis.call('EXISTS', runtime_guard_key) }.from(1)
    end
  end
end
