# Changelog

[![SemVer 2.0.0][📌semver-img]][📌semver] [![Keep-A-Changelog 1.0.0][📗keep-changelog-img]][📗keep-changelog]

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog][📗keep-changelog],
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html),
and [yes][📌major-versions-not-sacred], platform and engine support are part of the [public API][📌semver-breaking].
Please file a bug if you notice a violation of semantic versioning.

[📌semver]: https://semver.org/spec/v2.0.0.html
[📌semver-img]: https://img.shields.io/badge/semver-2.0.0-FFDD67.svg?style=flat
[📌semver-breaking]: https://github.com/semver/semver/issues/716#issuecomment-869336139
[📌major-versions-not-sacred]: https://tom.preston-werner.com/2022/05/23/major-version-numbers-are-not-sacred.html
[📗keep-changelog]: https://keepachangelog.com/en/1.0.0/
[📗keep-changelog-img]: https://img.shields.io/badge/keep--a--changelog-1.0.0-FFDD67.svg?style=flat

## 0.1.0

- Initial release

## [Unreleased]

### Added

### Changed

### Deprecated

### Removed

### Fixed

- Unique generated appraisal entries now collapse onto standard `ruby-X-Y`
  appraisals, allowing kettle-jem templates to reuse badge-linked standard jobs
  instead of adding redundant framework-only appraisals.
- Ruby bucket detection now honors `.kettle-jem.yml` `ruby.test_minimum`, so
  collapsed appraisals do not target standard Ruby appraisals below the
  templated CI floor.
- Added a configurable standard appraisal collapse policy for projects whose
  matrixed dependency is required by the normal test suite; duplicate Ruby
  buckets can now collapse the newest compatible entry onto the standard
  `ruby-X-Y` appraisal while keeping older compatibility entries separate.
- Generated Appraisals can now include shared support gemfiles, so framework
  matrices that need adapter/setup dependencies do not have to use a separate
  kettle-jem framework matrix just to compose those dependencies.
- Replaced ad hoc gemspec parsing in the CLI with real gemspec loading and
  `Kettle::Jem::GemSpecReader` metadata from the active local `kettle-jem`.
- Generated Appraisals now strip the leading `gemfiles/` path segment so
  Appraisal2 resolves modular gemfiles from the correct root.
- Generated Appraisals no longer end with an extra blank line.
- Kept Ruby series detection compatible with released `kettle-jem` versions
  that do not yet export the appraisal minimum Ruby floor constant.

### Security
