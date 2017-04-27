# encoding: utf-8

# Copyright (c) [2017] SUSE LLC
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

require "storage"

module Y2Storage
  # Mixin that enables a class to become a wrap around one of the classes
  # provided by the libstorage Ruby bindings.
  #
  # Libstorage is a language-agnostic and multi-purpose library and its Ruby
  # bindings are auto-generated by SWIG. As a result of that, accessing directly
  # to the libstorage API (the Storage namespace) from the YaST code has some
  # drawbacks. The API is not completely Ruby-like and sometimes it does not
  # completely fit the YaST use-cases.
  #
  # This mixin makes possible to define new classes in the Y2Storage namespace
  # that rely on the libstorage classes to do most of the job while offering a
  # more Ruby-oriented API and adding extra methods as needed.
  #
  # A class in the Y2Storage namespace can include this mixin and then use
  # the wrap_class macro to point to the Storage class to wrap. Then it can
  # use the storage_forward and storage_class_forward macros to define methods
  # and class methods. The calls to those methods will be automatically
  # forwarded to the wrapped object. The wrapped object will be specified when
  # creating the object (the initializer is also provided by this mixin).
  module StorageClassWrapper
    def self.included(base)
      base.extend(ClassMethods)
    end

    # Constructor for the wrapper object
    #
    # @param object [Object] the Storage object to wrap
    def initialize(object)
      cast_method = :"to_#{self.class.storage_class_underscored_name}"
      @storage_object =
        if Storage.respond_to?(cast_method)
          Storage.send(cast_method, object)
        else
          object
        end
    end

    # Equivalent to this object in the Storage world, i.e. the wrapped object.
    def to_storage_value
      @storage_object
    end

    # Class methods to be added
    module ClassMethods
      # Macro to define the class in the Storage namespace to be wrapped.
      #
      # Since libstorage enforces explicit type check and explicit downcast for
      # every object, this macro is also used to specify all the wrapper classes
      # to which it makes sense to automatically downcast the objects (i.e. the
      # existing subclasses for this in the Y2Storage namespace).
      #
      # @param storage_class [Class] class to wrap
      # @param downcast_to [Array<String>] names of the existing subclasses in
      #   Y2Storage to automatically perform downcasts to. Do not include the
      #   "Y2Storage" namespace in the class name (i.e. names relatively
      #   qualified).
      #
      # @example Basic usage of wrap_class
      #
      #   module Y2Storage
      #     class BlkDevice
      #       include StorageClassWrapper
      #       wrap_class Storage::BlkDevice, downcast_to: ["Disk", "MyPartition"]
      #     end
      #
      #     class Disk < BlkDevice
      #       wrap_class Storage::Disk
      #     end
      #
      #     class MyPartition < BlkDevice
      #       wrap_class Storage::Partition
      #     end
      #   end
      #
      #   blk_device = Storage::find_by_name(a_devicegraph, "/dev/sda2")
      #   blk_device.class #=> Storage::BlkDevice
      #   # The user should never need to call this constructor
      #   y2_device = Y2Storage::BlkDevice.downcasted_new(blk_device)
      #   y2_device.class #=> Y2Storage::Partition
      #
      def wrap_class(storage_class, downcast_to: [])
        @storage_class = storage_class
        @downcast_class_names = downcast_to
      end

      # Macro to define a method that will forward all the calls to the wrapped
      # object.
      #
      # The following measures will be taken to make the forward possible:
      #
      #   * At the moment of forwarding, all the arguments will be transformed
      #     to match libstorage type expectations (i.e. converted via
      #     #to_storage_value if available).
      #   * Storage exceptions indicating that a given element is not present
      #     will be turned into a return value of nil (see "raise_error" below)
      #   * Returned values will be converted.
      #     * SWIG typed vectors will become arrays
      #     * Objects will be transformed to the class specified by "as". No
      #       matter if those objects are the direct result or the elements of a
      #       vector. If the class specified by "as" is a wrapper class, the
      #       objects will be automatically downcasted as much as possible.
      #
      # @param method [Symbol] name of the method to define
      # @param as [String] name of the class to convert the result, nil if the
      #   value must be returned as-is (after turning any vector into an array)
      # @param raise_errors [Boolean] whether to disable the mechanism that
      #   turns into a nil result all the exceptions of type
      #   WrongNumberOfChildren, DeviceHasWrongType and DeviceNotFound.
      #   Useful for methods in which those exceptions don't have the usual
      #   meaning (looking for something that is not there).
      # @param to [Symbol] optional name of the method in the wrapped object.
      #   If not specified, the method name is considered to be the same in the
      #   wrapper and in the wrapper object. Using "to" allows to rename the
      #   method when exposing it.
      #
      # @example Usage of storage_forward
      #
      #   module Y2Storage
      #     class BlkDevice < Device
      #       include StorageClassWrapper
      #       wrap_class Storage::BlkDevice
      #
      #       storage_forward :name
      #       storage_forward :size, as: "DiskSize"
      #       storage_forward :size=
      #       storage_forward :udev_paths
      #       storage_forward :rotational?, to: :rotational
      #       storage_forward :blk_filesystem, as: "Filesystems::BlkFilesystem"
      #       storage_forward :create_blk_filesystem,
      #         as: "Filesystems::BlkFilesystem",
      #         raise_errors: true
      #     end
      #   end
      #
      #   device = Y2Storage::BlkDevice.new(storage_device)
      #
      #   # This is simply forwarded
      #   device.name
      #
      #   # This is forwarded to Storage::BlkDevice#rotational
      #   device.rotational?
      #
      #   # Returns a Y2Storage::DiskSize object instead of the Fixnum (bytes)
      #   # returned by Storage::BlkDevice#size
      #   device.size
      #
      #   # Transforms the argument to Fixnum (bytes) before passing it to
      #   # Storage::BlkDevice#size=
      #   device.size = Y2Storage::DiskSize.GiB(20)
      #
      #   # Returns an array of strings instead of a Storage::VectorString
      #   device.udev_paths
      #
      #   # If there is no filesystem (device is not formatted), it returns
      #   # nil instead of raising an exception. If there is one, its wrapped
      #   # into a Y2Storage::Filesystems::BlkFilesystem object before being
      #   # returned.
      #   device.blk_filesystem
      #
      #   fs_type = Y2Storage::Filesystems::Type.find(:btrfs)
      #   # Transforms fs_type into something understandable by
      #   # Storage::BlkDevice#create_blk_device when passing it.
      #   # If the device was already formatted, it raises an exception
      #   # (is not masked like in the example above).
      #   device.create_blk_filesystem(fs_type)
      #
      def storage_forward(method, to: nil, as: nil, raise_errors: false)
        modifiers = { as: as, raise_errors: raise_errors }
        target = to || method
        define_method(method) do |*args|
          StorageClassWrapper.forward(to_storage_value, target, modifiers, *args)
        end
      end

      # Equivalent to #storage_forward used to define class methods instead of
      # instance ones.
      #
      # @see #storage_forward
      def storage_class_forward(method, to: nil, as: nil, raise_errors: false)
        modifiers = { as: as, raise_errors: raise_errors }
        target = to || method
        define_singleton_method(method) do |*args|
          StorageClassWrapper.forward(storage_class, target, modifiers, *args)
        end
      end

      def storage_class
        @storage_class
      end

      def storage_class_name
        @storage_class_name ||= storage_class.name.split("::").last
      end

      def storage_class_underscored_name
        @storage_class_underscored_name ||= StorageClassWrapper.underscore(storage_class_name)
      end

      # Alternative constructor used internally by this module in order to get
      # fully downcasted objects.
      #
      # @param object [Object] storage object to be wrapped
      def downcasted_new(object)
        @downcast_class_names.each do |class_name|
          klass = StorageClassWrapper.class_for(class_name)
          storage_class = klass.storage_class

          underscored = StorageClassWrapper.underscore(storage_class.name.split("::").last)
          check_method = :"#{underscored}?"
          cast_method = :"to_#{underscored}"
          next unless Storage.public_send(check_method, object)

          return klass.downcasted_new(Storage.send(cast_method, object))
        end
        new(object)
      end
    end

    # Static methods offered by the module, not to extend or to be included in
    # the class using the mixin
    class << self
      # @see ClassMethods#storage_forward
      def forward(storage_object, method, modifiers, *args)
        wrapper_class_name = modifiers[:as]
        raise_errors = modifiers[:raise_errors]

        processed_args = processed_storage_args(*args)
        result = storage_object.public_send(method, *processed_args)
        processed_storage_result(result, wrapper_class_name)
      rescue Storage::WrongNumberOfChildren, Storage::DeviceHasWrongType, Storage::DeviceNotFound
        raise_errors ? raise : nil
      end

      def class_for(class_name)
        Y2Storage.const_get(class_name)
      end

      def underscore(camel_case_name)
        camel_case_name.gsub(/(.)([A-Z])/, '\1_\2').downcase
      end

    private

      def processed_storage_args(*args)
        args.map { |arg| arg.respond_to?(:to_storage_value) ? arg.to_storage_value : arg }
      end

      def processed_storage_result(result, class_name)
        result = result.to_a if result.class.name.start_with?("Storage::Vector")

        return result unless class_name

        wrapper_class = class_for(class_name)
        if result.is_a?(Array)
          result.map { |o| object_for(wrapper_class, o) }
        else
          object_for(wrapper_class, result)
        end
      end

      def object_for(wrapper_class, storage_object)
        if wrapper_class.respond_to?(:downcasted_new)
          wrapper_class.downcasted_new(storage_object)
        else
          wrapper_class.new(storage_object)
        end
      end
    end
  end
end
