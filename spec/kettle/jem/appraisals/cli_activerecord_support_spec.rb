# frozen_string_literal: true

RSpec.describe Kettle::Jem::Appraisals::CLI do
  let(:project_dir) { File.join(Dir.pwd, "tmp", "test_cli_activerecord_support") }
  let(:cli) { described_class.new([], project_dir: project_dir) }
  let(:tier1_gems) { [{"name" => "activerecord"}] }
  let(:entries) do
    [
      {name: "kja-ar-6-1-r2.6", tier1_name: "activerecord", tier1_version: "6.1"},
      {name: "kja-ar-8-0-r3", tier1_name: "activerecord", tier1_version: "8.0", extra_gemfiles: ["modular/combustion.gemfile"]}
    ]
  end

  before { FileUtils.mkdir_p(project_dir) }
  after { FileUtils.rm_rf(project_dir) }

  describe "#annotate_activerecord_support" do
    it "generates support gemfiles and wires the one matching each entry's ActiveRecord version" do
      expect {
        cli.send(:annotate_activerecord_support, entries, tier1_gems, {})
      }.to output(include("gemfiles/modular/activerecord_support.gemfile")).to_stdout

      expect(entries.first[:extra_gemfiles]).to eq(["modular/activerecord_support.gemfile"])
      expect(entries.last[:extra_gemfiles]).to eq(["modular/activerecord_support_modern.gemfile", "modular/combustion.gemfile"])
      expect(File).to exist(File.join(project_dir, "gemfiles/modular/activerecord_support_modern.gemfile"))
    end

    it "does nothing when activerecord is not a tier1 gem" do
      cli.send(:annotate_activerecord_support, entries, [{"name" => "sequel"}], {})

      expect(entries.first).not_to have_key(:extra_gemfiles)
      expect(Dir.exist?(File.join(project_dir, "gemfiles"))).to be(false)
    end

    it "can be disabled with activerecord_support: false" do
      cli.send(:annotate_activerecord_support, entries, tier1_gems, {"activerecord_support" => false})

      expect(entries.first).not_to have_key(:extra_gemfiles)
      expect(Dir.exist?(File.join(project_dir, "gemfiles"))).to be(false)
    end

    it "defers to support gemfiles already configured in appraisal_gemfiles" do
      matrix = {"appraisal_gemfiles" => ["gemfiles/modular/activerecord_support.gemfile"]}

      cli.send(:annotate_activerecord_support, entries, tier1_gems, matrix)

      expect(entries.first).not_to have_key(:extra_gemfiles)
      expect(Dir.exist?(File.join(project_dir, "gemfiles"))).to be(false)
    end
  end

  describe "#annotate_extra_gemfiles" do
    it "merges configured gemfiles with gemfiles already on the entry" do
      entry = {name: "kja-ar-8-0-r3", extra_gemfiles: ["modular/activerecord_support_modern.gemfile"]}

      cli.send(:annotate_extra_gemfiles, [entry], ["modular/combustion.gemfile", "modular/activerecord_support_modern.gemfile"])

      expect(entry[:extra_gemfiles]).to eq(["modular/activerecord_support_modern.gemfile", "modular/combustion.gemfile"])
    end
  end

  describe "config file location" do
    it "reads appraisal_matrix from .structuredmerge/kettle-jem.yml" do
      FileUtils.mkdir_p(File.join(project_dir, ".structuredmerge"))
      File.write(File.join(project_dir, ".structuredmerge/kettle-jem.yml"), "appraisal_matrix:\n  mode: minor\n")

      expect(cli.send(:load_config)).to eq("appraisal_matrix" => {"mode" => "minor"})
    end
  end
end
