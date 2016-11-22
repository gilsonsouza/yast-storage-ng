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

require "storage"
require "y2storage/refinements"

module Y2Storage
  class Proposal
    # Utility class to delete partitions from a devicegraph
    class PartitionKiller
      using Refinements::DevicegraphLists
      include Yast::Logger

      # Initialize.
      #
      # @param devicegraph [::Storage::Devicegraph]
      # @param disk_analyzer [::Storage::DiskAnalyzer]
      def initialize(devicegraph, disk_analyzer)
        @devicegraph = devicegraph
        @disk_analyzer = disk_analyzer
      end

      # Deletes a given partition and other partitions that, as a consequence,
      # are not longer useful.
      #
      # @param device_name [String] device name of the partition
      # @return [Array<String>] device names of all the deleted partitions
      def delete(device_name)
        partition = find_partition(device_name)
        return [] unless partition

        if lvm_pv?(partition)
          delete_lvm_partitions(partition)
        else
          delete_partition(partition)
        end
      end

    protected

      attr_reader :devicegraph, :disk_analyzer

      def find_partition(name)
        devicegraph.partitions.with(name: name).first
      end

      # Deletes a given partition from its corresponding partition table.
      # If the partition was the only remaining logical one, it also deletes the
      # now empty extended partition
      #
      # @param partition [Storage::Partition]
      # @return [Array<String>] device names of all the deleted partitions
      def delete_partition(partition)
        log.info("Deleting partition #{partition.name} in device graph")
        if last_logical?(partition)
          log.info("It's the last logical one, so deleting the extended")
          delete_extended(partition.partition_table)
        else
          result = [partition.name]
          partition.partition_table.delete_partition(partition.name)
          result
        end
      end

      # Deletes the extended partition and all the logical ones
      #
      # @param partition_table [Storage::PartitionTable]
      # @return [Array<String>] device names of all the deleted partitions
      def delete_extended(partition_table)
        partitions = partition_table.partitions.to_a
        extended = partitions.detect { |part| part.type == ::Storage::PartitionType_EXTENDED }
        logical_parts = partitions.select { |part| part.type == ::Storage::PartitionType_LOGICAL }

        # This will delete the extended and all the logicals
        names = [extended.name] + logical_parts.map(&:name)
        partition_table.delete_partition(extended.name)
        names
      end

      # Checks whether the partition is the only logical one in the
      # partition_table
      #
      # @param partition [Storage::Partition]
      # @return [Boolean]
      def last_logical?(partition)
        return false unless partition.type == ::Storage::PartitionType_LOGICAL

        partitions = partition.partition_table.partitions.to_a
        logical_parts = partitions.select { |part| part.type == ::Storage::PartitionType_LOGICAL }
        logical_parts.size == 1
      end

      # Deletes the given partition and all other partitions in the candidate
      # disks that are part of the same LVM volume group
      #
      # Rationale: when deleting a partition that holds a PV of a given VG, we
      # are effectively killing the whole VG. It makes no sense to leave the
      # other PVs alive. So let's reclaim all the space.
      #
      # @param partition [Storage::Partition] A partition that is acting as
      #   LVM physical volume
      # @return [Array<String>] device names of all the deleted partitions
      def delete_lvm_partitions(partition)
        log.info "Deleting #{partition.name}, which is part of an LVM volume group"
        vg_parts = disk_analyzer.used_lvm_partitions.values.detect do |parts|
          parts.map(&:name).include?(partition.name)
        end
        target_parts = vg_parts.map { |p| find_partition(p.name) }.compact
        log.info "These LVM partitions will be deleted: #{target_parts.map(&:name)}"
        target_parts.map { |part| delete_partition(part) }.flatten
      end

      # Checks whether the partition is part of a volume group
      #
      # @param partition [::Storage::Partition]
      # @return [Boolean]
      def lvm_pv?(partition)
        lvm_pv_names = disk_analyzer.used_lvm_partitions.values.flatten.map(&:name)
        lvm_pv_names.include?(partition.name)
      end
    end
  end
end