
module MarkdownV2
  refine String do
    def mdv2_escape
      self.gsub(/[_*\[\]()~`>#+\\\-=|{}.!]/) { |c| "\\#{c}" }
    end
  end
end

