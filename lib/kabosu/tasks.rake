require "kabosu/dict_manager"

namespace :kabosu do
  # ── Install ──

  desc "Install the core dictionary (default). VERSION=YYYYMMDD to pin a specific release."
  task :install do
    Kabosu::DictManager.new.install("core", version: ENV.fetch("VERSION", nil))
  end

  namespace :install do
    desc "Install the small dictionary. VERSION=YYYYMMDD to pin a specific release."
    task :small do
      Kabosu::DictManager.new.install("small", version: ENV.fetch("VERSION", nil))
    end

    desc "Install the core dictionary. VERSION=YYYYMMDD to pin a specific release."
    task :core do
      Kabosu::DictManager.new.install("core", version: ENV.fetch("VERSION", nil))
    end

    desc "Install the full dictionary. VERSION=YYYYMMDD to pin a specific release."
    task :full do
      Kabosu::DictManager.new.install("full", version: ENV.fetch("VERSION", nil))
    end
  end

  desc "Install a dictionary only if a matching one isn't already on disk. " \
       "EDITION=core|small|full (default core), VERSION=YYYYMMDD optional."
  task :install_if_missing do
    edition = ENV["EDITION"] || "core"
    Kabosu::DictManager.new.install_if_missing(edition, version: ENV.fetch("VERSION", nil))
  end

  # ── Remove ──

  desc "Remove all installed dictionaries, or a specific one with EDITION=small|core|full and/or VERSION=YYYYMMDD"
  task :remove do
    Kabosu::DictManager.new.remove(edition: ENV.fetch("EDITION", nil), version: ENV.fetch("VERSION", nil))
  end

  namespace :remove do
    desc "Remove the small dictionary."
    task :small do
      Kabosu::DictManager.new.remove(edition: "small", version: ENV.fetch("VERSION", nil))
    end

    desc "Remove the core dictionary."
    task :core do
      Kabosu::DictManager.new.remove(edition: "core", version: ENV.fetch("VERSION", nil))
    end

    desc "Remove the full dictionary."
    task :full do
      Kabosu::DictManager.new.remove(edition: "full", version: ENV.fetch("VERSION", nil))
    end
  end

  # ── Info ──

  desc "List installed Sudachi dictionaries"
  task :list do
    manager = Kabosu::DictManager.new
    dicts = manager.installed

    if dicts.empty?
      puts "No dictionaries installed. Run: rake kabosu:install"
    else
      puts "Installed dictionaries (#{manager.dir}):"
      puts
      dicts.each do |d|
        size_mb = (File.size(d[:path]).to_f / 1024 / 1024).round(1)
        puts "  #{d[:version]} / #{d[:edition].ljust(5)} (#{size_mb} MB)"
        puts "    #{d[:path]}"
      end
    end
  end

  desc "Show available dictionary versions from GitHub"
  task :versions do
    Kabosu::DictManager.new.available_versions.each { |v| puts v }
  end

  desc "Show the path to the best available dictionary. EDITION=small|core|full to be specific."
  task :path do
    puts Kabosu::DictManager.new.find(edition: ENV.fetch("EDITION", nil))
  rescue Kabosu::DictManager::DictNotFound => e
    warn e.message
    exit 1
  end
end
