

require "expert-partitioner/tree"


module ExpertPartitioner

  class TabView

    def create()
      VBox(VStretch(), HStretch())
    end

    def handle(input)
    end

    def update(also_tree = false)

      # TODO more accurate update options

      if also_tree
        Yast::UI.ChangeWidget(:tree, :Items, Tree.new().tree_items)
      end

      Yast::UI.ReplaceWidget(:tab_panel, create)

    end

  end

end
