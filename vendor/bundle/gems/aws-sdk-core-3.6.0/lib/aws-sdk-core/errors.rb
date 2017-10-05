require 'thread'

module Aws
  module Errors

    class NonSupportedRubyVersionError < RuntimeError; end

    # The base class for all errors returned by an Amazon Web Service.
    # All ~400 level client errors and ~500 level server errors are raised
    # as service errors.  This indicates it was an error returned from the
    # service and not one generated by the client.
    class ServiceError < RuntimeError

      # @param [Seahorse::Client::RequestContext] context
      # @param [String] message
      def initialize(context, message)
        @code = self.class.code
        @context = context
        super(message)
      end

      # @return [String]
      attr_reader :code

      # @return [Seahorse::Client::RequestContext] The context of the request
      #   that triggered the remote service to return this error.
      attr_reader :context

      class << self

        # @return [String]
        attr_accessor :code

      end
    end

    # Various plugins perform client-side checksums of responses.
    # This error indicates a checksum failed.
    class ChecksumError < RuntimeError; end

    # Raised when a client is constructed and the specified shared
    # credentials profile does not exist.
    class NoSuchProfileError < RuntimeError; end

    # Raised when a client is constructed, where Assume Role credentials are
    # expected, and there is no source profile specified.
    class NoSourceProfileError < RuntimeError; end

    # Raised when a client is constructed and credentials are not
    # set, or the set credentials are empty.
    class MissingCredentialsError < RuntimeError
      def initialize(*args)
        msg = 'unable to sign request without credentials set'
        super(msg)
      end
    end

    # Raised when a client is constructed and region is not specified.
    class MissingRegionError < ArgumentError
      def initialize(*args)
        msg = "missing region; use :region option or "
        msg << "export region name to ENV['AWS_REGION']"
        super(msg)
      end
    end

    # Raised when attempting to connect to an endpoint and a `SocketError`
    # is received from the HTTP client. This error is typically the result
    # of configuring an invalid `:region`.
    class NoSuchEndpointError < RuntimeError

      def initialize(options = {})
        @context = options[:context]
        @endpoint = @context.http_request.endpoint
        @original_error = options[:original_error]
        super(<<-MSG)
Encountered a `SocketError` while attempting to connect to:

  #{endpoint.to_s}

This is typically the result of an invalid `:region` option or a
poorly formatted `:endpoint` option.

* Avoid configuring the `:endpoint` option directly. Endpoints are constructed
  from the `:region`. The `:endpoint` option is reserved for connecting to
  non-standard test endpoints.

* Not every service is available in every region.

* Never suffix region names with availability zones.
  Use "us-east-1", not "us-east-1a"

Known AWS regions include (not specific to this service):

#{possible_regions}
        MSG
      end

      attr_reader :context

      attr_reader :endpoint

      attr_reader :original_error

      private

      def possible_regions
        Aws.partitions.inject([]) do |region_names, partition|
          partition.regions.each do |region|
            region_names << region.name
          end
          region_names
        end.join("\n")
      end

    end

    # This module is mixed into another module, providing dynamic
    # error classes.  Error classes all inherit from {ServiceError}.
    #
    #     # creates and returns the class
    #     Aws::S3::Errors::MyNewErrorClass
    #
    # Since the complete list of possible AWS errors returned by services
    # is not known, this allows us to create them as needed.  This also
    # allows users to rescue errors by class without them being concrete
    # classes beforehand.
    #
    # @api private
    module DynamicErrors

      def self.extended(submodule)
        submodule.instance_variable_set("@const_set_mutex", Mutex.new)
        submodule.const_set(:ServiceError, Class.new(ServiceError))
      end

      def const_missing(constant)
        set_error_constant(constant)
      end

      # Given the name of a service and an error code, this method
      # returns an error class (that extends {ServiceError}.
      #
      #     Aws::S3::Errors.error_class('NoSuchBucket').new
      #     #=> #<Aws::S3::Errors::NoSuchBucket>
      #
      # @api private
      def error_class(error_code)
        constant = error_class_constant(error_code)
        if error_const_set?(constant)
          const_get(constant)
        else
          set_error_constant(constant)
        end
      end

      private

      # Convert an error code to an error class name/constant.
      # This requires filtering non-safe characters from the constant
      # name and ensuring it begins with an uppercase letter.
      # @param [String] error_code
      # @return [Symbol] Returns a symbolized constant name for the given
      #   `error_code`.
      def error_class_constant(error_code)
        constant = error_code.to_s
        constant = constant.gsub(/https?:.*$/, '')
        constant = constant.gsub(/[^a-zA-Z0-9]/, '')
        constant = 'Error' + constant unless constant.match(/^[a-z]/i)
        constant = constant[0].upcase + constant[1..-1]
        constant.to_sym
      end

      def set_error_constant(constant)
        @const_set_mutex.synchronize do
          # Ensure the const was not defined while blocked by the mutex
          if error_const_set?(constant)
            const_get(constant)
          else
            error_class = Class.new(const_get(:ServiceError))
            error_class.code = constant.to_s
            const_set(constant, error_class)
          end
        end
      end

      def error_const_set?(constant)
        # Purposefully not using #const_defined? as that method returns true
        # for constants not defined directly in the current module.
        constants.include?(constant.to_sym)
      end

    end
  end
end
