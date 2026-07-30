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
end
