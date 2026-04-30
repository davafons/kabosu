require "rails/railtie"

module Kabosu
  class Railtie < Rails::Railtie
    rake_tasks do
      load File.expand_path("tasks.rake", __dir__)
    end
  end
end
