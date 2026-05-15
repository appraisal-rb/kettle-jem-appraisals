# frozen_string_literal: true

module Kettle
  module Jem
    module Appraisals
      # Adapter over Kettle/Jem's shared RubyGems resolver.
      #
      # Kettle/Jem owns the RubyGems HTTP/cache/minimum-Ruby behavior because
      # Gemfile, gemspec, and appraisal planning need the same package metadata.
      # This class preserves the appraisals-local type name while delegating the
      # implementation to {Kettle::Jem::RubyGemsResolver}.
      #
      # @example Fetch all stable versions of a gem
      #   resolver = GemVersionResolver.new
      #   resolver.versions("activerecord")
      #   #=> [{number: "7.1.3", ruby_version: ">= 2.7.0", ...}, ...]
      class GemVersionResolver
        # @return [Kettle::Jem::RubyGemsResolver] shared Kettle/Jem resolver
        attr_reader :resolver

        # @return [Hash] in-memory cache of API responses
        def cache
          resolver.cache
        end

        # @param resolver [Kettle::Jem::RubyGemsResolver, nil]
        #   optional pre-built resolver for sharing a warm cache across multiple
        #   appraisals components in the same session
        def initialize(resolver: nil, **resolver_options)
          @resolver = resolver || Kettle::Jem::RubyGemsResolver.new(**resolver_options)
        end

        # Returns all versions of a gem, sorted oldest-to-newest.
        #
        # Each entry is a Hash with the keys +:number+, +:ruby_version+,
        # +:created_at+, and +:prerelease+.
        #
        # @param gem_name [String] the RubyGems gem name
        # @param include_prerelease [Boolean] when +true+, includes pre-release versions (default: +false+)
        # @return [Array<Hash>] version hashes sorted by +Gem::Version+
        def versions(gem_name, include_prerelease: false, requirements: nil)
          resolver.versions(gem_name, include_prerelease: include_prerelease, requirements: requirements)
        end

        # Returns version info (dependencies, ruby_version) for a specific gem version.
        #
        # Uses the v2 API which includes the full dependency structure.
        #
        # @param gem_name [String] the RubyGems gem name
        # @param version [String] an exact version string (e.g., +"7.1.3"+)
        # @return [Hash, nil] a Hash with +:number+, +:ruby_version+, and +:runtime_dependencies+,
        #   or +nil+ if the version was not found
        def version_info(gem_name, version)
          resolver.version_info(gem_name, version)
        end

        # Returns the minimum Ruby version required by a specific gem version.
        #
        # Delegates to {Kettle::Jem::RubyGemsResolver#min_ruby_version}.
        #
        # @param gem_name [String] the RubyGems gem name
        # @param version [String] an exact version string (e.g., +"7.1.3"+)
        # @return [Gem::Version, nil] the minimum required Ruby version, or +nil+ if unspecified
        def min_ruby_version(gem_name, version)
          resolver.min_ruby_version(gem_name, version)
        end

        # Returns all minor versions (+X.Y+) for a gem, grouped by major version.
        #
        # @param gem_name [String] the RubyGems gem name
        # @return [Array<Hash>] sorted entries, each with +:major+ (Integer) and +:minors+ (Array<String>)
        # @example
        #   resolver.minor_versions_by_major("activerecord")
        #   #=> [{major: 6, minors: ["6.0", "6.1"]}, {major: 7, minors: ["7.0", "7.1", "7.2"]}]
        def minor_versions_by_major(gem_name, requirements: nil)
          resolver.minor_versions_by_major(gem_name, requirements: requirements)
        end
      end
    end
  end
end
