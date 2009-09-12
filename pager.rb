module SimpleResource
  class Pager
    attr_accessor :totalnum, :from, :size

    def initialize response
      @totalnum = response['totalnum'].to_i
      @from = response['from'].to_i
      @size = response['size'].to_i
    end

    def prev
      (@from > 0) ? true : false
    end

    def next
      ((@totalnum - (@from + @size)) > 0) ? true : false
    end

    def totalpagenum
      (@totalnum.to_f / @size.to_f).ceil
    end

    def page
      return nil unless @size > 0
      (@from.to_f / @size.to_f).floor + 1
    end

    def to
      ((@from + @size) <= @totalnum) ? @from + @size - 1 : @totalnum - 1
    end

    def first
      @from + 1
    end

    def last
      ((last = @from + @size) < @totalnum) ? last : @totalnum
    end
  end
end
