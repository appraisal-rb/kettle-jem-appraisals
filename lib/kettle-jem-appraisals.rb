# frozen_string_literal: true

require "kettle/jem"
require "kettle/jem/appraisals"
require "version_gem"
require_relative "kettle/jem/appraisals/version"

Kettle::Jem::Appraisals::Version.class_eval do
  extend VersionGem::Basic
end
