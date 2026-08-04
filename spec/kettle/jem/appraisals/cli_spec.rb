# frozen_string_literal: true

require "tmpdir"

RSpec.describe Kettle::Jem::Appraisals::CLI do
  describe "standard appraisal collapse annotation" do
    it "collapses unique bucket targets onto standard ruby appraisals" do
      cli = described_class.new([])
      entries = [
        {name: "kja-ar-8-0-r3", ruby_series: "r3"},
        {name: "kja-ar-7-2-r3.1", ruby_series: "r3.1"}
      ]
      bucket_ranges = {
        "r3" => {floor: Gem::Version.new("3.2"), ceiling: Gem::Version.new("3.99")},
        "r3.1" => {floor: Gem::Version.new("3.0"), ceiling: Gem::Version.new("3.1")}
      }

      cli.send(:annotate_standard_appraisal_collapses, entries, bucket_ranges)

      expect(entries).to include(include(name: "kja-ar-8-0-r3", appraisal_name: "ruby-3-2"))
      expect(entries).to include(include(name: "kja-ar-7-2-r3.1", appraisal_name: "ruby-3-0"))
    end

    it "keeps generated names when multiple entries target the same standard appraisal" do
      cli = described_class.new([])
      entries = [
        {name: "kja-ar-6-0-r2.6", ruby_series: "r2.6", tier1_version: "6.0"},
        {name: "kja-ar-6-1-r2.6", ruby_series: "r2.6", tier1_version: "6.1"}
      ]
      bucket_ranges = {
        "r2.6" => {floor: Gem::Version.new("2.5"), ceiling: Gem::Version.new("2.6")}
      }

      cli.send(:annotate_standard_appraisal_collapses, entries, bucket_ranges)

      expect(entries).to all(satisfy { |entry| !entry.key?(:appraisal_name) })
    end

    it "collapses the newest duplicate bucket entry when standard appraisals are required" do
      cli = described_class.new([])
      entries = [
        {name: "kja-ar-6-0-r2.6", ruby_series: "r2.6", tier1_version: "6.0"},
        {name: "kja-ar-6-1-r2.6", ruby_series: "r2.6", tier1_version: "6.1"}
      ]
      bucket_ranges = {
        "r2.6" => {floor: Gem::Version.new("2.5"), ceiling: Gem::Version.new("2.6")}
      }

      cli.send(
        :annotate_standard_appraisal_collapses,
        entries,
        bucket_ranges,
        {"standard_appraisal_role" => "runtime_dependency"}
      )

      expect(entries).to include(include(name: "kja-ar-6-1-r2.6", appraisal_name: "ruby-2-5"))
      expect(entries.find { |entry| entry[:name] == "kja-ar-6-0-r2.6" }).not_to include(:appraisal_name)
    end

    it "can disable standard appraisal collapse entirely" do
      cli = described_class.new([])
      entries = [
        {name: "kja-ar-8-0-r3", ruby_series: "r3", tier1_version: "8.0"}
      ]
      bucket_ranges = {
        "r3" => {floor: Gem::Version.new("3.2"), ceiling: Gem::Version.new("3.99")}
      }

      cli.send(
        :annotate_standard_appraisal_collapses,
        entries,
        bucket_ranges,
        {"standard_appraisal_collapse" => "none"}
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
          ""
        ]
      }

      expect(cli.send(:matrix_extra_gemfiles, matrix)).to eq(["modular/activerecord_support.gemfile"])
    end

    it "annotates generated entries with shared support gemfiles" do
      cli = described_class.new([])
      entries = [{name: "kja-ar-6-0-r2.6"}]

      cli.send(:annotate_extra_gemfiles, entries, ["modular/activerecord_support.gemfile"])

      expect(entries).to eq([
        {name: "kja-ar-6-0-r2.6", extra_gemfiles: ["modular/activerecord_support.gemfile"]}
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
      cli = described_class.new(["--scaffold"], project_dir: "/var/home/pboling/src/kettle-dev/demo")
      allow(cli).to receive(:find_gemspec).and_return(nil)

      expect { cli.run }.to output(include("/home/pboling/src/kettle-dev/demo")).to_stderr.and raise_error(SystemExit)
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
          bucket_ranges: {"r3" => {floor: Gem::Version.new("3.2"), ceiling: Gem::Version.new("3.99")}}
        )
        allow(series_detector).to receive(:find_seams).with("activerecord", all_versions).and_return(
          [{version: "6.0.9", min_ruby: Gem::Version.new("3.0")}]
        )
        allow(builder).to receive(:assign_version_buckets).with(
          "activerecord",
          all_versions,
          seams: [{version: "6.0.9", min_ruby: Gem::Version.new("3.0")}],
          buckets: ["r3"],
          bucket_ranges: {"r3" => {floor: Gem::Version.new("3.2"), ceiling: Gem::Version.new("3.99")}},
          all_versions: all_versions
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
          all_versions: all_versions
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
          bucket_ranges: {"r3" => {floor: Gem::Version.new("3.2"), ceiling: Gem::Version.new("3.99")}}
        )
        allow(series_detector).to receive(:find_seams).with("sequel", ["5.0", "5.9"]).and_return(
          [{version: "5.0", min_ruby: Gem::Version.new("3.2")}]
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
          bucket_ranges: {"r3" => {floor: Gem::Version.new("3.2"), ceiling: Gem::Version.new("3.99")}}
        )
        allow(series_detector).to receive(:find_seams).with("mail", %w[2.7 2.7.1 2.8]).and_return(
          [{version: "2.7", min_ruby: Gem::Version.new("3.2")}]
        )
        allow(builder).to receive(:assign_version_buckets).with(
          "mail",
          %w[2.7.1 2.8],
          seams: [{version: "2.7", min_ruby: Gem::Version.new("3.2")}],
          buckets: ["r3"],
          bucket_ranges: {"r3" => {floor: Gem::Version.new("3.2"), ceiling: Gem::Version.new("3.99")}},
          all_versions: %w[2.7 2.7.1 2.8]
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
          all_versions: %w[2.7 2.7.1 2.8]
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
          bucket_ranges: {"r3" => {floor: Gem::Version.new("3.2"), ceiling: Gem::Version.new("3.99")}}
        )
        allow(series_detector).to receive(:find_seams).with("activerecord", all_versions).and_return(
          [{version: "6.0.9", min_ruby: Gem::Version.new("3.0")}]
        )
        allow(builder).to receive(:assign_version_buckets).with(
          "activerecord",
          final_versions,
          seams: [{version: "6.0.9", min_ruby: Gem::Version.new("3.0")}],
          buckets: ["r3"],
          bucket_ranges: {"r3" => {floor: Gem::Version.new("3.2"), ceiling: Gem::Version.new("3.99")}},
          all_versions: all_versions
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
          all_versions: all_versions
        )
      end
    end
  end

  describe "private helpers" do
    let(:cli) { described_class.new([]) }

    it "detects explicit and config-derived modes" do
      expect(described_class.new(["--scaffold"]).send(:detect_mode)).to eq(:scaffold)
      expect(described_class.new(["--resolve"]).send(:detect_mode)).to eq(:resolve)

      allow(cli).to receive(:load_config).and_return({})
      expect(cli.send(:detect_mode)).to eq(:scaffold)

      allow(cli).to receive(:load_config).and_return(
        "appraisal_matrix" => {"gems" => {"tier1" => [{"versions" => ["1.0"]}]}}
      )
      expect(cli.send(:detect_mode)).to eq(:resolve)
    end

    it "detects whether a matrix contains versions" do
      expect(cli.send(:has_versions?, {})).to be(false)
      expect(cli.send(:has_versions?, "gems" => {"tier2" => [{"versions" => []}]})).to be(false)
      expect(cli.send(:has_versions?, "gems" => {"tier1" => [{"versions" => ["1.0"]}]})).to be(true)
    end

    it "handles freshness and human-readable elapsed times" do
      now = Time.now.to_i
      expect(cli.send(:fresh?, {})).to be(false)
      expect(cli.send(:fresh?, "resolved_at" => now, "freshness_ttl" => 60)).to be(true)
      expect(cli.send(:fresh?, "resolved_at" => now - 61, "freshness_ttl" => 60)).to be(false)
      expect(cli.send(:time_ago, nil)).to eq("unknown")
      expect(cli.send(:time_ago, now - 30)).to eq("0m")
      expect(cli.send(:time_ago, now - 3_600)).to eq("1h")
      expect(cli.send(:time_ago, now - 86_400)).to eq("1d")
    end

    it "round-trips configuration and finds a project gemspec" do
      Dir.mktmpdir do |project_dir|
        project_cli = described_class.new([], project_dir: project_dir)
        project_cli.send(:write_config, "answer" => 42)

        expect(project_cli.send(:load_config)).to eq("answer" => 42)
        expect(project_cli.send(:find_gemspec)).to be_nil

        gemspec = File.join(project_dir, "demo.gemspec")
        File.write(gemspec, "Gem::Specification.new do |s|\n  s.name = 'demo'\nend\n")
        expect(project_cli.send(:find_gemspec)).to eq(gemspec)
      end
    end

    it "raises when a gemspec cannot be loaded" do
      Dir.mktmpdir do |project_dir|
        path = File.join(project_dir, "broken.gemspec")
        File.write(path, "not a gemspec")

        expect { cli.send(:load_gemspec, path) }
          .to raise_error(Gem::InvalidSpecificationException, /Unable to load gemspec/)
      end
    end

    it "normalizes requirements and include/exclude version lists" do
      config = {
        "requirements" => [">= 1", ["< 3", " "]],
        "include_versions" => ["2.0", "1.0", "2.0"],
        "exclude_versions" => "1.0"
      }

      expect(cli.send(:gem_requirements, config)).to eq([">= 1", "< 3"])
      expect(cli.send(:gem_include_versions, config)).to eq(%w[1.0 2.0])
      expect(cli.send(:gem_exclude_versions, config)).to eq(["1.0"])
      expect(cli.send(:gem_requirements, {})).to be_nil
      expect(cli.send(:gem_include_versions, {})).to be_nil
      expect(cli.send(:gem_exclude_versions, {})).to be_nil
    end

    it "merges, excludes, and sorts versions" do
      expect(cli.send(:finalize_versions, ["2.0", "1.0"], ["3.0"], ["1.0"]))
        .to eq(%w[2.0 3.0])
      expect(cli.send(:subtract_versions, ["2.0", "1.0"], nil)).to eq(%w[1.0 2.0])
      expect(cli.send(:sort_versions, [nil, "2.0", "1.0", "2.0"])).to eq(%w[1.0 2.0])
    end

    it "checks tier2 compatibility conservatively" do
      resolver = instance_double(Kettle::Jem::Appraisals::GemVersionResolver)
      range = {"r3" => {ceiling: Gem::Version.new("3.2")}}

      expect(cli.send(:compatible?, "child", "1.0", "missing", range, resolver)).to be(true)
      allow(resolver).to receive(:versions).with("child").and_return([{number: "1.0.0"}])
      allow(resolver).to receive(:min_ruby_version).with("child", "1.0.0").and_return(Gem::Version.new("3.3"))
      expect(cli.send(:compatible?, "child", "1.0", "r3", range, resolver)).to be(false)
      allow(resolver).to receive(:min_ruby_version).with("child", "1.0.0").and_return(nil)
      expect(cli.send(:compatible?, "child", "1.0", "r3", range, resolver)).to be(true)
      allow(resolver).to receive(:versions).and_raise(StandardError)
      expect(cli.send(:compatible?, "child", "1.0", "r3", range, resolver)).to be(true)
    end

    it "selects the latest patch for a minor version" do
      resolver = instance_double(Kettle::Jem::Appraisals::GemVersionResolver)
      allow(resolver).to receive(:versions).with("child").and_return(
        [{number: "1.2.0"}, {number: "1.2.4"}, {number: "1.3.0"}]
      )

      expect(cli.send(:latest_minor_patch, "child", "1.2", resolver)).to eq("1.2.4")
      expect(cli.send(:latest_minor_patch, "child", "9.9", resolver)).to eq("9.9")
    end

    it "handles extra gemfile annotations and collapse policies" do
      entries = [{name: "one"}, {name: "two"}]
      cli.send(:annotate_extra_gemfiles, entries, [])
      expect(entries).to eq([{name: "one"}, {name: "two"}])
      expect(cli.send(:standard_appraisal_collapse_policy, {})).to eq(:unique)
      expect(cli.send(:standard_appraisal_collapse_policy, "collapse" => {"standard_appraisals" => "required"})).to eq(:required)
      expect(cli.send(:standard_appraisal_collapse_policy, "standard_appraisal_collapse" => "off")).to eq(:none)
      expect(cli.send(:standard_appraisal_name, {ruby_series: "missing"}, {})).to be_nil
    end

    it "handles version sort fallbacks and collapse selection" do
      expect(cli.send(:version_sort_key, nil)).to eq(Gem::Version.new("0"))
      expect(cli.send(:version_sort_key, "not-a-version")).to eq(Gem::Version.new("0"))
      entries = [
        {name: "old", tier1_version: "1.0", tier2_version: "1.0"},
        {name: "new", tier1_version: "2.0", tier2_version: "1.0"}
      ]

      expect(cli.send(:standard_appraisal_collapse_entry, entries, :none)).to be_nil
      expect(cli.send(:standard_appraisal_collapse_entry, entries.first(1), :unique)).to eq(entries.first)
      expect(cli.send(:standard_appraisal_collapse_entry, entries, :required)).to eq(entries.last)
    end
  end
end
