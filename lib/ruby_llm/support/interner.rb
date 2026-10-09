# frozen_string_literal: true

module RubyLLM
  module Support # :nodoc:
    # Shares one frozen copy of every distinct value it is given. The model
    # registry repeats the same capability lists, modality pairs, and metadata
    # subtrees across thousands of entries, and sharing them keeps one copy of
    # each for the life of the process.
    class Interner # :nodoc:
      LIMIT = 16_384

      def initialize(limit: LIMIT)
        @limit = limit
        @lock = Mutex.new
        @interned = {}
        @built = {}
      end

      # Returns a frozen equivalent of +value+, shared with every equal value
      # interned before it. Hashes and arrays are interned entry by entry, so
      # repeated subtrees are shared too. The value itself is left untouched.
      def intern(value)
        case value
        when Hash then canonical(value.to_h { |key, entry| [intern(key), intern(entry)] })
        when Array then canonical(value.map { |entry| intern(entry) })
        when String then -value
        else value
        end
      end

      # Returns the value of +kind+ built for +key+, building it on the first
      # of each set of equal keys and sharing it from then on. Two kinds can
      # carry the same key, so an empty modality list never answers a lookup
      # for empty pricing. The block runs outside the lock, so a value that
      # interns values of its own cannot deadlock.
      def shared(kind, key)
        pooled = @built[[kind, key]]
        return pooled if pooled

        value = yield key
        store(@built, [kind, intern(key)].freeze) { value }
      end

      def clear
        @lock.synchronize do
          @interned.clear
          @built.clear
        end
      end

      private

      def canonical(value)
        @interned[value] || store(@interned, value.freeze) { value }
      end

      # Two threads that miss on the same key must end up with one value, so
      # the miss path re-checks under the lock.
      def store(table, key)
        @lock.synchronize do
          existing = table[key]
          next existing if existing

          value = yield
          table[key] = value if table.size < @limit
          value
        end
      end
    end
  end
end
