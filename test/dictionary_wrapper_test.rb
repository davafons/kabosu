require_relative "test_helper"
require "kabosu"

class DictionaryWrapperTest < Minitest::Test
  def with_stubbed_dictionary_singleton
    singleton = class << Kabosu::Dictionary
                  self
                end

    singleton.class_eval do
      alias_method :__orig_new_for_test, :_new
      remove_method :_new
    end

    singleton.define_method(:_new) { |config, system_dict, user_dicts| [config, system_dict, user_dicts] }

    yield
  ensure
    singleton.class_eval do
      remove_method :_new
      alias_method :_new, :__orig_new_for_test
      remove_method :__orig_new_for_test
    end
  end

  def test_dictionary_new_requires_config_or_system_dict
    with_stubbed_dictionary_singleton do
      assert_raises(ArgumentError) { Kabosu::Dictionary.new }
    end
  end

  def test_dictionary_new_passes_config
    with_stubbed_dictionary_singleton do
      assert_equal ["/tmp/sudachi.json", nil, nil], Kabosu::Dictionary.new(config: "/tmp/sudachi.json")
    end
  end

  def test_dictionary_new_passes_system_dict_with_default_config
    with_stubbed_dictionary_singleton do
      assert_equal [Kabosu::Dictionary::DEFAULT_CONFIG_PATH, "/tmp/system.dic", nil],
                   Kabosu::Dictionary.new(system_dict: "/tmp/system.dic")
    end
  end

  def test_dictionary_new_forwards_user_dicts
    with_stubbed_dictionary_singleton do
      user_dicts = ["/tmp/domain.dic", "/tmp/names.dic"]
      assert_equal [Kabosu::Dictionary::DEFAULT_CONFIG_PATH, "/tmp/system.dic", user_dicts],
                   Kabosu::Dictionary.new(system_dict: "/tmp/system.dic", user_dicts: user_dicts)
    end
  end

  def test_dictionary_new_rejects_unknown_keyword
    with_stubbed_dictionary_singleton do
      assert_raises(ArgumentError) { Kabosu::Dictionary.new(system_dict: "/tmp/system.dic", foo: "bar") }
    end
  end

  def test_dictionary_new_validates_argument_types
    with_stubbed_dictionary_singleton do
      assert_raises(ArgumentError) { Kabosu::Dictionary.new(config: 123) }
      assert_raises(ArgumentError) { Kabosu::Dictionary.new(system_dict: 123) }
      assert_raises(ArgumentError) { Kabosu::Dictionary.new(system_dict: "/tmp/system.dic", user_dicts: "bad") }
      assert_raises(ArgumentError) do
        Kabosu::Dictionary.new(system_dict: "/tmp/system.dic", user_dicts: ["/tmp/u.dic", 123])
      end
    end
  end

  def test_dictionary_new_wraps_config_errors
    with_stubbed_dictionary_singleton do
      singleton = class << Kabosu::Dictionary
                    self
                  end
      singleton.send(:remove_method, :_new)
      singleton.send(:define_method, :_new) do |_config, _system_dict, _user_dicts|
        raise "failed to parse setting.json"
      end

      assert_raises(Kabosu::ConfigError) { Kabosu::Dictionary.new(config: "/tmp/sudachi.json") }
    end
  end

  def test_dictionary_new_wraps_dictionary_errors
    with_stubbed_dictionary_singleton do
      singleton = class << Kabosu::Dictionary
                    self
                  end
      singleton.send(:remove_method, :_new)
      singleton.send(:define_method, :_new) do |_config, _system_dict, _user_dicts|
        raise "dictionary not found"
      end

      assert_raises(Kabosu::DictionaryError) { Kabosu::Dictionary.new(system_dict: "/tmp/system.dic") }
    end
  end
end
