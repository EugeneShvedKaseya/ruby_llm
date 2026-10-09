# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Support::Interner do
  subject(:interner) { described_class.new }

  describe '#intern' do
    it 'returns one object for equal arrays' do
      expect(interner.intern(%w[text image])).to equal(interner.intern(%w[text image]))
    end

    it 'returns one object for equal hashes' do
      expect(interner.intern({ input: ['text'] })).to equal(interner.intern({ input: ['text'] }))
    end

    it 'shares nested structures' do
      first = interner.intern({ limit: { context: 128, output: 16 } })
      second = interner.intern({ limit: { context: 128, output: 16 } })

      expect(second[:limit]).to equal(first[:limit])
    end

    it 'shares a subtree that appears under different parents' do
      first = interner.intern({ cost: { input: 1 } })
      second = interner.intern({ pricing: { input: 1 } })

      expect(second[:pricing]).to equal(first[:cost])
    end

    it 'deduplicates strings' do
      first = interner.intern(['models.dev'])
      second = interner.intern(['models.dev'])

      expect(second.first).to equal(first.first)
    end

    it 'freezes what it returns' do
      interned = interner.intern({ values: %w[low high] })

      expect(interned).to be_frozen
      expect(interned[:values]).to be_frozen
      expect(interned[:values].first).to be_frozen
    end

    it 'leaves the value it was given unfrozen' do
      source = { values: %w[low high] }
      interner.intern(source)

      expect(source).not_to be_frozen
      expect(source[:values]).not_to be_frozen
    end

    it 'preserves key types and order' do
      interned = interner.intern({ b: 1, 'a' => 2 })

      expect(interned.keys).to eq([:b, 'a'])
    end

    it 'returns values it cannot intern unchanged' do
      expect(interner.intern(42)).to eq(42)
      expect(interner.intern(nil)).to be_nil
      expect(interner.intern(:symbol)).to eq(:symbol)
    end

    it 'stops pooling once it reaches its limit' do
      small = described_class.new(limit: 1)
      small.intern([1])

      first = small.intern([2])
      second = small.intern([2])

      expect(second).not_to equal(first)
      expect(second).to be_frozen
    end
  end

  describe '#shared' do
    it 'builds once for equal keys' do
      built = 0
      2.times { interner.shared(:modalities, { input: ['text'] }) { built += 1 } }

      expect(built).to eq(1)
    end

    it 'returns the value built for the first equal key' do
      first = interner.shared(:modalities, { input: ['text'] }) { Object.new }
      second = interner.shared(:modalities, { input: ['text'] }) { Object.new }

      expect(second).to equal(first)
    end

    it 'builds again for a different key' do
      first = interner.shared(:modalities, { input: ['text'] }) { Object.new }
      second = interner.shared(:modalities, { input: ['image'] }) { Object.new }

      expect(second).not_to equal(first)
    end

    it 'keeps kinds apart when their keys are equal' do
      modalities = interner.shared(:modalities, {}) { Object.new }
      pricing = interner.shared(:pricing, {}) { Object.new }

      expect(pricing).not_to equal(modalities)
    end

    it 'yields the key it was given' do
      expect { |block| interner.shared(:modalities, { input: ['text'] }, &block) }
        .to yield_with_args({ input: ['text'] })
    end
  end

  describe '#clear' do
    it 'forgets what it pooled' do
      first = interner.intern(%w[text])
      interner.clear

      expect(interner.intern(%w[text])).not_to equal(first)
    end
  end
end
