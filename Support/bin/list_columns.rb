#!/usr/bin/env ruby -W0

require "yaml"
require File.join(File.dirname(__FILE__), '..', 'lib', "rails_bundle_tools")
require File.join(File.dirname(__FILE__), '..', 'lib', "search_utilities")
require File.join(ENV['TM_SUPPORT_PATH'], 'lib', 'progress')
require File.join(ENV['TM_SUPPORT_PATH'], 'lib', 'current_word')

module TextMate
  class ListColumns
    CACHE_DIR      = File.join(TextMate.project_directory, "tmp", "textmate")
    CACHE_FILE     = File.join(CACHE_DIR, "attribute_cache.yml")
    RELOAD_MESSAGE = "Reload database schema..."
    RAILS_REGEX    = /^Rails (\d\.?){3}(\w+)?$/
    
    def run!(current_word=current_word)
      TextMate.exit_show_tool_tip("Place cursor on class name (or variation) to show its schema") if current_word.nil? || current_word.empty?
      # TextMate.exit_show_tool_tip("You don't have Rails installed in this gemset.") unless rails_present?

      klass = Inflector.singularize(Inflector.underscore(current_word))

      if cache[klass]
        display_menu(klass)
      elsif cache[klass_without_undescore = klass.split('_').last]
        display_menu(klass_without_undescore)
      elsif initials_match = cache.keys.detect { |word| first_letter_of_each_word(word) == current_word }
        display_menu(initials_match)
      else
        options = [
          @error || "'#{Inflector.camelize(klass)}' is not an Active Record derived class or was not recognised as a class.", 
          nil,
          cache.keys.map { |model_name| "Use #{Inflector.camelize(model_name)}..." }.sort,
          nil,
          RELOAD_MESSAGE
        ].flatten
        selected = TextMate::UI.menu(options)

        return if selected.nil?

        case options[selected]
        when options.first
          if @error && @error =~ /^#{TextMate.project_directory}(.+?)[:]?(\d+)/
            TextMate.open(File.join(TextMate.project_directory, $1), $2.to_i)
          else
            klass_file = File.join(TextMate.project_directory, "/app/models/#{klass}.rb")
            TextMate.open(klass_file) if File.exist?(klass_file)
          end
        when RELOAD_MESSAGE
          cache_attributes and run!
        else
          klass = Inflector.singularize(Inflector.underscore(options[selected].split[1].delete('...')))
          clone_cache(klass, current_word) and display_menu(current_word)
        end
      end
    end
    
    def cache_attributes
      _cache = {}
      File.delete(CACHE_FILE) if File.exists?(CACHE_FILE)

      TextMate.call_with_progress(:title => "Contacting database", :message => "Fetching database schema...") do
        self.update_cache(_cache)
      end

      return _cache
    end
    
    def cache_attributes_in_background
      _cache = {}
      File.delete(CACHE_FILE) if File.exists?(CACHE_FILE)
      self.update_cache(_cache)

      return _cache
    end
    
   protected
   
   def first_letter_of_each_word(string)
     string.split('_').map { |word| word[0,1] }.join("")
   end
   
    def update_cache(_cache)
      begin
        require "#{TextMate.project_directory}/config/environment"

        Dir.glob(File.join(Rails.root, "app/models/**/**/*.rb")) do |file|
          klass = nil
          begin
            klass = File.basename(file, '.*').camelize.constantize
          rescue Exception =>  e
          end
          
          if klass and klass.class.is_a?(Class) and klass.ancestors.include?(ActiveRecord::Base)
            _cache[klass.name.underscore] = { :associations => klass.reflections.stringify_keys.keys, :columns => klass.column_names, :constants => klass.class_variables - ActiveRecord::Base.class_variables }
          end
        end

        File.open(CACHE_FILE, 'w') { |out| YAML.dump(_cache, out ) }
        
      rescue Exception => e
        @error_message = "Fix it: #{e.message}"
      end
    end
   
    def clone_cache(klass, new_word)
      cached_model = cache[klass]
      cache[new_word] = cached_model

      File.open(CACHE_FILE, 'w') { |out| YAML.dump(cache, out ) }
    end
   
    def display_menu(klass)
      columns      = cache[klass][:columns]
      associations = cache[klass][:associations]
      constants    = cache[klass][:constants]

      options = associations.empty? ? [] : associations + [nil]
      options += constants.map { |constant| constant.gsub('@@', '') } + [nil]
      
      search_term = TextMate::UI.request_string(:title => "Find attribute", :prompt => "Attribute name")      
      options = array_sorted_search(options, search_term) unless search_term.nil? or search_term == ''
      
      options += columns + [nil, RELOAD_MESSAGE] + [nil, "(Listing attributes for #{Inflector.classify(klass)})"]
      
      
      valid_options = options.select { |e| !e.nil? and e != RELOAD_MESSAGE }
      if(valid_options.size == 1)
        out = valid_options.first
      elsif valid_options.size == 0
        TextMate.exit_show_tool_tip("No matching results")
      else
        
        selected = TextMate::UI.menu(options)
        return if selected.nil?

        if options[selected] == RELOAD_MESSAGE
          cache_attributes and run!
        end
        
        out = options[selected]
      end

      out = ".#{out}" unless input_text =~ /\.$/
      TextMate.exit_insert_text(out)
    end
   
    def cache
      Dir.mkdir(CACHE_DIR) unless File.exists?(CACHE_DIR)
      @cache ||= File.exist?(CACHE_FILE) ? YAML.load(File.read(CACHE_FILE)) : cache_attributes
    end
    
    def current_word
      @current_word ||= input_text.split('.').select { |e| e != '' }.last
    end
    
    def input_text
      Word.current_word('_a-zA-Z0-9.', :left)
    end
    
    def rails_present?
      rails_version_command = "rails -v 2> /dev/null"
      return `#{rails_version_command}` =~ RAILS_REGEX || `bundle exec #{rails_version_command}` =~ RAILS_REGEX
    end
    
  end
end


TextMate::ListColumns.new.cache_attributes_in_background  if ENV['TM_CACHE_IN_BACKGROUND']