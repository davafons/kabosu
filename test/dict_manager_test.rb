require_relative "test_helper"
require "kabosu/dict_manager"

class DictManagerTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir
    @manager = Kabosu::DictManager.new(dir: @tmpdir)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  # Creates a fake .dic file at the expected path
  def stub_dic(version, edition)
    dir = File.join(@tmpdir, "sudachi-dictionary-#{version}")
    FileUtils.mkdir_p(dir)
    path = File.join(dir, "system_#{edition}.dic")
    FileUtils.touch(path)
    path
  end

  # ── installed ──

  def test_installed_empty_dir
    assert_equal [], @manager.installed
  end

  def test_installed_single
    stub_dic("20260116", "small")
    result = @manager.installed
    assert_equal 1, result.size
    assert_equal({ version: "20260116", edition: "small",
                   path: File.join(@tmpdir, "sudachi-dictionary-20260116", "system_small.dic") },
                 result.first)
  end

  def test_installed_multiple_editions_same_version
    stub_dic("20260116", "small")
    stub_dic("20260116", "core")
    editions = @manager.installed.map { _1[:edition] }
    assert_equal %w[small core], editions
  end

  def test_installed_multiple_versions_returns_newest_first
    stub_dic("20251022", "small")
    stub_dic("20260116", "small")
    versions = @manager.installed.map { _1[:version] }
    assert_equal %w[20260116 20251022], versions
  end

  def test_installed_ignores_non_dic_files
    dir = File.join(@tmpdir, "sudachi-dictionary-20260116")
    FileUtils.mkdir_p(dir)
    FileUtils.touch(File.join(dir, "LICENSE"))
    FileUtils.touch(File.join(dir, "system_small.dic"))
    assert_equal 1, @manager.installed.size
  end

  def test_installed_ignores_non_directory_entries
    FileUtils.touch(File.join(@tmpdir, "sudachi-dictionary-20260116"))
    assert_equal [], @manager.installed
  end

  # ── find ──

  def test_find_raises_when_nothing_installed
    assert_raises(Kabosu::DictManager::DictNotFound) { @manager.find }
  end

  def test_find_returns_only_available_edition
    stub_dic("20260116", "small")
    assert @manager.find.end_with?("system_small.dic")
  end

  def test_find_prefers_core_over_small
    stub_dic("20260116", "small")
    stub_dic("20260116", "core")
    assert @manager.find.end_with?("system_core.dic")
  end

  def test_find_prefers_full_over_core
    stub_dic("20260116", "core")
    stub_dic("20260116", "full")
    assert @manager.find.end_with?("system_full.dic")
  end

  def test_find_prefers_latest_version_over_better_edition
    # older version has full, newer only has small — newer wins
    stub_dic("20251022", "full")
    stub_dic("20260116", "small")
    assert @manager.find.include?("20260116")
    assert @manager.find.end_with?("system_small.dic")
  end

  def test_find_by_edition
    stub_dic("20260116", "small")
    stub_dic("20260116", "core")
    assert @manager.find(edition: "small").end_with?("system_small.dic")
    assert @manager.find(edition: "core").end_with?("system_core.dic")
  end

  def test_find_by_edition_raises_when_not_installed
    stub_dic("20260116", "small")
    assert_raises(Kabosu::DictManager::DictNotFound) { @manager.find(edition: "full") }
  end

  def test_find_by_edition_finds_across_versions
    stub_dic("20251022", "core")
    stub_dic("20260116", "small")
    # explicitly asking for core should find the older version
    assert @manager.find(edition: "core").include?("20251022")
  end

  # ── remove ──

  def test_remove_by_edition
    stub_dic("20260116", "small")
    stub_dic("20260116", "core")
    @manager.remove(edition: "small")
    editions = @manager.installed.map { _1[:edition] }
    refute_includes editions, "small"
    assert_includes editions, "core"
  end

  def test_remove_by_version
    stub_dic("20260116", "small")
    stub_dic("20251022", "small")
    @manager.remove(version: "20251022")
    versions = @manager.installed.map { _1[:version] }
    refute_includes versions, "20251022"
    assert_includes versions, "20260116"
  end

  def test_remove_by_edition_and_version
    stub_dic("20260116", "small")
    stub_dic("20260116", "core")
    stub_dic("20251022", "small")
    @manager.remove(edition: "small", version: "20260116")
    remaining = @manager.installed
    assert_equal 2, remaining.size
    refute remaining.any? { _1[:edition] == "small" && _1[:version] == "20260116" }
  end

  def test_remove_cleans_up_empty_version_directory
    stub_dic("20260116", "small")
    version_dir = File.join(@tmpdir, "sudachi-dictionary-20260116")
    @manager.remove(edition: "small")
    refute Dir.exist?(version_dir)
  end

  def test_remove_keeps_version_directory_when_other_editions_remain
    stub_dic("20260116", "small")
    stub_dic("20260116", "core")
    @manager.remove(edition: "small")
    version_dir = File.join(@tmpdir, "sudachi-dictionary-20260116")
    assert Dir.exist?(version_dir)
  end

  def test_remove_raises_when_nothing_matches
    stub_dic("20260116", "small")
    assert_raises(Kabosu::DictManager::DictNotFound) { @manager.remove(edition: "full") }
  end

  # ── validate_edition ──

  def test_install_rejects_invalid_edition
    assert_raises(ArgumentError) { @manager.install("xl") }
  end

  def test_install_accepts_case_insensitive_edition
    # Should not raise — just hit the network (we stub that out by checking the error type)
    error = assert_raises { @manager.install("SMALL", version: "00000000") }
    refute_instance_of ArgumentError, error
  end
end
