# frozen_string_literal: true
module Licensed
  module Commands
    class Cache < Command
      # Create a reporter to use during a command run
      #
      # options - The options the command was run with
      #
      # Raises a Licensed::Reporters::CacheReporter
      def create_reporter(options)
        Licensed::Reporters::CacheReporter.new
      end

      # Run the command.
      # Removes any cached records that don't match a current application
      # dependency.
      #
      # options - Options to run the command with
      #
      # Returns whether the command was a success
      def run(**options)
        begin
          @cache_paths = Set.new
          @files = Set.new

          result = super
          clear_stale_cached_records if result

          result
        ensure
          @cache_paths = nil
          @files = nil
        end
      end

      protected

      # Run the command for all enabled sources for an application configuration,
      # recording results in a report.
      #
      # app - An application configuration
      #
      # Returns whether the command succeeded for the application.
      def run_app(app)
        result = super
        @cache_paths << app.cache_path
        result
      end

      # Cache dependency record data.
      #
      # app - The application configuration for the dependency
      # source - The dependency source enumerator for the dependency
      # dependency - An application dependency
      # report - A report hash for the command to provide extra data for the report output.
      #
      # Returns true.
      def evaluate_dependency(app, source, dependency, report)
        if dependency.path.empty?
          report.errors << "dependency path not found"
          return false
        end

        filename = app.cache_path.join(source.class.type, "#{dependency.name}.#{DependencyRecord::EXTENSION}")
        @files << filename.to_s
        cached_record = Licensed::DependencyRecord.read(filename)
        if options[:force] || save_dependency_record?(dependency, cached_record)
          if dependency.record.matches?(cached_record)
            # use the cached license value if the license text wasn't updated
            dependency.record["license"] = cached_record["license"]
          elsif cached_record && app.reviewed?(dependency.record)
            # if the license text changed and the dependency is set as reviewed
            # force a re-review of the dependency
            dependency.record["review_changed_license"] = true
          end

          dependency.record.save(filename)
          report["cached"] = true
        end

        if !dependency.exist?
          report.warnings << "expected dependency path #{dependency.path} does not exist"
        end

        true
      end

      # Determine if the current dependency's record should be saved.
      # The record should be saved if:
      # 1. there is no cached record
      # 2. the cached record doesn't have a version set
      # 3. the cached record version doesn't match the current dependency version
      #
      # dependency - An application dependency
      # cached_record - A dependency record to compare with the dependency
      #
      # Returns true if dependency's record should be saved
      def save_dependency_record?(dependency, cached_record)
        return true if cached_record.nil?

        cached_version = cached_record["version"]
        return true if cached_version.nil? || cached_version.empty?
        return true if dependency.version != cached_version
        false
      end

      # Clean up cached files that dont match current dependencies
      #
      # app - An application configuration
      # source - A dependency source enumerator
      #
      # Returns nothing
      def clear_stale_cached_records
        @cache_paths.each do |cache_path|
          Dir.glob(cache_path.join("**/*.#{DependencyRecord::EXTENSION}")).each do |file|
            next if @files.include?(file)

            FileUtils.rm(file)
          end
        end
      end
    end
  end
end
