# frozen_string_literal: true

RSpec.describe Kettle::Jem::Appraisals::ConfigFile do
  let(:project_dir) { File.join(Dir.pwd, "tmp", "test_config_file") }
  let(:config_file) { described_class.new(project_dir: project_dir) }
  let(:canonical) { File.join(project_dir, ".structuredmerge", "kettle-jem.yml") }
  let(:legacy) { File.join(project_dir, ".kettle-jem.yml") }

  before { FileUtils.mkdir_p(project_dir) }
  after { FileUtils.rm_rf(project_dir) }

  describe "#path" do
    it "defaults to the canonical kettle-jem config when no config exists" do
      expect(config_file.path).to eq(canonical)
      expect(config_file.relative_path).to eq(".structuredmerge/kettle-jem.yml")
    end

    it "falls back to a legacy root config when only that exists" do
      File.write(legacy, "appraisal_matrix: {}\n")

      expect(config_file.path).to eq(legacy)
      expect(config_file.relative_path).to eq(".kettle-jem.yml")
    end

    it "prefers the canonical config over a legacy one" do
      FileUtils.mkdir_p(File.dirname(canonical))
      File.write(canonical, "appraisal_matrix: {}\n")
      File.write(legacy, "appraisal_matrix: {}\n")

      expect(config_file.path).to eq(canonical)
    end
  end

  describe "#load" do
    it "returns an empty hash when no config exists" do
      expect(config_file.load).to eq({})
    end

    it "reads the canonical config" do
      FileUtils.mkdir_p(File.dirname(canonical))
      File.write(canonical, "appraisal_matrix:\n  mode: minor\n")

      expect(config_file.load).to eq("appraisal_matrix" => {"mode" => "minor"})
    end
  end

  describe "#write" do
    let(:original) do
      <<~YAML
        # kettle-jem configuration
        tokens:
          forge:
            org: galtzo-floss

        # Appraisal matrix, owned by kettle-jem-appraisals
        appraisal_matrix:
          mode: semver
          gems:
            tier1:
            - name: activerecord

        # Workflow settings
        workflows:
          exec_cmd: kettle-test # inline comment
      YAML
    end

    before do
      FileUtils.mkdir_p(File.dirname(canonical))
      File.write(canonical, original)
    end

    it "creates the canonical config, including its directory, when missing" do
      FileUtils.rm_rf(File.dirname(canonical))

      config_file.write("appraisal_matrix" => {"mode" => "minor"})

      expect(YAML.load_file(canonical)).to eq("appraisal_matrix" => {"mode" => "minor"})
    end

    it "replaces only the changed section and preserves comments and other sections" do
      config = config_file.load
      config["appraisal_matrix"]["resolved_at"] = 1_700_000_000

      config_file.write(config)

      content = File.read(canonical)
      expect(content).to include("# kettle-jem configuration\n")
      expect(content).to include("# Appraisal matrix, owned by kettle-jem-appraisals\n")
      expect(content).to include("# Workflow settings\n")
      expect(content).to include("exec_cmd: kettle-test # inline comment\n")
      expect(content).to include("resolved_at: 1700000000")
      expect(YAML.safe_load(content)).to eq(config)
    end

    it "keeps the comment that introduces the following section in place" do
      config = config_file.load
      config["appraisal_matrix"]["mode"] = "minor"

      config_file.write(config)

      lines = File.read(canonical).lines
      comment_index = lines.index("# Workflow settings\n")
      expect(lines[comment_index + 1]).to eq("workflows:\n")
      expect(lines[0...comment_index].join).to include("mode: minor")
    end

    it "appends a section that does not exist yet" do
      config = config_file.load.merge("test_bundle" => {"gemfiles" => ["gemfiles/modular/example.gemfile"]})

      config_file.write(config)

      content = File.read(canonical)
      expect(content).to start_with("# kettle-jem configuration\n")
      expect(YAML.safe_load(content)).to eq(config)
    end

    it "keeps indented comments that trail the rewritten section" do
      File.write(canonical, <<~YAML)
        appraisal_matrix:
          mode: minor
          resolved_at: 1
          # preset: framework
          # framework_matrix:
          #   dimension: activerecord
        workflows:
          exec_cmd: kettle-test
      YAML
      config = config_file.load
      config["appraisal_matrix"]["resolved_at"] = 2

      config_file.write(config)

      expect(File.read(canonical)).to eq(<<~YAML)
        appraisal_matrix:
          mode: minor
          resolved_at: 2
          # preset: framework
          # framework_matrix:
          #   dimension: activerecord
        workflows:
          exec_cmd: kettle-test
      YAML
    end

    it "leaves the file byte-for-byte unchanged when nothing changed" do
      config_file.write(config_file.load)

      expect(File.read(canonical)).to eq(original)
    end

    it "updates the final section of the file" do
      config = config_file.load
      config["workflows"] = {"exec_cmd" => "rake spec"}

      config_file.write(config)

      content = File.read(canonical)
      expect(content).to include("# Appraisal matrix, owned by kettle-jem-appraisals\n")
      expect(YAML.safe_load(content)).to eq(config)
    end
  end
end
