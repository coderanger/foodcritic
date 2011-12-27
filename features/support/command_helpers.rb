module FoodCritic

  # Helpers for asserting that the correct warnings are displayed.
  #
  # Unless the environment variable FC_FORK_PROCESS is set to 'true' then the features will be run in the same process.
  module CommandHelpers

    # The warning codes and messages displayed to the end user.
    WARNINGS = {
      'FC001' => 'Use strings in preference to symbols to access node attributes',
      'FC002' => 'Avoid string interpolation where not required',
      'FC003' => 'Check whether you are running with chef server before using server-specific features',
      'FC004' => 'Use a service resource to start and stop services',
      'FC005' => 'Avoid repetition of resource declarations',
      'FC006' => 'Mode should be quoted or fully specified when setting file permissions',
      'FC007' => 'Ensure recipe dependencies are reflected in cookbook metadata',
      'FC008' => 'Generated cookbook metadata needs updating',
      'FC009' => 'Resource attribute not recognised',
      'FC010' => 'Invalid search syntax',
      'FC011' => 'Missing README in markdown format',
      'FC012' => 'Use Markdown for README rather than RDoc',
      'FC013' => 'Use file_cache_path rather than hard-coding tmp paths',
      'FC014' => 'Consider extracting long ruby_block to library',
      'FC015' => 'Consider converting definition to a LWRP',
      'FC016' => 'LWRP does not declare a default action',
      'FC017' => 'LWRP does not notify when updated',
      'FC018' => 'LWRP uses deprecated notification syntax'
    }

    # If the cucumber features should run foodcritic in the same process or spawn a separate process.
    def self.running_in_process?
      ! (ENV.has_key?('FC_FORK_PROCESS') and ENV['FC_FORK_PROCESS'] == true.to_s)
    end

    # Expect a warning to be included in the command output.
    #
    # @param [String] code The warning code to check for.
    # @param [Hash] options The warning options.
    # @option options [Integer] :line The line number the warning should appear on - nil for any line.
    # @option options [Boolean] :expect_warning If false then assert that a warning is NOT present
    # @option options [String] :file The path to the file the warning should be raised against
    # @option options [Symbol] :file_type Alternative to specifying file name. One of: :attributes, :definition, :metadata, :provider
    def expect_warning(code, options={})
      if options.has_key?(:file_type)
        options[:file] = {:attributes => 'attributes/default.rb', :definition => 'definitions/apache_site.rb',
                          :metadata => 'metadata.rb', :provider => 'providers/site.rb'}[options[:file_type]]
      end
      options = {:line => 1, :expect_warning => true, :file => 'recipes/default.rb'}.merge!(options)
      warning = "#{code}: #{WARNINGS[code]}: cookbooks/example/#{options[:file]}:#{options[:line]}#{"\n" if ! options[:line].nil?}"
      options[:expect_warning] ? expect_output(warning) : expect_no_output(warning)
    end

    # Expect a warning not to be included in the command output.
    #
    # @see CommandHelpers#expect_warning
    def expect_no_warning(code, options={:expect_warning => false})
      expect_warning(code, options)
    end
  end

  # Helpers used when features are executed in-process.
  module InProcessHelpers

    # Assert that the output contains the specified warning.
    #
    # @param [String] warning The warning to check for.
    def expect_output(warning)
      @review.should include(warning)
    end

    # Assert that the output does not contain the specified warning.
    #
    # @param [String] warning The warning to check for.
    def expect_no_output(warning)
      @review.should_not include(warning)
    end

    # Assert that no error occurred following a lint check.
    def assert_no_error_occurred
      @status.should == 0
    end

    # Run a lint check with the provided command line arguments.
    #
    # @param [Array] cmd_args The command line arguments.
    def run_lint(cmd_args)
      in_current_dir do
        review, @status = FoodCritic::Linter.check(cmd_args)
        @review = review.nil? || (review.respond_to?(:warnings) && review.warnings.empty?) ? '' : "#{review.to_s}\n"
      end
    end

    # Assert that the usage message is displayed.
    #
    # @param [Boolean] is_exit_zero The exit code to check for.
    def usage_displayed(is_exit_zero)
      expect_output 'foodcritic [cookbook_path]'
      @review.should match /( )+-t, --tags TAGS( )+Only check against rules with the specified tags./
      if is_exit_zero
        @status.should == 0
      else
        @status.should_not == 0
      end
    end

  end

  # Helpers used when features are executed out of process.
  module ArubaHelpers

    # Assert that the output contains the specified warning.
    #
    # @param [String] warning The warning to check for.
    def expect_output(warning)
      assert_partial_output(warning, all_output)
    end

    # Assert that the output does not contain the specified warning.
    #
    # @param [String] warning The warning to check for.
    def expect_no_output(warning)
      assert_no_partial_output(warning, all_output)
    end

    # Assert that no error occurred following a lint check.
    def assert_no_error_occurred
      assert_exit_status(0)
    end

    # Run a lint check with the provided command line arguments.
    #
    # @param [Array] cmd_args The command line arguments.
    def run_lint(cmd_args)
      run_simple(unescape("foodcritic #{cmd_args.join(' ')}"), false)
    end

    # Assert that the usage message is displayed.
    #
    # @param [Boolean] is_exit_zero The exit code to check for.
    def usage_displayed(is_exit_zero)
      assert_partial_output 'foodcritic [cookbook_path]', all_output
      assert_matching_output('( )+-t, --tags TAGS( )+Only check against rules with the specified tags.', all_output)
      if is_exit_zero
        assert_exit_status 0
      else
        assert_not_exit_status 0
      end
    end
  end

end

World(FoodCritic::CommandHelpers)
if FoodCritic::CommandHelpers.running_in_process?
  World(FoodCritic::InProcessHelpers)
else
  World(FoodCritic::ArubaHelpers)
end
