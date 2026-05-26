# frozen_string_literal: true

require "tmpdir"

RSpec.describe Kettle::Jem::Appraisals::CLI do
  describe "standard appraisal collapse annotation" do
    it "collapses unique bucket targets onto standard ruby appraisals" do
      cli = described_class.new([])
      entries = [
        {name: "kja-ar-8-0-r3", ruby_series: "r3"},
        {name: "kja-ar-7-2-r3.1", ruby_series: "r3.1"},
      ]
      bucket_ranges = {
        "r3" => {floor: Gem::Version.new("3.2"), ceiling: Gem::Version.new("3.99")},
        "r3.1" => {floor: Gem::Version.new("3.0"), ceiling: Gem::Version.new("3.1")},
      }

      cli.send(:annotate_standard_appraisal_collapses, entries, bucket_ranges)

      expect(entries).to include(include(name: "kja-ar-8-0-r3", appraisal_name: "ruby-3-2"))
      expect(entries).to include(include(name: "kja-ar-7-2-r3.1", appraisal_name: "ruby-3-0"))
    end

    it "keeps generated names when multiple entries target the same standard appraisal" do
      cli = described_class.new([])
      entries = [
        {name: "kja-ar-6-0-r2.6", ruby_series: "r2.6", tier1_version: "6.0"},
        {name: "kja-ar-6-1-r2.6", ruby_series: "r2.6", tier1_version: "6.1"},
      ]
      bucket_ranges = {
        "r2.6" => {floor: Gem::Version.new("2.5"), ceiling: Gem::Version.new("2.6")},
      }

      cli.send(:annotate_standard_appraisal_collapses, entries, bucket_ranges)

      expect(entries).to all(satisfy { |entry| !entry.key?(:appraisal_name) })
    end

    it "collapses the newest duplicate bucket entry when standard appraisals are required" do
      cli = described_class.new([])
      entries = [
        {name: "kja-ar-6-0-r2.6", ruby_series: "r2.6", tier1_version: "6.0"},
        {name: "kja-ar-6-1-r2.6", ruby_series: "r2.6", tier1_version: "6.1"},
      ]
      bucket_ranges = {
        "r2.6" => {floor: Gem::Version.new("2.5"), ceiling: Gem::Version.new("2.6")},
      }

      cli.send(
        :annotate_standard_appraisal_collapses,
        entries,
        bucket_ranges,
        {"standard_appraisal_role" => "runtime_dependency"},
      )

      expect(entries).to include(include(name: "kja-ar-6-1-r2.6", appraisal_name: "ruby-2-5"))
      expect(entries.find { |entry| entry[:name] == "kja-ar-6-0-r2.6" }).not_to include(:appraisal_name)
    end

    it "can disable standard appraisal collapse entirely" do
      cli = described_class.new([])
      entries = [
        {name: "kja-ar-8-0-r3", ruby_series: "r3", tier1_version: "8.0"},
      ]
      bucket_ranges = {
        "r3" => {floor: Gem::Version.new("3.2"), ceiling: Gem::Version.new("3.99")},
      }

      cli.send(
        :annotate_standard_appraisal_collapses,
        entries,
        bucket_ranges,
        {"standard_appraisal_collapse" => "none"},
      )

      expect(entries).to all(satisfy { |entry| !entry.key?(:appraisal_name) })
    end
  end

  describe "shared appraisal gemfiles" do
    it "normalizes shared support gemfiles configured for generated entries" do
      cli = described_class.new([])
      matrix = {
        "appraisal_gemfiles" => [
          "gemfiles/modular/activerecord_support.gemfile",
          "modular/activerecord_support.gemfile",
          "",
        ],
      }

      expect(cli.send(:matrix_extra_gemfiles, matrix)).to eq(["modular/activerecord_support.gemfile"])
    end

    it "annotates generated entries with shared support gemfiles" do
      cli = described_class.new([])
      entries = [{name: "kja-ar-6-0-r2.6"}]

      cli.send(:annotate_extra_gemfiles, entries, ["modular/activerecord_support.gemfile"])

      expect(entries).to eq([
        {name: "kja-ar-6-0-r2.6", extra_gemfiles: ["modular/activerecord_support.gemfile"]},
      ])
    end
  end

  describe "project Ruby floor detection" do
    it "uses the higher of gemspec required_ruby_version and ruby.test_minimum" do
      Dir.mktmpdir do |project_dir|
        File.write(File.join(project_dir, "demo.gemspec"), <<~GEMSPEC)
          Gem::Specification.new do |spec|
            spec.name = "demo"
            spec.version = "0.1.0"
            spec.summary = "demo"
            spec.required_ruby_version = ">= 2.3"
          end
        GEMSPEC
        cli = described_class.new([], project_dir: project_dir)

        floor = cli.send(:detect_project_min_ruby, {"ruby" => {"test_minimum" => "2.4"}})

        expect(floor).to eq(Gem::Version.new("2.4"))
      end
    end
  end

  describe "#run" do
    it "normalizes scaffold-mode project paths in missing gemspec output" do
      cli = described_class.new(["--scaffold"], project_dir: "/var/home/pboling/src/kettle-rb/demo")
      allow(cli).to receive(:find_gemspec).and_return(nil)

      expect { cli.run }.to output(include("/home/pboling/src/kettle-rb/demo")).to_stderr.and raise_error(SystemExit)
    end

    it "reads runtime dependencies from a loaded gemspec object in scaffold mode" do
      Dir.mktmpdir do |project_dir|
        File.write(File.join(project_dir, "demo.gemspec"), <<~GEMSPEC)
          Gem::Specification.new do |spec|
            spec.name = "demo"
            spec.version = "0.1.0"
            spec.summary = "demo"
            spec.authors = ["Test User"]
            spec.email = ["test@example.com"]
            spec.required_ruby_version = ">= 3.2"
            spec.add_dependency "runtime_dep", ">= 1"
            spec.add_development_dependency "dev_dep", ">= 1"
            # spec.add_dependency "commented_dep"
          end
        GEMSPEC

        cli = described_class.new(["--scaffold"], project_dir: project_dir)

        cli.run

        config = YAML.load_file(File.join(project_dir, ".kettle-jem.yml"))
        tier1 = config.fetch("appraisal_matrix").fetch("gems").fetch("tier1")
        expect(tier1).to eq([{"name" => "runtime_dep"}])
      end
    end

    it "passes requirements through to patch-mode selection and unions include_versions into the matrix" do
      Dir.mktmpdir do |project_dir|
        File.write(File.join(project_dir, ".kettle-jem.yml"), <<~YAML)
          appraisal_matrix:
            mode: semver
            gems:
              tier1:
                - name: activerecord
                  mode: patch
                  requirements:
                    - ">= 7.1"
                    - "< 7.2"
                  include_versions:
                    - "6.0.9"
                    - "8.0.1"
              tier2: []
        YAML
        File.write(File.join(project_dir, "demo.gemspec"), <<~GEMSPEC)
          Gem::Specification.new do |spec|
            spec.name = "demo"
            spec.version = "0.1.0"
            spec.summary = "demo"
            spec.authors = ["Test User"]
            spec.email = ["test@example.com"]
            spec.required_ruby_version = ">= 3.2"
          end
        GEMSPEC

        cli = described_class.new(["--resolve"], project_dir: project_dir)
        resolver = instance_double(Kettle::Jem::Appraisals::GemVersionResolver)
        builder = instance_double(Kettle::Jem::Appraisals::MatrixBuilder)
        sub_resolver = instance_double(Kettle::Jem::Appraisals::SubDepResolver)
        gemfile_gen = instance_double(Kettle::Jem::Appraisals::ModularGemfileGenerator)
        series_detector = instance_double(Kettle::Jem::Appraisals::RubySeriesDetector)
        workflow_gen = instance_double(Kettle::Jem::Appraisals::WorkflowStrategyGenerator)

        allow(Kettle::Jem::Appraisals::GemVersionResolver).to receive(:new).and_return(resolver)
        allow(Kettle::Jem::Appraisals::MatrixBuilder).to receive(:new).with(resolver: resolver).and_return(builder)
        allow(Kettle::Jem::Appraisals::SubDepResolver).to receive(:new).with(resolver: resolver).and_return(sub_resolver)
        allow(Kettle::Jem::Appraisals::ModularGemfileGenerator).to receive(:new).with(base_dir: project_dir).and_return(gemfile_gen)
        allow(Kettle::Jem::Appraisals::RubySeriesDetector).to receive(:new).with(resolver: resolver).and_return(series_detector)
        allow(Kettle::Jem::Appraisals::WorkflowStrategyGenerator).to receive(:new).and_return(workflow_gen)
        allow(Kettle::Jem::Appraisals::AppraisalsGenerator).to receive(:generate).and_return("# Appraisals\n")

        requirements = [">= 7.1", "< 7.2"]
        selected_versions = %w[7.1.0 7.1.1]
        all_versions = %w[6.0.9 7.1.0 7.1.1 8.0.1]
        allow(builder).to receive(:select_versions)
          .with("activerecord", mode: "patch", requirements: requirements)
          .and_return(selected_versions)
        allow(resolver).to receive(:versions)
          .with("activerecord", requirements: requirements)
          .and_return(selected_versions.map { |version| {number: version} })
        allow(series_detector).to receive(:detect_with_ranges).and_return(
          buckets: ["r3"],
          bucket_ranges: {"r3" => {floor: Gem::Version.new("3.2"), ceiling: Gem::Version.new("3.99")}},
        )
        allow(series_detector).to receive(:find_seams).with("activerecord", all_versions).and_return(
          [{version: "6.0.9", min_ruby: Gem::Version.new("3.0")}],
        )
        allow(builder).to receive(:assign_version_buckets).with(
          "activerecord",
          all_versions,
          seams: [{version: "6.0.9", min_ruby: Gem::Version.new("3.0")}],
          buckets: ["r3"],
          bucket_ranges: {"r3" => {floor: Gem::Version.new("3.2"), ceiling: Gem::Version.new("3.99")}},
          all_versions: all_versions,
        ).and_return([{version: "8.0.1", bucket: "r3"}])
        allow(sub_resolver).to receive(:resolve).and_return({})
        allow(gemfile_gen).to receive(:generate).and_return("gemfiles/modular/activerecord/r3/v8.0.1.gemfile")
        allow(workflow_gen).to receive(:generate).and_return({})

        cli.run

        expect(builder).to have_received(:select_versions)
          .with("activerecord", mode: "patch", requirements: requirements)
        expect(resolver).to have_received(:versions)
          .with("activerecord", requirements: requirements)
        expect(series_detector).to have_received(:find_seams).with("activerecord", all_versions)
        expect(builder).to have_received(:assign_version_buckets).with(
          "activerecord",
          all_versions,
          seams: [{version: "6.0.9", min_ruby: Gem::Version.new("3.0")}],
          buckets: ["r3"],
          bucket_ranges: {"r3" => {floor: Gem::Version.new("3.2"), ceiling: Gem::Version.new("3.99")}},
          all_versions: all_versions,
        )
      end
    end

    it "passes requirements through in major mode" do
      Dir.mktmpdir do |project_dir|
        File.write(File.join(project_dir, ".kettle-jem.yml"), <<~YAML)
          appraisal_matrix:
            mode: major
            gems:
              tier1:
                - name: sequel
                  requirements:
                    - ">= 5.0"
                    - "< 6.0"
              tier2: []
        YAML
        File.write(File.join(project_dir, "demo.gemspec"), <<~GEMSPEC)
          Gem::Specification.new do |spec|
            spec.name = "demo"
            spec.version = "0.1.0"
            spec.summary = "demo"
            spec.authors = ["Test User"]
            spec.email = ["test@example.com"]
            spec.required_ruby_version = ">= 3.2"
          end
        GEMSPEC

        cli = described_class.new(["--resolve"], project_dir: project_dir)
        resolver = instance_double(Kettle::Jem::Appraisals::GemVersionResolver)
        builder = instance_double(Kettle::Jem::Appraisals::MatrixBuilder)
        sub_resolver = instance_double(Kettle::Jem::Appraisals::SubDepResolver)
        gemfile_gen = instance_double(Kettle::Jem::Appraisals::ModularGemfileGenerator)
        series_detector = instance_double(Kettle::Jem::Appraisals::RubySeriesDetector)
        workflow_gen = instance_double(Kettle::Jem::Appraisals::WorkflowStrategyGenerator)

        allow(Kettle::Jem::Appraisals::GemVersionResolver).to receive(:new).and_return(resolver)
        allow(Kettle::Jem::Appraisals::MatrixBuilder).to receive(:new).with(resolver: resolver).and_return(builder)
        allow(Kettle::Jem::Appraisals::SubDepResolver).to receive(:new).with(resolver: resolver).and_return(sub_resolver)
        allow(Kettle::Jem::Appraisals::ModularGemfileGenerator).to receive(:new).with(base_dir: project_dir).and_return(gemfile_gen)
        allow(Kettle::Jem::Appraisals::RubySeriesDetector).to receive(:new).with(resolver: resolver).and_return(series_detector)
        allow(Kettle::Jem::Appraisals::WorkflowStrategyGenerator).to receive(:new).and_return(workflow_gen)
        allow(Kettle::Jem::Appraisals::AppraisalsGenerator).to receive(:generate).and_return("# Appraisals\n")

        requirements = [">= 5.0", "< 6.0"]
        allow(builder).to receive(:select_versions)
          .with("sequel", mode: "major", requirements: requirements)
          .and_return(["5.9"])
        allow(resolver).to receive(:minor_versions_by_major)
          .with("sequel", requirements: requirements)
          .and_return([{major: 5, minors: ["5.0", "5.9"]}])
        allow(series_detector).to receive(:detect_with_ranges).and_return(
          buckets: ["r3"],
          bucket_ranges: {"r3" => {floor: Gem::Version.new("3.2"), ceiling: Gem::Version.new("3.99")}},
        )
        allow(series_detector).to receive(:find_seams).with("sequel", ["5.0", "5.9"]).and_return(
          [{version: "5.0", min_ruby: Gem::Version.new("3.2")}],
        )
        allow(builder).to receive(:assign_version_buckets).and_return([{version: "5.9", bucket: "r3"}])
        allow(sub_resolver).to receive(:resolve).and_return({})
        allow(gemfile_gen).to receive(:generate).and_return("gemfiles/modular/sequel/r3/v5.9.gemfile")
        allow(workflow_gen).to receive(:generate).and_return({})

        cli.run

        expect(builder).to have_received(:select_versions)
          .with("sequel", mode: "major", requirements: requirements)
        expect(resolver).to have_received(:minor_versions_by_major)
          .with("sequel", requirements: requirements)
      end
    end

    it "adds include_versions even when no requirements are specified" do
      Dir.mktmpdir do |project_dir|
        File.write(File.join(project_dir, ".kettle-jem.yml"), <<~YAML)
          appraisal_matrix:
            mode: major
            gems:
              tier1:
                - name: mail
                  include_versions:
                    - "2.7.1"
              tier2: []
        YAML
        File.write(File.join(project_dir, "demo.gemspec"), <<~GEMSPEC)
          Gem::Specification.new do |spec|
            spec.name = "demo"
            spec.version = "0.1.0"
            spec.summary = "demo"
            spec.authors = ["Test User"]
            spec.email = ["test@example.com"]
            spec.required_ruby_version = ">= 3.2"
          end
        GEMSPEC

        cli = described_class.new(["--resolve"], project_dir: project_dir)
        resolver = instance_double(Kettle::Jem::Appraisals::GemVersionResolver)
        builder = instance_double(Kettle::Jem::Appraisals::MatrixBuilder)
        sub_resolver = instance_double(Kettle::Jem::Appraisals::SubDepResolver)
        gemfile_gen = instance_double(Kettle::Jem::Appraisals::ModularGemfileGenerator)
        series_detector = instance_double(Kettle::Jem::Appraisals::RubySeriesDetector)
        workflow_gen = instance_double(Kettle::Jem::Appraisals::WorkflowStrategyGenerator)

        allow(Kettle::Jem::Appraisals::GemVersionResolver).to receive(:new).and_return(resolver)
        allow(Kettle::Jem::Appraisals::MatrixBuilder).to receive(:new).with(resolver: resolver).and_return(builder)
        allow(Kettle::Jem::Appraisals::SubDepResolver).to receive(:new).with(resolver: resolver).and_return(sub_resolver)
        allow(Kettle::Jem::Appraisals::ModularGemfileGenerator).to receive(:new).with(base_dir: project_dir).and_return(gemfile_gen)
        allow(Kettle::Jem::Appraisals::RubySeriesDetector).to receive(:new).with(resolver: resolver).and_return(series_detector)
        allow(Kettle::Jem::Appraisals::WorkflowStrategyGenerator).to receive(:new).and_return(workflow_gen)
        allow(Kettle::Jem::Appraisals::AppraisalsGenerator).to receive(:generate).and_return("# Appraisals\n")

        allow(builder).to receive(:select_versions)
          .with("mail", mode: "major", requirements: nil)
          .and_return(["2.8"])
        allow(resolver).to receive(:minor_versions_by_major)
          .with("mail", requirements: nil)
          .and_return([{major: 2, minors: ["2.7", "2.8"]}])
        allow(series_detector).to receive(:detect_with_ranges).and_return(
          buckets: ["r3"],
          bucket_ranges: {"r3" => {floor: Gem::Version.new("3.2"), ceiling: Gem::Version.new("3.99")}},
        )
        allow(series_detector).to receive(:find_seams).with("mail", %w[2.7 2.7.1 2.8]).and_return(
          [{version: "2.7", min_ruby: Gem::Version.new("3.2")}],
        )
        allow(builder).to receive(:assign_version_buckets).with(
          "mail",
          %w[2.7.1 2.8],
          seams: [{version: "2.7", min_ruby: Gem::Version.new("3.2")}],
          buckets: ["r3"],
          bucket_ranges: {"r3" => {floor: Gem::Version.new("3.2"), ceiling: Gem::Version.new("3.99")}},
          all_versions: %w[2.7 2.7.1 2.8],
        ).and_return([{version: "2.7.1", bucket: "r3"}])
        allow(sub_resolver).to receive(:resolve).and_return({})
        allow(gemfile_gen).to receive(:generate).and_return("gemfiles/modular/mail/r3/v2.7.1.gemfile")
        allow(workflow_gen).to receive(:generate).and_return({})

        cli.run

        expect(builder).to have_received(:select_versions)
          .with("mail", mode: "major", requirements: nil)
        expect(resolver).to have_received(:minor_versions_by_major)
          .with("mail", requirements: nil)
        expect(series_detector).to have_received(:find_seams).with("mail", %w[2.7 2.7.1 2.8])
        expect(builder).to have_received(:assign_version_buckets).with(
          "mail",
          %w[2.7.1 2.8],
          seams: [{version: "2.7", min_ruby: Gem::Version.new("3.2")}],
          buckets: ["r3"],
          bucket_ranges: {"r3" => {floor: Gem::Version.new("3.2"), ceiling: Gem::Version.new("3.99")}},
          all_versions: %w[2.7 2.7.1 2.8],
        )
      end
    end

    it "removes exclude_versions after mode and include_versions are combined" do
      Dir.mktmpdir do |project_dir|
        File.write(File.join(project_dir, ".kettle-jem.yml"), <<~YAML)
          appraisal_matrix:
            mode: semver
            gems:
              tier1:
                - name: activerecord
                  mode: patch
                  requirements:
                    - ">= 7.1"
                    - "< 7.2"
                  include_versions:
                    - "6.0.9"
                    - "8.0.1"
                  exclude_versions:
                    - "7.1.0"
                    - "8.0.1"
              tier2: []
        YAML
        File.write(File.join(project_dir, "demo.gemspec"), <<~GEMSPEC)
          Gem::Specification.new do |spec|
            spec.name = "demo"
            spec.version = "0.1.0"
            spec.summary = "demo"
            spec.authors = ["Test User"]
            spec.email = ["test@example.com"]
            spec.required_ruby_version = ">= 3.2"
          end
        GEMSPEC

        cli = described_class.new(["--resolve"], project_dir: project_dir)
        resolver = instance_double(Kettle::Jem::Appraisals::GemVersionResolver)
        builder = instance_double(Kettle::Jem::Appraisals::MatrixBuilder)
        sub_resolver = instance_double(Kettle::Jem::Appraisals::SubDepResolver)
        gemfile_gen = instance_double(Kettle::Jem::Appraisals::ModularGemfileGenerator)
        series_detector = instance_double(Kettle::Jem::Appraisals::RubySeriesDetector)
        workflow_gen = instance_double(Kettle::Jem::Appraisals::WorkflowStrategyGenerator)

        allow(Kettle::Jem::Appraisals::GemVersionResolver).to receive(:new).and_return(resolver)
        allow(Kettle::Jem::Appraisals::MatrixBuilder).to receive(:new).with(resolver: resolver).and_return(builder)
        allow(Kettle::Jem::Appraisals::SubDepResolver).to receive(:new).with(resolver: resolver).and_return(sub_resolver)
        allow(Kettle::Jem::Appraisals::ModularGemfileGenerator).to receive(:new).with(base_dir: project_dir).and_return(gemfile_gen)
        allow(Kettle::Jem::Appraisals::RubySeriesDetector).to receive(:new).with(resolver: resolver).and_return(series_detector)
        allow(Kettle::Jem::Appraisals::WorkflowStrategyGenerator).to receive(:new).and_return(workflow_gen)
        allow(Kettle::Jem::Appraisals::AppraisalsGenerator).to receive(:generate).and_return("# Appraisals\n")

        requirements = [">= 7.1", "< 7.2"]
        selected_versions = %w[7.1.0 7.1.1]
        final_versions = %w[6.0.9 7.1.1]
        all_versions = %w[6.0.9 7.1.1]
        allow(builder).to receive(:select_versions)
          .with("activerecord", mode: "patch", requirements: requirements)
          .and_return(selected_versions)
        allow(resolver).to receive(:versions)
          .with("activerecord", requirements: requirements)
          .and_return(selected_versions.map { |version| {number: version} })
        allow(series_detector).to receive(:detect_with_ranges).and_return(
          buckets: ["r3"],
          bucket_ranges: {"r3" => {floor: Gem::Version.new("3.2"), ceiling: Gem::Version.new("3.99")}},
        )
        allow(series_detector).to receive(:find_seams).with("activerecord", all_versions).and_return(
          [{version: "6.0.9", min_ruby: Gem::Version.new("3.0")}],
        )
        allow(builder).to receive(:assign_version_buckets).with(
          "activerecord",
          final_versions,
          seams: [{version: "6.0.9", min_ruby: Gem::Version.new("3.0")}],
          buckets: ["r3"],
          bucket_ranges: {"r3" => {floor: Gem::Version.new("3.2"), ceiling: Gem::Version.new("3.99")}},
          all_versions: all_versions,
        ).and_return([{version: "7.1.1", bucket: "r3"}])
        allow(sub_resolver).to receive(:resolve).and_return({})
        allow(gemfile_gen).to receive(:generate).and_return("gemfiles/modular/activerecord/r3/v7.1.1.gemfile")
        allow(workflow_gen).to receive(:generate).and_return({})

        cli.run

        expect(builder).to have_received(:select_versions)
          .with("activerecord", mode: "patch", requirements: requirements)
        expect(resolver).to have_received(:versions)
          .with("activerecord", requirements: requirements)
        expect(series_detector).to have_received(:find_seams).with("activerecord", all_versions)
        expect(builder).to have_received(:assign_version_buckets).with(
          "activerecord",
          final_versions,
          seams: [{version: "6.0.9", min_ruby: Gem::Version.new("3.0")}],
          buckets: ["r3"],
          bucket_ranges: {"r3" => {floor: Gem::Version.new("3.2"), ceiling: Gem::Version.new("3.99")}},
          all_versions: all_versions,
        )
      end
    end
  end
end
