# frozen_string_literal: true

FactoryBot.define do
  factory :workshop_recording do
    workshop_group
    workshop_challenge
    recorded_by factory: :user
    status { "pending" }
    utterances { [] }

    trait :ready do
      status { "ready" }
      duration_seconds { 16.9 }
      provider { "fixture" }
      model { "fixture-v1" }
      utterances do
        [
          { "speaker" => 0, "start" => 0.0, "end" => 4.2, "transcript" => "Primera.",
            "confidence" => 0.99, "speaker_confidence" => 0.91 },
          { "speaker" => 1, "start" => 5.1, "end" => 9.4, "transcript" => "Segunda.",
            "confidence" => 0.97, "speaker_confidence" => 0.88 }
        ]
      end
    end

    trait :colapsada do
      status { "ready" }
      utterances do
        [
          { "speaker" => 0, "start" => 0.0, "end" => 4.2, "transcript" => "Primera.",
            "confidence" => 0.99, "speaker_confidence" => 0.32 },
          { "speaker" => 0, "start" => 5.1, "end" => 9.4, "transcript" => "Segunda.",
            "confidence" => 0.97, "speaker_confidence" => 0.19 }
        ]
      end
    end
  end
end
