#!/usr/bin/env ruby
#
# encoding: utf-8

# Copyright (c) [2015] SUSE LLC
#
# All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of version 2 of the GNU General Public License as published
# by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, contact SUSE LLC.
#
# To contact SUSE LLC about this file by physical or electronic mail, you may
# find current contact information at www.suse.com.

require "yast"
require "yastx"
require "storage"

module Yast
  module Storage
    #
    # Singleton class for the libstorage object.
    #
    # You can simply use StorageManager.instance to use it and create a
    # libstorage instance if there isn't one yet; this will use common default
    # parameters for creating it.
    #
    # If you need special parameters for creating it, you can use
    # StorageManager.create_instance with a custom ::Storage::Environment
    # (notice the difference between the global ::Storage namespace which is
    # libstorage and this Yast::Storage namespace).
    #
    # By default (unless disabled in the ::Storage::Environment), creating the
    # instance will also start hardware probing. This is why there is an alias
    # name StorageManager.start_probing to make this explicit.
    #
    class StorageManager
      include Yast::Logger
      #
      # Class methods
      #
      class << self
        @instance = nil
        @logger   = nil

        # Return the singleton for the libstorage object. This will create one
        # for the first call, which will also trigger hardware probing.
        #
        # @return [::Storage::Storage] libstorage object
        #
        def instance
          create_instance unless @instance
          @instance
        end

        # Create the singleton for the libstorage object.
        #
        # Create your own Storage::Environment for custom purposes like mocking
        # the hardware probing etc.
        #
        # @return [::Storage::Storage] libstorage object
        #
        def create_instance(storage_environment = nil)

          if !storage_environment
            case "A"
            when "A"                  # probe
              storage_environment = ::Storage::Environment.new(true)

            when "B"                  # probe and write probed data to disk
              storage_environment = ::Storage::Environment.new(true, ::Storage::ProbeMode_STANDARD_WRITE_DEVICEGRAPH,
                                                               ::Storage::TargetMode_DIRECT)
            when "C"                 # instead of probing read probed data from disk
              storage_environment = ::Storage::Environment.new(true, ::Storage::ProbeMode_READ_DEVICEGRAPH,
                                                               ::Storage::TargetMode_DIRECT)
            end

            storage_environment.devicegraph_filename = "./devicegraph.xml"
            storage_environment.arch_filename = "./arch.xml"
          end

          create_logger
          log.info("Creating Storage object")
          @instance = ::Storage::Storage.new(storage_environment)
        end

        alias_method :start_probing, :create_instance

        private

        def create_logger
          @logger = StorageLogger.new
          ::Storage.logger = @logger
        end
      end

      # Logger class for libstorage. This is needed to make libstorage log to the
      # y2log.
      class StorageLogger < ::Storage::Logger
        def initialize
          super
        end

        def write(level, component, filename, line, function, content)
          Yast.y2_logger(level, component, filename, line, function, content)
        end
      end
    end
  end
end