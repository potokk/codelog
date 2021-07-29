require 'date'
require 'yaml'
require 'fileutils'

module Codelog
  module Command
    module Step
      class Version
        include FileUtils
        UNRELEASED_LOGS_PATH = 'changelogs/unreleased'.freeze
        CONFIG_FILE_PATH = 'changelogs/codelog.yml'.freeze
        RELEASES_PATH = 'changelogs/releases'.freeze
        PREFIX_CATEGORY = 'Задачи'.freeze

        def initialize(version, release_date, outputter)
          abort(Codelog::Message::Error.missing_config_file) unless config_file_exists?
          @version = version
          @release_date = Date.strptime(release_date, Codelog::Config.date_input_format).to_s
          @outputter = outputter
        rescue ArgumentError
          abort(Codelog::Message::Error.invalid_date_format)
        end

        def self.run(version, release_date, outputter)
          Codelog::Command::Step::Version.new(version, release_date, outputter).run
        end

        def run
          abort(Codelog::Message::Error.missing_version_number) if @version.nil?
          abort(Codelog::Message::Error.already_existing_version(@version)) if version_exists?
          abort(Codelog::Message::Error.no_detected_changes(@version)) unless unreleased_changes?

          @outputter.print generate_changelog_content_from(changes_hash)
        end

        private

        def generate_changelog_content_from(changes_hash)
          file_content = StringIO.new
          file_content.puts "## #{Codelog::Config.version_tag(@version, @release_date)}"
          changes_hash.each do |category, changes|
            file_content.puts "### #{category}"
            add_entry(file_content, changes)
            file_content.puts "\n"
          end
          file_content.puts "---\n"
          file_content.string
        end

        def changes_hash
          change_files_paths = Dir["#{UNRELEASED_LOGS_PATH}/*.yml"]

          change_files_paths.inject({}) do |all_changes, change_file|
            changes_per_category = YAML.load_file(change_file)
            task_prefix = begin
              changes_per_category[PREFIX_CATEGORY]
                   .flatten
                   .select { |str| !str.nil? && !str.empty? }
                   .map { |str| str.match(/((PTK)|(APP)|(ptk)|(app))-\d+\Z/).to_s }
                   .select { |str| !str.nil? && !str.empty? }
                   .join(', ')
            rescue
              ''
            end

            changes_per_category.each do |category, entries|
              all_changes[category] ||= []
              next if entries.nil? || entries.empty?

              entries = entries.select { |str| !str.nil? && !str.empty? }
              next if entries.empty?

              if category != PREFIX_CATEGORY && !task_prefix.empty?
                entries = entries.map { |entry| [task_prefix, entry].join(' - ') }
              end
              all_changes[category] += entries
            end

            all_changes
          end
        rescue Psych::SyntaxError => error
          abort(Codelog::Message::Error.could_not_parse_yaml(error))
        end

        def add_entry(line, changes, level = 0)
          if changes.is_a?(Hash)
            changes.each do |key, values|
              line.puts "#{"\t" * level}- #{key}"
              add_entry(line, values, level + 1)
            end
          elsif changes.is_a?(Array)
            changes.each { |change| add_entry(line, change, level) }
          else
            line.puts "#{"\t" * level}- #{changes}"
          end
        end

        def version_exists?
          File.file?("#{RELEASES_PATH}/#{@version}.md")
        end

        def unreleased_changes?
          Dir["#{UNRELEASED_LOGS_PATH}/*.yml"].any?
        end

        def config_file_exists?
          File.file?(CONFIG_FILE_PATH)
        end
      end
    end
  end
end
