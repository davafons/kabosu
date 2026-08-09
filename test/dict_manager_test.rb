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
    refute(remaining.any? { _1[:edition] == "small" && _1[:version] == "20260116" })
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

  # ── default_dir ──

  def test_default_dir_falls_back_to_home
    ENV.delete("KABOSU_DICT_DIR")
    assert_equal File.join(Dir.home, ".kabosu", "dict"), Kabosu::DictManager.default_dir
  end

  def test_default_dir_honors_env_var
    original = ENV.fetch("KABOSU_DICT_DIR", nil)
    ENV["KABOSU_DICT_DIR"] = "/tmp/custom-kabosu-dict"
    assert_equal "/tmp/custom-kabosu-dict", Kabosu::DictManager.default_dir
  ensure
    if original.nil?
      ENV.delete("KABOSU_DICT_DIR")
    else
      ENV["KABOSU_DICT_DIR"] = original
    end
  end

  # ── install_if_missing ──

  def test_install_if_missing_returns_existing_path_without_network
    path = stub_dic("20260116", "core")
    # Sentinel: if it tried to hit the network, latest_version would raise here
    @manager.define_singleton_method(:latest_version) { raise "should not be called" }
    assert_equal path, @manager.install_if_missing("core")
  end

  def test_install_if_missing_returns_existing_when_version_matches
    path = stub_dic("20260116", "small")
    @manager.define_singleton_method(:latest_version) { raise "should not be called" }
    assert_equal path, @manager.install_if_missing("small", version: "20260116")
  end

  def test_install_if_missing_falls_through_when_version_mismatches
    stub_dic("20260116", "small")
    # Asking for a different version should attempt install (which we'll let
    # bubble out as a non-ArgumentError network/HTTP failure).
    error = assert_raises { @manager.install_if_missing("small", version: "00000000") }
    refute_instance_of ArgumentError, error
  end

  def test_install_if_missing_falls_through_when_edition_missing
    stub_dic("20260116", "small")
    error = assert_raises { @manager.install_if_missing("full", version: "00000000") }
    refute_instance_of ArgumentError, error
  end

  def test_install_if_missing_rejects_invalid_edition
    assert_raises(ArgumentError) { @manager.install_if_missing("xl") }
  end

  # ── Release asset discovery ─ ──

  # The legacy zip is always present as a candidate. When the GitHub release
  # API is unreachable or returns no wheel assets, the wheel candidate is
  # omitted, leaving a single fallback path so an offline / 404 caller still
  # gets a meaningful failure.
  def test_pick_release_sources_includes_legacy_zip_when_api_missing
    @manager.define_singleton_method(:fetch_release) { |_v| nil }
    sources = @manager.send(:pick_release_sources, "20260428", "full")
    assert_equal 1, sources.length
    assert_equal :zip, sources.first[:format]
    assert_match(%r{sudachi-dictionary-20260428-full\.zip\z}, sources.first[:url])
  end

  # When the API exposes only wheel assets (v20260723+), the wheel becomes
  # the second candidate alongside the (404'ing) legacy zip.
  def test_pick_release_sources_adds_wheel_when_only_wheel_asset_exists
    payload = {
      "tag_name" => "v20260723",
      "assets" => [
        { "name" => "sudachidict_full-20260723-py3-none-any.whl",
          "browser_download_url" => "https://github.com/WorksApplications/SudachiDict/releases/download/v20260723/sudachidict_full-20260723-py3-none-any.whl" },
        { "name" => "sudachidict_full-20260723.tar.gz",
          "browser_download_url" => "https://github.com/WorksApplications/SudachiDict/releases/download/v20260723/sudachidict_full-20260723.tar.gz" }
      ]
    }.to_json

    @manager.define_singleton_method(:fetch_release) { |_v| JSON.parse(payload) }

    sources = @manager.send(:pick_release_sources, "20260723", "full")
    formats = sources.map { _1[:format] }
    assert_equal %i[zip wheel], formats
    assert_match(%r{sudachidict_full-20260723-py3-none-any\.whl\z}, sources.last[:url])
  end

  # `extract` lands a wheel's `system.dic` at `dest_dir/system_{edition}.dic`
  # so `find`/`installed` keep working without a separate code path.
  def test_extract_renames_wheel_system_dic
    Dir.mktmpdir do |wheel|
      wheel_zip = File.join(wheel, "test.whl")
      Zip::File.open(wheel_zip, create: true) do |z|
        z.get_output_stream("sudachidict_full/resources/system.dic") { |io| io.write("fake dic bytes") }
      end

      Dir.mktmpdir do |dest|
        @manager.send(:extract, wheel_zip, dest, edition: "full")
        assert File.exist?(File.join(dest, "system_full.dic"))
        refute File.exist?(File.join(dest, "system.dic"))
        refute File.exist?(File.join(dest, "sudachidict_full", "resources", "system.dic"))
      end
    end
  end

  # When `edition:` is nil (legacy zips with edition in the file name), extract
  # passes entries through unchanged.
  def test_extract_legacy_zip_passes_entries_through
    Dir.mktmpdir do |zip|
      zip_path = File.join(zip, "test.zip")
      Zip::File.open(zip_path, create: true) do |z|
        z.get_output_stream("system_full.dic") { |io| io.write("fake dic bytes") }
      end

      Dir.mktmpdir do |dest|
        @manager.send(:extract, zip_path, dest)
        assert File.exist?(File.join(dest, "system_full.dic"))
      end
    end
  end
end
