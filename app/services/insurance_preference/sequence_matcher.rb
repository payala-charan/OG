# frozen_string_literal: true

module InsurancePreference
  # Port of Python difflib.SequenceMatcher (Ratcliff/Obershelp), including
  # the default autojunk heuristic, so similarity scores match the validated script.
  class SequenceMatcher
    Match = Struct.new(:a, :b, :size)

    def initialize(a = "", b = "", autojunk: true)
      @a = a.to_s
      @b = b.to_s
      @autojunk = autojunk
      chain_b
    end

    def ratio
      la = @a.length
      lb = @b.length
      return 1.0 if la.zero? && lb.zero?
      return 0.0 if la.zero? || lb.zero?

      2.0 * matching_blocks.sum(&:size) / (la + lb)
    end

    def matching_blocks
      return @matching_blocks if defined?(@matching_blocks)

      queue = [[0, @a.length, 0, @b.length]]
      matching = []

      until queue.empty?
        alo, ahi, blo, bhi = queue.pop
        i, j, k = find_longest_match(alo, ahi, blo, bhi)
        next if k.zero?

        matching << [i, j, k]
        queue << [alo, i, blo, j] if alo < i && blo < j
        queue << [i + k, ahi, j + k, bhi] if i + k < ahi && j + k < bhi
      end

      matching.sort!
      i1 = j1 = k1 = 0
      non_adjacent = []
      matching.each do |i2, j2, k2|
        if i1 + k1 == i2 && j1 + k1 == j2
          k1 += k2
        else
          non_adjacent << Match.new(i1, j1, k1) if k1.positive?
          i1 = i2
          j1 = j2
          k1 = k2
        end
      end
      non_adjacent << Match.new(i1, j1, k1) if k1.positive?
      non_adjacent << Match.new(@a.length, @b.length, 0)
      @matching_blocks = non_adjacent
    end

    def find_longest_match(alo, ahi, blo, bhi)
      besti = alo
      bestj = blo
      bestsize = 0
      j2len = {}

      (alo...ahi).each do |i|
        newj2len = {}
        (@b2j[@a[i]] || []).each do |j|
          next if j < blo
          break if j >= bhi

          k = newj2len[j] = (j2len[j - 1] || 0) + 1
          if k > bestsize
            besti = i - k + 1
            bestj = j - k + 1
            bestsize = k
          end
        end
        j2len = newj2len
      end

      while besti > alo && bestj > blo && !junk?(@b[bestj - 1]) && @a[besti - 1] == @b[bestj - 1]
        besti -= 1
        bestj -= 1
        bestsize += 1
      end

      while besti + bestsize < ahi && bestj + bestsize < bhi && !junk?(@b[bestj + bestsize]) && @a[besti + bestsize] == @b[bestj + bestsize]
        bestsize += 1
      end

      while besti > alo && bestj > blo && junk?(@b[bestj - 1]) && @a[besti - 1] == @b[bestj - 1]
        besti -= 1
        bestj -= 1
        bestsize += 1
      end

      while besti + bestsize < ahi && bestj + bestsize < bhi && junk?(@b[bestj + bestsize]) && @a[besti + bestsize] == @b[bestj + bestsize]
        bestsize += 1
      end

      [besti, bestj, bestsize]
    end

    private

    def chain_b
      @b2j = {}
      @b.each_char.with_index do |elt, i|
        (@b2j[elt] ||= []) << i
      end

      @bjunk = {}
      popular = {}
      n = @b.length
      if @autojunk && n >= 200
        ntest = n / 100 + 1
        @b2j.each do |elt, idxs|
          popular[elt] = true if idxs.length > ntest
        end
        popular.each_key { |elt| @b2j.delete(elt) }
      end

      @b2j.each_key { |elt| @bjunk[elt] = true if junk?(elt) }
    end

    def junk?(_elt)
      false
    end
  end
end
