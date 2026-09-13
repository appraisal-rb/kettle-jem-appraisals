# frozen_string_literal: true

require "fileutils"
require "yaml"

module Kettle
  module Jem
    module Appraisals
      # Reads and surgically updates the project's kettle-jem configuration file.
      #
      # The +appraisal_matrix+ lives in the same file kettle-jem uses
      # (+.structuredmerge/kettle-jem.yml+). That file is heavily commented and
      # holds many other settings, so writes only replace the top-level sections
      # whose values changed, leaving comments and every other section intact.
      #
      # @example
      #   config_file = ConfigFile.new(project_dir: "/path/to/gem")
      #   config = config_file.load
      #   config["appraisal_matrix"]["resolved_at"] = Time.now.to_i
      #   config_file.write(config)
      class ConfigFile
        # @return [String] canonical config path, relative to the project root
        CANONICAL_PATH = Kettle::Jem::KETTLE_CONFIG_PATH

        # @return [String] legacy config path, read only when the canonical file is absent
        LEGACY_PATH = Kettle::Jem::LEGACY_KETTLE_CONFIG_PATH

        # @return [String] absolute path to the project root
        attr_reader :project_dir

        # @param project_dir [String] path to the project root
        def initialize(project_dir:)
          @project_dir = project_dir
        end

        # The config file to read and write: the canonical file when present,
        # otherwise an existing legacy file, otherwise the canonical location.
        #
        # @return [String] absolute path
        def path
          canonical = File.join(project_dir, CANONICAL_PATH)
          return canonical if File.exist?(canonical)

          legacy = File.join(project_dir, LEGACY_PATH)
          return legacy if File.exist?(legacy)

          canonical
        end

        # @return [String] {#path} relative to the project root, for messages
        def relative_path
          File.expand_path(path).delete_prefix("#{File.expand_path(project_dir)}/")
        end

        # @return [Hash] the parsed config, or an empty Hash when the file does not exist
        def load
          return {} unless File.exist?(path)

          YAML.safe_load_file(path, permitted_classes: [Symbol]) || {}
        end

        # Writes +config+, replacing only the top-level sections that differ from
        # the file on disk. Creates the file (and its directory) when missing.
        #
        # @param config [Hash] the full desired config
        # @return [void]
        def write(config)
          target = path
          unless File.exist?(target)
            FileUtils.mkdir_p(File.dirname(target))
            File.write(target, YAML.dump(config))
            return
          end

          content = File.read(target)
          current = YAML.safe_load(content, permitted_classes: [Symbol]) || {}
          config.each do |key, value|
            next if current.key?(key) && current[key] == value

            content = upsert_section(content, key.to_s, value)
          end
          File.write(target, content)
        end

        private

        def upsert_section(content, key, value)
          block = YAML.dump({key => value}).delete_prefix("---\n")
          range = section_range(content, key)
          return "#{content.rstrip}\n\n#{block}" unless range

          lines = content.lines
          [*lines[0...range.begin], block, *lines[range.end..]].join
        end

        # Line range (0-based, end-exclusive) of the top-level +key+ section.
        # A parsed section runs up to the next top-level key, so trailing blank
        # lines and comment lines (commented-out settings, or comments that
        # introduce the next section) are trimmed back out of the range and kept.
        def section_range(content, key)
          require "yaml/merge"

          analysis = Yaml::Merge::FileAnalysis.new(content)
          raise ArgumentError, "could not parse #{relative_path} as YAML" unless analysis.valid?

          body = analysis.documents.first&.body_node
          return unless body&.mapping?

          lines = content.lines
          pairs = body.mapping_pairs
          pairs.each_with_index do |pair, index|
            next unless pair.key_name == key

            start_index = pair.start_line.to_i - 1
            next_pair = pairs[index + 1]
            end_index = next_pair ? next_pair.start_line.to_i - 1 : lines.length
            end_index -= 1 while end_index > start_index + 1 && trailing_trivia?(lines[end_index - 1])
            return start_index...end_index
          end

          nil
        end

        # @return [Boolean] whether +line+ is blank or a comment (at any indentation)
        def trailing_trivia?(line)
          stripped = line.strip
          stripped.empty? || stripped.start_with?("#")
        end
      end
    end
  end
end
