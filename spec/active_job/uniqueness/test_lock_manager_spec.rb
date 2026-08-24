# frozen_string_literal: true

describe ActiveJob::Uniqueness::TestLockManager do
  subject(:manager) { described_class.new }

  # Guards against drift: every public method the real manager responds to
  # (its own plus the inherited Redlock::Client API) must be stubbed here, so
  # test_mode! can never raise NoMethodError for an otherwise-valid call.
  it 'stubs the full public API of LockManager', :aggregate_failures do
    lock_manager_api = ActiveJob::Uniqueness::LockManager.instance_methods - Object.instance_methods

    expect(lock_manager_api).not_to be_empty
    expect(manager).to respond_to(*lock_manager_api)
  end

  describe '#lock' do
    it 'succeeds' do
      expect(manager.lock('resource', 1000)).to be(true)
    end

    it 'yields when a block is given' do
      expect { |b| manager.lock('resource', 1000, &b) }.to yield_with_args(true)
    end
  end

  describe '#lock!' do
    it 'succeeds without a block' do
      expect(manager.lock!('resource', 1000)).to be(true)
    end

    it 'yields and returns the block value' do
      expect(manager.lock!('resource', 1000) { :ok }).to eq(:ok)
    end
  end

  describe 'lock state reads report that nothing is held' do
    specify { expect(manager.locked?('resource')).to be(false) }
    specify { expect(manager.valid_lock?('lock_info')).to be(false) }
    specify { expect(manager.get_remaining_ttl_for_lock('lock_info')).to be_nil }
    specify { expect(manager.get_remaining_ttl_for_resource('resource')).to be_nil }
    specify { expect(manager.unlock('lock_info')).to be_nil }
  end

  describe 'deletion' do
    specify { expect(manager.delete_lock('resource')).to be(true) }
    specify { expect(manager.delete_locks('wildcard')).to be(true) }
  end
end
