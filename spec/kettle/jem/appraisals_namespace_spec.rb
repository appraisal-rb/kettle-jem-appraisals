# frozen_string_literal: true

RSpec.describe Kettle::Jem::Appraisals do
  describe ".display_path" do
    it "returns nil unchanged" do
      expect(described_class.display_path(nil)).to be_nil
    end

    it "normalizes the workspace home prefix for user-facing output" do
      expect(described_class.display_path("/var/home/pboling/src/project"))
        .to eq("/home/pboling/src/project")
    end

    it "leaves unrelated paths unchanged" do
      expect(described_class.display_path("/tmp/project")).to eq("/tmp/project")
    end
  end
end
