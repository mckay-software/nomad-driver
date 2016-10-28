module Slop
  class MultiOption < Option
    def call(value)
      @@multi ||= []
      @@multi << value
      @@multi
    end
  end
end
