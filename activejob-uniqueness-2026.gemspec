# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'active_job/uniqueness/version'

Gem::Specification.new do |spec|
  spec.name          = 'activejob-uniqueness-2026'
  spec.version       = ActiveJob::Uniqueness::VERSION
  spec.authors       = ['Rustam Sharshenov', 'Nicolai Seerup', 'Yaroslav Kurbatov']
  spec.email         = ['nse@norminvest.com']

  spec.summary       = 'Ensure uniqueness of your ActiveJob jobs'
  spec.description   = 'Ensure uniqueness of your ActiveJob jobs. Maintained fork of veeqo/activejob-uniqueness.'
  spec.homepage      = 'https://github.com/nordinvestments/activejob-uniqueness'
  spec.license       = 'MIT'

  if spec.respond_to?(:metadata)
    spec.metadata['homepage_uri'] = spec.homepage
    spec.metadata['source_code_uri'] = spec.homepage
    spec.metadata['changelog_uri'] = 'https://github.com/nordinvestments/activejob-uniqueness/blob/main/CHANGELOG.md'
    spec.metadata['rubygems_mfa_required'] = 'true'
  end

  spec.files = Dir['CHANGELOG.md', 'LICENSE.txt', 'README.md', 'lib/**/*']

  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 3.1'

  spec.add_dependency 'activejob', '>= 7.1', '< 8.2'
  spec.add_dependency 'redlock', '>= 2.0', '< 3'

  spec.add_development_dependency 'appraisal', '~> 2.3.0'
  spec.add_development_dependency 'bundler', '>= 2.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rubocop', '~> 1.82.1'
  spec.add_development_dependency 'rubocop-rspec', '~> 3.9.0'
end
