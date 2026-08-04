# frozen_string_literal: true

RSpec.describe Kettle::Jem::Appraisals::SubDepResolver do
  let(:resolver) { instance_double(Kettle::Jem::Appraisals::GemVersionResolver) }
  let(:subject_resolver) { described_class.new(resolver: resolver) }

  describe "#resolve" do
    it "returns an empty hash when the parent version is unavailable" do
      allow(resolver).to receive(:versions).with("parent").and_return([{number: "1.2.3"}])
      allow(resolver).to receive(:version_info).with("parent", "1.2.3").and_return(nil)

      expect(subject_resolver.resolve("parent", "1.2")).to eq({})
    end

    it "excludes standard-library dependencies and resolves the rest" do
      allow(resolver).to receive(:versions).with("parent").and_return([{number: "1.2.3"}])
      allow(resolver).to receive(:version_info).with("parent", "1.2.3").and_return(
        runtime_dependencies: [
          {name: "version_gem", requirements: ">= 1"},
          {name: "child", requirements: "~> 2.0"}
        ]
      )
      allow(resolver).to receive(:versions).with("child").and_return([{number: "2.0.0"}])

      expect(subject_resolver.resolve("parent", "1.2")).to eq("child" => "2.0.0")
    end

    it "omits a dependency when no compatible version can be resolved" do
      allow(resolver).to receive(:versions).with("parent").and_return([{number: "1.2.3"}])
      allow(resolver).to receive(:version_info).with("parent", "1.2.3").and_return(
        runtime_dependencies: [{name: "child", requirements: "~> 2.0"}]
      )
      allow(resolver).to receive(:versions).with("child").and_return([{number: "1.0.0"}])

      expect(subject_resolver.resolve("parent", "1.2")).to eq({})
    end

    it "uses the newest compatible sub-dependency without a Ruby constraint" do
      allow(resolver).to receive(:versions).with("parent").and_return([{number: "1.2.3"}])
      allow(resolver).to receive(:version_info).with("parent", "1.2.3").and_return(
        runtime_dependencies: [{name: "child", requirements: "< 3"}]
      )
      allow(resolver).to receive(:versions).with("child").and_return(
        [{number: "1.0.0"}, {number: "2.0.0"}, {number: "3.0.0"}]
      )

      expect(subject_resolver.resolve("parent", "1.2")).to eq("child" => "2.0.0")
    end

    it "uses the newest Ruby-compatible version when a Ruby floor is supplied" do
      ruby_min = Gem::Version.new("3.1")
      allow(resolver).to receive(:versions).with("parent").and_return([{number: "1.2.3"}])
      allow(resolver).to receive(:version_info).with("parent", "1.2.3").and_return(
        runtime_dependencies: [{name: "child", requirements: ">= 1"}]
      )
      allow(resolver).to receive(:versions).with("child").and_return(
        [{number: "1.0.0"}, {number: "2.0.0"}, {number: "3.0.0"}]
      )
      allow(resolver).to receive(:min_ruby_version).with("child", "3.0.0").and_return(Gem::Version.new("3.2"))
      allow(resolver).to receive(:min_ruby_version).with("child", "2.0.0").and_return(Gem::Version.new("3.0"))

      expect(subject_resolver.resolve("parent", "1.2", ruby_min: ruby_min)).to eq("child" => "2.0.0")
    end

    it "returns the oldest compatible version when none meet the Ruby floor" do
      ruby_min = Gem::Version.new("2.7")
      allow(resolver).to receive(:versions).with("parent").and_return([{number: "1.2.3"}])
      allow(resolver).to receive(:version_info).with("parent", "1.2.3").and_return(
        runtime_dependencies: [{name: "child", requirements: ">= 1"}]
      )
      allow(resolver).to receive(:versions).with("child").and_return(
        [{number: "1.0.0"}, {number: "2.0.0"}]
      )
      allow(resolver).to receive(:min_ruby_version).with("child", anything).and_return(Gem::Version.new("3.0"))

      expect(subject_resolver.resolve("parent", "1.2", ruby_min: ruby_min)).to eq("child" => "1.0.0")
    end

    it "uses the default requirement when a dependency requirement is malformed" do
      allow(resolver).to receive(:versions).with("parent").and_return([{number: "1.2.3"}])
      allow(resolver).to receive(:version_info).with("parent", "1.2.3").and_return(
        runtime_dependencies: [{name: "child", requirements: "not a requirement"}]
      )
      allow(resolver).to receive(:versions).with("child").and_return([{number: "1.0.0"}])

      expect(subject_resolver.resolve("parent", "1.2")).to eq("child" => "1.0.0")
    end

    it "returns no value when a sub-dependency has no versions" do
      allow(resolver).to receive(:versions).with("parent").and_return([{number: "1.2.3"}])
      allow(resolver).to receive(:version_info).with("parent", "1.2.3").and_return(
        runtime_dependencies: [{name: "child", requirements: ">= 1"}]
      )
      allow(resolver).to receive(:versions).with("child").and_return([])

      expect(subject_resolver.resolve("parent", "1.2")).to eq({})
    end
  end
end
