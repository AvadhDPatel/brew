# typed: strict
# frozen_string_literal: true

require "abstract_command" # Base class for Homebrew commands.
require "fetch"            # Module for fetching resources.
require "cask/download"    # Handles downloading casks.

module Homebrew
  module Cmd
    # This class implements the `--cache` command in Homebrew.
    # It displays the cache directory used by Homebrew or specific cached files for given formulae or casks.
    class Cache < AbstractCommand
      include Fetch

      # Returns the command name as "--cache".
      sig { override.returns(String) }
      def self.command_name = "--cache"

      # Command-line arguments for the `--cache` command.
      cmd_args do
        description <<~EOS
          Display Homebrew's download cache. See also `HOMEBREW_CACHE`.

          If a <formula> or <cask> is provided, display the file or directory used to cache it.
        EOS

        # Flags and switches for additional filters and options.
        flag "--os=",
             description: "Show cache file for the given operating system. " \
                          "(Pass `all` to show cache files for all operating systems.)"
        flag "--arch=",
             description: "Show cache file for the given CPU architecture. " \
                          "(Pass `all` to show cache files for all architectures.)"
        switch "-s", "--build-from-source",
               description: "Show the cache file used when building from source."
        switch "--force-bottle",
               description: "Show the cache file used when pouring a bottle."
        flag "--bottle-tag=",
             description: "Show the cache file used when pouring a bottle for the given tag."
        switch "--HEAD",
               description: "Show the cache file used when building from HEAD."
        switch "--formula", "--formulae",
               description: "Only show cache files for formulae."
        switch "--cask", "--casks",
               description: "Only show cache files for casks."

        # Ensure certain arguments are mutually exclusive.
        conflicts "--build-from-source", "--force-bottle", "--bottle-tag", "--HEAD", "--cask"
        conflicts "--formula", "--cask"
        conflicts "--os", "--bottle-tag"
        conflicts "--arch", "--bottle-tag"

        # Allows specifying named arguments like formulae or casks.
        named_args [:formula, :cask]
      end

      # Main method that runs the `--cache` command.
      sig { override.void }
      def run
        # If no formula or cask is specified, display the general cache directory.
        if args.no_named?
          puts HOMEBREW_CACHE
          return
        end

        # Retrieve the formulae or casks specified as arguments.
        formulae_or_casks = args.named.to_formulae_and_casks

        # Generate combinations of OS and architecture from user input.
        os_arch_combinations = args.os_arch_combinations

        # Process each formula or cask provided by the user.
        formulae_or_casks.each do |formula_or_cask|
          case formula_or_cask
          when Formula
            # If the argument is a formula, handle formula-specific caching.
            formula = formula_or_cask
            ref = formula.loaded_from_api? ? formula.full_name : formula.path

            # Iterate over OS and architecture combinations.
            os_arch_combinations.each do |os, arch|
              # Simulate the specified system environment.
              SimulateSystem.with(os:, arch:) do
                # Reload the formula in the simulated environment.
                formula = Formulary.factory(ref)
                # Display the cache location for the formula.
                print_formula_cache(formula, os:, arch:)
              end
            end
          when Cask::Cask
            # If the argument is a cask, handle cask-specific caching.
            cask = formula_or_cask
            ref = cask.loaded_from_api? ? cask.full_name : cask.sourcefile_path

            os_arch_combinations.each do |os, arch|
              # Skip processing for Linux, as casks are macOS-specific.
              next if os == :linux

              # Simulate the specified system environment.
              SimulateSystem.with(os:, arch:) do
                # Reload the cask in the simulated environment.
                loaded_cask = Cask::CaskLoader.load(ref)
                # Display the cache location for the cask.
                print_cask_cache(loaded_cask)
              end
            end
          else
            # Raise an error for invalid argument types.
            raise "Invalid type: #{formula_or_cask.class}"
          end
        end
      end

      private

      # Displays the cache location for a formula based on various filters.
      sig { params(formula: Formula, os: Symbol, arch: Symbol).void }
      def print_formula_cache(formula, os:, arch:)
        # Check if a bottle should be fetched for the formula.
        if fetch_bottle?(
          formula,
          force_bottle:               args.force_bottle?,
          bottle_tag:                 args.bottle_tag&.to_sym,
          build_from_source_formulae: args.build_from_source_formulae,
          os:                         args.os&.to_sym,
          arch:                       args.arch&.to_sym,
        )
          # Determine the bottle tag to use.
          bottle_tag = if (bottle_tag = args.bottle_tag&.to_sym)
            Utils::Bottles::Tag.from_symbol(bottle_tag)
          else
            Utils::Bottles::Tag.new(system: os, arch:)
          end

          # Retrieve the bottle information for the formula.
          bottle = formula.bottle_for_tag(bottle_tag)

          # Handle missing bottle information.
          if bottle.nil?
            opoo "Bottle for tag #{bottle_tag.to_sym.inspect} is unavailable."
            return
          end

          # Print the cache location for the bottle.
          puts bottle.cached_download
        elsif args.HEAD?
          # Handle HEAD builds if specified.
          if (head = formula.head)
            puts head.cached_download
          else
            opoo "No head is defined for #{formula.full_name}."
          end
        else
          # Default to printing the general cache location for the formula.
          puts formula.cached_download
        end
      end

      # Displays the cache location for a cask.
      sig { params(cask: Cask::Cask).void }
      def print_cask_cache(cask)
        puts Cask::Download.new(cask).downloader.cached_location
      end
    end
  end
end
