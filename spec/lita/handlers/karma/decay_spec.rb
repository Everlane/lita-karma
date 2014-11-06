require "spec_helper"

describe Lita::Handlers::Karma::Decay, lita_handler: true do
  prepend_before { registry.register_handler(Lita::Handlers::Karma::Config) }

  let(:term) { "foo" }

  describe '#call' do
    let(:modifications) { { joe: 2, amy: 3, nil => 4 } }
    let(:offsets) { {} }

    before do
      registry.config.handlers.karma.decay = true
      registry.config.handlers.karma.decay_interval = 24 * 60 * 60

      subject.redis.zadd('terms', 8, term)
      subject.redis.zadd("modified:#{term}", modifications.invert.to_a)
      modifications.each do |modifying_user_id, score|
        offset = offsets[modifying_user_id].to_i
        score.times do |i|
          Lita::Handlers::Karma::Action.create(
            subject.redis,
            term,
            modifying_user_id,
            1,
            Time.now - (i + offset) * 24 * 60 * 60
          )
        end
      end
    end

    it 'should decrement scores' do
      subject.call

      expect(subject.redis.zscore(:terms, term).to_i).to eq(2)
    end

    it 'should remove decayed actions' do
      subject.call

      expect(subject.redis.zcard(:actions).to_i).to eq(3)
    end

    context 'with decayed modifiers' do
      let(:offsets) { { amy: 1 } }

      it 'should remove them' do
        subject.call

        expect(subject.redis.zcard("modified:#{term}")).to eq(2)
      end
    end
  end
end
