# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable-next RSpec/DescribeClass
RSpec.describe 'allocations on the hot path' do
  # Counts objects created by the block, the way "The Complete Guide to Rails
  # Performance" does: stop the collector, diff ObjectSpace, put it back.
  def allocated_in(*types)
    types = %i[T_HASH T_ARRAY] if types.empty?
    GC.disable
    before = ObjectSpace.count_objects
    yield
    after = ObjectSpace.count_objects
    types.sum { |type| after[type] - before[type] }
  ensure
    GC.enable
  end

  def baseline(*types)
    allocated_in(*types) { nil }
  end

  it 'builds a Tokens without counts without allocating hashes' do
    RubyLLM::Tokens.new

    expect(allocated_in { RubyLLM::Tokens.new }).to eq(baseline)
  end

  it 'builds a Tokens with counts without a pair array per count' do
    counts = { 'web_search_requests' => 2, 'web_fetch_requests' => 1 }
    RubyLLM::Tokens.new(server_tool_use: counts)

    expect(allocated_in(:T_ARRAY) { RubyLLM::Tokens.new(server_tool_use: counts) }).to eq(baseline(:T_ARRAY))
  end

  it 'keeps the counts a Tokens was given' do
    tokens = RubyLLM::Tokens.new(input: 10, server_tool_use: { web_search_requests: 2, unused: 0 })

    expect(tokens.input).to eq(10)
    expect(tokens.server_tool_use).to eq('web_search_requests' => 2)
  end

  it 'reads nothing from empty counts' do
    expect(RubyLLM::Tokens.new(server_tool_use: {}, cache_write_by_ttl: {}).server_tool_use).to be_nil
  end

  it 'builds a message without citations without allocating twice for them' do
    attributes = { role: :user, content: 'hi' }
    RubyLLM::Message.new(attributes)

    expect(allocated_in { RubyLLM::Message.new(attributes) }).to be <= baseline + 4
  end

  it 'still coerces the citations it is given' do
    message = RubyLLM::Message.new(role: :assistant, content: 'hi',
                                   citations: [{ 'title' => 'T', 'url' => 'https://example.test' }])

    expect(message.citations.first).to be_a(RubyLLM::Citation)
  end

  it 'resolves the configured protocol option without building its name again' do
    config = RubyLLM::Configuration.new
    config.openai_api_key = 'test-key'
    provider = RubyLLM::Provider.resolve!(:openai).new(config)
    provider.send(:configured_protocol)

    expect(allocated_in { 10.times { provider.send(:configured_protocol) } }).to eq(baseline)
  end
end
