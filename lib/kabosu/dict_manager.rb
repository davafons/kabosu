require "net/http"
require "uri"
require "fileutils"
require "json"
require "zip"

module Kabosu
  class DictManager
    EDITIONS = %w[small core full].freeze
    EDITION_PRIORITY = %w[full core small].freeze
    GITHUB_REPO = "WorksApplications/SudachiDict".freeze
    GITHUB_API = "https://api.github.com".freeze

    class DictNotFound < StandardError; end
    class DownloadError < StandardError; end

    # Default storage directory. Honors KABOSU_DICT_DIR so consumers can point
    # the gem at a Docker volume / shared mount without subclassing or threading
    # `dir:` through every call site. Falls back to ~/.kabosu/dict/.
    def self.default_dir
      ENV["KABOSU_DICT_DIR"] || File.join(Dir.home, ".kabosu", "dict")
    end

    def initialize(dir: self.class.default_dir)
      @dir = dir
    end

    attr_reader :dir

    # ── Install ──

    # Download and extract a dictionary edition.
    #
    #   manager.install("small")
    #   manager.install("core", version: "20260116")
    #
    def install(edition = "core", version: nil)
      edition = validate_edition(edition)
      version ||= latest_version

      dest_dir = File.join(@dir, "sudachi-dictionary-#{version}")
      dic_path = File.join(dest_dir, "system_#{edition}.dic")

      if File.exist?(dic_path)
        warn "Already installed: #{dic_path}"
        return dic_path
      end

      FileUtils.mkdir_p(@dir)

      # SudachiDict switched to Python-only release assets in v20260723:
      # https://github.com/WorksApplications/SudachiDict/releases/tag/v20260723
      # The legacy `sudachi-dictionary-{version}-{edition}.zip` is gone; the
      # new releases ship `sudachidict_{edition}-{version}-py3-none-any.whl`
      # (a PEP 427 wheel). Pick whichever exists, preferring the legacy zip
      # when both are present (older releases kept both formats in flight).
      sources = pick_release_sources(version, edition)
      raise DownloadError, "No downloadable assets for #{version}/#{edition}" if sources.empty?

      sources.each do |source|
        begin
          download(source.fetch(:url), source.fetch(:archive_path))
          extract(source.fetch(:archive_path), dest_dir, edition: edition)
          FileUtils.rm_f(source.fetch(:archive_path))
          break
        rescue DownloadError => e
          FileUtils.rm_f(source.fetch(:archive_path)) if File.exist?(source.fetch(:archive_path))
          # Try the next candidate (e.g. wheel if the zip 404s). If this was
          # the last one, surface the original error.
          raise if sources.last.equal?(source)

          warn "  falling back: #{e.message}"
        end
      end

      raise DownloadError, "Expected #{dic_path} after extraction, but file not found" unless File.exist?(dic_path)

      warn "Installed: #{dic_path}"
      dic_path
    end

    # Idempotent install. Returns the existing dictionary path if a matching
    # one is already on disk; otherwise downloads and extracts. Useful for
    # entrypoint scripts and CI hooks that should converge on the desired
    # state without paying the network cost on every run.
    #
    #   manager.install_if_missing("core")
    #   manager.install_if_missing("core", version: "20260116")
    #
    def install_if_missing(edition = "core", version: nil)
      edition = validate_edition(edition)
      matching = installed.find do |d|
        d[:edition] == edition && (version.nil? || d[:version] == version)
      end
      return matching[:path] if matching

      install(edition, version: version)
    end

    # ── Discovery ──

    # List all installed dictionaries.
    # Returns an array of hashes: { version:, edition:, path: }
    def installed
      results = []
      return results unless Dir.exist?(@dir)

      Dir.glob(File.join(@dir, "sudachi-dictionary-*")).reverse.each do |version_dir|
        next unless File.directory?(version_dir)

        version = File.basename(version_dir).sub("sudachi-dictionary-", "")
        EDITIONS.each do |edition|
          dic = File.join(version_dir, "system_#{edition}.dic")
          next unless File.exist?(dic)

          results << { version: version, edition: edition, path: dic }
        end
      end

      results
    end

    # Find the best available dictionary path.
    # Prefers: latest version, then full > core > small.
    def find(edition: nil)
      candidates = installed
      raise DictNotFound, "No dictionaries installed. Run: rake kabosu:install" if candidates.empty?

      if edition
        edition = validate_edition(edition)
        match = candidates.find { |d| d[:edition] == edition }
        raise DictNotFound, "No #{edition} dictionary installed" unless match

        return match[:path]
      end

      # Group by version (already sorted newest-first), pick best edition
      by_version = candidates.group_by { |d| d[:version] }
      latest_version_dicts = by_version.values.first

      best = EDITION_PRIORITY.each do |ed|
        found = latest_version_dicts.find { |d| d[:edition] == ed }
        break found if found
      end

      best.is_a?(Hash) ? best[:path] : latest_version_dicts.first[:path]
    end

    # ── Remove ──

    # Remove a specific dictionary edition, or an entire version.
    def remove(edition: nil, version: nil)
      targets = installed
      targets = targets.select { |d| d[:version] == version } if version
      targets = targets.select { |d| d[:edition] == edition } if edition

      raise DictNotFound, "No matching dictionary found" if targets.empty?

      targets.each do |d|
        FileUtils.rm_f(d[:path])
        warn "Removed: #{d[:path]}"

        # Clean up empty version directories
        version_dir = File.dirname(d[:path])
        dics_remaining = Dir.glob(File.join(version_dir, "system_*.dic"))
        if dics_remaining.empty?
          FileUtils.rm_rf(version_dir)
          warn "Removed empty directory: #{version_dir}"
        end
      end
    end

    # ── Version resolution ──

    # Fetch the latest release tag from GitHub.
    def latest_version
      uri = URI("#{GITHUB_API}/repos/#{GITHUB_REPO}/releases/latest")
      response = http_get(uri, headers: { "Accept" => "application/json" })
      data = JSON.parse(response.body)
      tag = data["tag_name"]
      # Tags are like "v20260116" — strip the "v" prefix
      tag.sub(/\Av/, "")
    end

    # List available versions from GitHub releases.
    def available_versions
      uri = URI("#{GITHUB_API}/repos/#{GITHUB_REPO}/releases")
      response = http_get(uri, headers: { "Accept" => "application/json" })
      JSON.parse(response.body).map { |r| r["tag_name"].sub(/\Av/, "") }
    end

    private

    def validate_edition(edition)
      edition = edition.to_s.downcase
      unless EDITIONS.include?(edition)
        raise ArgumentError, "Unknown edition '#{edition}'. Must be one of: #{EDITIONS.join(", ")}"
      end

      edition
    end

    # Look up the GitHub release for `version` and return an ordered list of
    # candidate download sources. The legacy `sudachi-dictionary-{version}-{edition}.zip`
    # is preferred when present (matches the layout every other consumer
    # assumes); otherwise we fall back to the SudachiDict Python wheel,
    # which is what v20260723+ ship and which carries `system.dic` inside
    # `sudachidict_{edition}/resources/`.
    #
    # On GitHub API failure we degrade to the legacy zip URL alone: an old
    # release that 404s on the zip *also* 404s on the wheel, so falling back
    # to "guessed" candidates costs nothing and keeps the code path simple
    # for offline / no-network callers.
    def pick_release_sources(version, edition)
      candidates = []
      zip = release_asset_url(version, edition)
      candidates << { url: zip, archive_path: File.join(@dir, "sudachi-dictionary-#{version}-#{edition}.zip"), format: :zip }

      begin
        release = fetch_release(version)
        if release
          wheel_name = "sudachidict_#{edition}-#{version}-py3-none-any.whl"
          wheel = release["assets"].to_a.find { |a| a["name"] == wheel_name }
          if wheel && wheel["browser_download_url"]
            candidates << {
              url: wheel.fetch("browser_download_url"),
              archive_path: File.join(@dir, wheel_name),
              format: :wheel
            }
          end
        end
      rescue DownloadError
        # API failure is fine: keep the legacy-zip candidate; the user will
        # see a clean 404 if neither asset actually exists on disk.
      end

      candidates
    end

    def fetch_release(version)
      uri = URI("#{GITHUB_API}/repos/#{GITHUB_REPO}/releases/tags/v#{version}")
      response = http_get(uri, headers: { "Accept" => "application/json" })
      return nil unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end

    def release_asset_url(version, edition)
      "https://github.com/#{GITHUB_REPO}/releases/download/v#{version}/sudachi-dictionary-#{version}-#{edition}.zip"
    end

    def download(url, dest)
      warn "Downloading #{url}..."
      uri = resolve_redirects(URI(url))

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(Net::HTTP::Get.new(uri)) do |response|
          unless response.is_a?(Net::HTTPSuccess)
            raise DownloadError, "Failed to download: #{response.code} #{response.message}"
          end

          total = response["Content-Length"]&.to_i
          written = 0

          File.open(dest, "wb") do |f|
            response.read_body do |chunk|
              f.write(chunk)
              written += chunk.bytesize
              if total&.positive?
                pct = (written * 100 / total).clamp(0, 100)
                done_mb = (written.to_f / 1024 / 1024).round(1)
                total_mb = (total.to_f / 1024 / 1024).round(1)
                $stderr.print "\r  #{done_mb} / #{total_mb} MB (#{pct}%)"
              end
            end
          end

          warn "\r  #{(written.to_f / 1024 / 1024).round(1)} MB downloaded"
        end
      end
    end

    def resolve_redirects(uri, limit: 5)
      raise DownloadError, "Too many redirects" if limit.zero?

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        response = http.request(Net::HTTP::Head.new(uri))
        case response
        when Net::HTTPRedirection
          resolve_redirects(URI(response["location"]), limit: limit - 1)
        else
          uri
        end
      end
    end

    def http_get(uri, headers: {}, redirect_limit: 5)
      raise DownloadError, "Too many redirects" if redirect_limit.zero?

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")

      request = Net::HTTP::Get.new(uri)
      headers.each { |k, v| request[k] = v }

      response = http.request(request)

      case response
      when Net::HTTPRedirection
        http_get(URI(response["location"]), headers: headers, redirect_limit: redirect_limit - 1)
      else
        response
      end
    end

    def extract(zip_path, dest_dir, edition: nil)
      warn "Extracting..."
      Zip::File.open(zip_path) do |archive|
        archive.each do |entry|
          # Wheels (`sudachidict_{edition}/resources/system.dic`) carry the
          # edition in the top-level directory; legacy zips name the file
          # `system_{edition}.dic` already. When the entry is a `system.dic`
          # inside a wheel and `edition:` was passed, land it at
          # `dest_dir/system_{edition}.dic` so `find`/`installed` keep working
          # without a separate code path.
          target_name = entry.name
          if edition && File.basename(entry.name) == "system.dic"
            target_name = "system_#{edition}.dic"
          end

          target = File.join(dest_dir, target_name)
          # Guard against zip-slip — refuse entries that escape dest_dir.
          unless File.expand_path(target).start_with?(File.expand_path(dest_dir) + File::SEPARATOR)
            raise DownloadError, "Refusing to extract entry outside dest_dir: #{entry.name}"
          end

          FileUtils.mkdir_p(File.dirname(target))
          entry.extract(target) { true } # overwrite existing
        end
      end
    rescue Zip::Error => e
      raise DownloadError, "Failed to extract #{zip_path}: #{e.message}"
    end
  end
end
