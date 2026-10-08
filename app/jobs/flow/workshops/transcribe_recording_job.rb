module Flow
  module Workshops
    class TranscribeRecordingJob < ApplicationJob
      queue_as :flow_ai
    end
  end
end
