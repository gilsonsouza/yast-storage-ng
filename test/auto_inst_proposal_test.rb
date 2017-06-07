#!/usr/bin/env rspec
# encoding: utf-8
#
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

require_relative "spec_helper"
require "storage"
require "y2storage"
# require_relative "support/proposal_context"
require "y2storage/auto_inst_proposal"

describe Y2Storage::AutoInstProposal do
  subject(:proposal) { described_class.new(partitioning: partitioning, devicegraph: fake_devicegraph) }

  describe "#propose" do
    using Y2Storage::Refinements::SizeCasts

    ROOT_PART = { "filesystem" => :ext4, "mount" => "/", "size" => "25%", "label" => "new_root" }

    let(:scenario) { "windows-linux-free-pc" }

    # include_context "proposal"
    let(:root) { ROOT_PART.merge("create" => true) }

    let(:home) do
      { "filesystem" => :xfs, "mount" => "/home", "size" => "50%", "create" => true }
    end

    let(:swap) do
      { "filesystem" => :swap, "mount" => "swap", "size" => "1GB", "create" => true }
    end

    let(:partitioning) do
      [{ "device" => "/dev/sda", "use" => "all", "partitions" => [root, home] }]
    end

    before do
      fake_scenario(scenario)
    end

    context "when partitions are specified" do
      it "proposes a layout including those partitions" do
        proposal.propose
        devicegraph = proposal.proposed_devicegraph

        expect(devicegraph.partitions.size).to eq(2)
        root, home = devicegraph.partitions

        expect(root).to have_attributes(
          filesystem_type:       Y2Storage::Filesystems::Type.find("Ext4"),
          filesystem_mountpoint: "/",
          size:                  125.GiB
        )

        expect(home).to have_attributes(
          # FIXME: use a different filesystem type
          filesystem_type:       Y2Storage::Filesystems::Type.find("XFS"),
          filesystem_mountpoint: "/home",
          size:                  250.GiB
        )
      end
    end

    context "failing scenario" do
      let(:root) { ROOT_PART.merge("create" => true, "size" => "max") }

      let(:partitioning) do
        [{ "device" => "/dev/sda", "use" => "all", "partitions" => [swap, root] }]
      end

      it "proposes a layout including those partitions" do
        proposal.propose
        devicegraph = proposal.proposed_devicegraph

        expect(devicegraph.partitions.size).to eq(2)
        swap, root = devicegraph.partitions

        expect(swap).to have_attributes(
          filesystem_type:       Y2Storage::Filesystems::Type.find("swap"),
          filesystem_mountpoint: "swap",
          size:                  1.GiB
        )

        expect(root).to have_attributes(
          # FIXME: use a different filesystem type
          filesystem_type:       Y2Storage::Filesystems::Type.find("ext4"),
          filesystem_mountpoint: "/"
        )
      end
    end

    describe "reusing partitions" do
      let(:partitioning) do
        [{ "device" => "/dev/sda", "use" => "free", "partitions" => [root] }]
      end

      context "when an existing partition_nr is specified" do
        let(:root) do
          { "filesystem" => :ext4, "mount" => "/", "partition_nr" => 1, "create" => false }
        end

        xit "reuses the partition with the given partition number" do
          proposal.propose
          devicegraph = proposal.proposed_devicegraph
          reused_part = devicegraph.partitions.find { |p| p.name == "/dev/sda1" }
          expect(reused_part.filesystem_mountpoint).to eq("/")
        end
      end

      context "when an existing label is specified" do
        let(:root) do
          { "filesystem" => :ext4, "mount" => "/", "mountby" => :label, "label" => "windows",
            "create" => false }
        end

        xit "reuses the partition with the given label" do
          proposal.propose
          devicegraph = proposal.proposed_devicegraph
          reused_part = devicegraph.partitions.find { |p| p.filesystem_label == "windows" }
          expect(reused_part.filesystem_mountpoint).to eq("/")
        end
      end
    end

    describe "removing partitions" do
      let(:scenario) { "windows-linux-free-pc" }
      let(:partitioning) { [{ "device" => "/dev/sda", "partitions" => [root], "use" => use }] }

      context "when the whole disk should be used" do
        let(:use) { "all" }

        it "removes the old partitions" do
          proposal.propose
          devicegraph = proposal.proposed_devicegraph
          expect(devicegraph.partitions.size).to eq(1)
          part = devicegraph.partitions.first
          expect(part).to have_attributes(filesystem_label: "new_root")
        end
      end

      context "when only free space should be used" do
        let(:use) { "free" }

        it "keeps the old partitions" do
          proposal.propose
          devicegraph = proposal.proposed_devicegraph
          labels = devicegraph.partitions.map(&:filesystem_label)
          expect(labels).to eq(["windows", "swap", "root", "new_root"])
        end

        it "raises an error if there is not enough space"
      end

      context "when only space from Linux partitions should be used" do
        let(:use) { "linux" }

        it "keeps all partitions except Linux ones" do
          proposal.propose
          devicegraph = proposal.proposed_devicegraph
          labels = devicegraph.partitions.map(&:filesystem_label)
          expect(labels).to eq(["windows", "new_root"])
        end

        it "raises an error if there is not enough space"
      end

      context "when the device should be initialized" do
        let(:partitioning) { [{ "device" => "/dev/sda", "partitions" => [root], "initialize" => true }] }

        xit "removes the old partitions" do
          proposal.propose
          devicegraph = proposal.proposed_devicegraph
          expect(devicegraph.partitions.size).to eq(1)
          part = devicegraph.partitions.first
          expect(part).to have_attributes(filesystem_label: "new_root")
        end
      end
    end

    describe "skipping a disk" do
      let(:skip_list) do
        [{ "skip_key" => "name", "skip_value" => skip_device }]
      end

      let(:partitioning) do
        [{ "use" => "all", "partitions" => [root, home], "skip_list" => skip_list }]
      end

      context "when a disk is included in the skip_list" do
        let(:skip_device) { "sda" }

        it "skips the given disk" do
          proposal.propose
          devicegraph = proposal.proposed_devicegraph
          sdb1 = devicegraph.partitions.find { |p| p.name == "/dev/sdb1" }
          expect(sdb1).to have_attributes(filesystem_label: "new_root")
          sda1 = devicegraph.partitions.first
          expect(sda1).to have_attributes(filesystem_label: "windows")
        end
      end

      context "when no disk is included in the skip_list" do
        let(:skip_device) { "sdc" }

        it "does not skip any disk" do
          proposal.propose
          devicegraph = proposal.proposed_devicegraph
          sda1 = devicegraph.partitions.first
          expect(sda1).to have_attributes(filesystem_label: "new_root")
        end
      end
    end

    describe "automatic partitioning" do
      let(:partitioning) do
        [{ "device" => "/dev/sda", "use" => "all" }]
      end

      it "falls back to the product's proposal"
    end

    context "when already called" do
      before do
        proposal.propose
      end

      it "raises an error" do
        expect { proposal.propose }.to raise_error(Y2Storage::UnexpectedCallError)
      end
    end
  end
end
