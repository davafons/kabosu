require "net/http"
require "uri"
require "fileutils"
require "json"
require "zip"

module Kabosu
  class DictManager
    EDITIONS = %w[small core full].freeze
    EDITION_PRIORITY = %w[full core small].freeze
    GITHUB_REPO = "WorksApplications/SudachiDict"
    GITHUB_API = "https://api.github.com"

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
        $stderr.puts "Already installed: #{dic_path}"
        return dic_path
      end

      url = release_asset_url(version, edition)
      zip_path = File.join(@dir, "sudachi-dictionary-#{version}-#{edition}.zip")

      FileUtils.mkdir_p(@dir)
      download(url, zip_path)
      extract(zip_path, @dir)
      FileUtils.rm_f(zip_path)

      unless File.exist?(dic_path)
        raise DownloadError, "Expected #{dic_path} after extraction, but file not found"
      end

      $stderr.puts "Installed: #{dic_path}"
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

      Dir.glob(File.join(@dir, "sudachi-dictionary-*")).sort.reverse.each do |version_dir|
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
        $stderr.puts "Removed: #{d[:path]}"

        # Clean up empty version directories
        version_dir = File.dirname(d[:path])
        dics_remaining = Dir.glob(File.join(version_dir, "system_*.dic"))
        if dics_remaining.empty?
          FileUtils.rm_rf(version_dir)
          $stderr.puts "Removed empty directory: #{version_dir}"
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

    def release_asset_url(version, edition)
      "https://github.com/#{GITHUB_REPO}/releases/download/v#{version}/sudachi-dictionary-#{version}-#{edition}.zip"
    end

    def download(url, dest)
      $stderr.puts "Downloading #{url}..."
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
              if total && total > 0
                pct = (written * 100 / total).clamp(0, 100)
                $stderr.print "\r  #{(written.to_f / 1024 / 1024).round(1)} / #{(total.to_f / 1024 / 1024).round(1)} MB (#{pct}%)"
              end
            end
          end

          $stderr.puts "\r  #{(written.to_f / 1024 / 1024).round(1)} MB downloaded"
        end
      end
    end

    def resolve_redirects(uri, limit: 5)
      raise DownloadError, "Too many redirects" if limit == 0

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
      raise DownloadError, "Too many redirects" if redirect_limit == 0

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

    def extract(zip_path, dest_dir)
      $stderr.puts "Extracting..."
      Zip::File.open(zip_path) do |archive|
        archive.each do |entry|
          target = File.join(dest_dir, entry.name)
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
