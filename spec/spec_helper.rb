# frozen_string_literal: true

# Config for development dependencies of this library
# i.e., not configured by this library
#
# SimpleCov & related config (must run BEFORE any other requires)
# NOTE: Gemfiles for non-coverage appraisals may not have kettle-soup-cover.
#       The rescue LoadError handles that scenario.
begin
  require "kettle-soup-cover"
  if Kettle::Soup::Cover::DO_COV
    require "simplecov"
    require "kettle/soup/cover/config"
    SimpleCov.start
  end
rescue LoadError => error
  # check the error message and re-raise when unexpected
  raise error unless error.message.include?("kettle")
end

# External RSpec & related config
require "kettle/test/rspec"
# `kettle/test/rspec` installs harness helpers documented in spec/README.md.
require "fileutils"
require "kettle-jem-appraisals"

# ConfigFile#write edits YAML through yaml-merge, which parses with the tree-sitter
# backend. That grammar is not loadable on every Ruby (e.g. ruby-head), so examples
# tagged :tree_sitter_yaml run only where the backend can actually parse YAML.
TREE_SITTER_YAML_AVAILABLE = begin
  require "yaml/merge"
  Yaml::Merge::FileAnalysis.new("a: 1\n").valid?
rescue LoadError, StandardError
  false
end

RSpec.configure do |config|
  config.filter_run_excluding(tree_sitter_yaml: true) unless TREE_SITTER_YAML_AVAILABLE

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  config.expect_with :rspec do |c|
    c.syntax = :expect
    c.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
