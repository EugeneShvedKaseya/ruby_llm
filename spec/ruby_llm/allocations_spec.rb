# frozen_string_literal: true

require 'spec_helper'

# rubocop:disable-next RSpec/DescribeClass
RSpec.describe 'allocations on the hot path' do
  include_context 'with configured RubyLLM'

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

  def chat_with(turns)
    chat = RubyLLM.chat(model: 'gpt-4.1')
    chat.with_instructions('terse')
    turns.times do |index|
      chat.add_message(role: :user, content: "question #{index}")
      chat.add_message(role: :assistant, content: "answer #{index}")
    end
    chat
  end

  it 'builds a request transcript without an array per message' do
    chat = chat_with(10)
    chat.send(:request_history, chat.messages)

    arrays = allocated_in(:T_ARRAY) { chat.send(:request_history, chat.messages) }

    expect(arrays - baseline(:T_ARRAY)).to be < chat.messages.size
  end

  it 'builds a request transcript at a cost that does not grow with the transcript' do
    short = chat_with(3)
    long = chat_with(20)
    [short, long].each { |chat| chat.send(:request_history, chat.messages) }

    short_arrays = allocated_in(:T_ARRAY) { short.send(:request_history, short.messages) }
    long_arrays = allocated_in(:T_ARRAY) { long.send(:request_history, long.messages) }

    expect(long_arrays - short_arrays).to be <= 2
  end

  it 'keeps the transcript a request is built from' do
    chat = chat_with(3)

    expect(chat.send(:request_history, chat.messages).map(&:content))
      .to eq(chat.messages.map(&:content))
  end

  it 'resolves the configured protocol option without building its name again' do
    config = RubyLLM::Configuration.new
    config.openai_api_key = 'test-key'
    provider = RubyLLM::Provider.resolve!(:openai).new(config)
    provider.send(:configured_protocol)

    expect(allocated_in { 10.times { provider.send(:configured_protocol) } }).to eq(baseline)
  end
end
