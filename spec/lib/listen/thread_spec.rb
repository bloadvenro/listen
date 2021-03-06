# frozen_string_literal: true

require 'listen/thread'

RSpec.describe Listen::Thread do
  let(:raise_nested_exception_block) do
    -> do
      begin
        begin
          raise ArgumentError, 'boom!'
        rescue
          raise 'nested inner'
        end
      rescue
        raise 'nested outer'
      end
    end
  end

  let(:raise_script_error_block) do
    -> do
      raise ScriptError, "ruby typo!"
    end
  end

  describe '.new' do
    let(:name) { "worker_thread" }
    let(:block) { -> { } }
    subject { described_class.new(name, &block) }

    it "calls Thread.new" do
      expect(Thread).to receive(:new) do
        thread = instance_double(Thread, "thread")
        expect(thread).to receive(:name=).with("listen-#{name}")
        thread
      end
      subject
    end

    context "when exception raised" do
      let(:block) do
        -> { raise ArgumentError, 'boom!' }
      end

      it "rescues and logs exceptions" do
        expect(Listen.logger).to receive(:error).
          with(/Exception rescued in listen-worker_thread:\nArgumentError: boom!\n.*\/listen\/thread_spec\.rb/)
        subject.join
      end

      it "rescues and logs backtrace + exception backtrace" do
        expect(Listen.logger).to receive(:error).
          with(/Exception rescued in listen-worker_thread:\nArgumentError: boom!\n.*\/listen\/thread\.rb.*--- Thread.new ---.*\/listen\/thread_spec\.rb/m)
        subject.join
      end
    end

    context "when nested exceptions raised" do
      let(:block) { raise_nested_exception_block }

      it "details exception causes" do
        expect(Listen.logger).to receive(:error).
          with(/RuntimeError: nested outer\n--- Caused by: ---\nRuntimeError: nested inner\n--- Caused by: ---\nArgumentError: boom!/)
        subject.join
      end
    end

    context 'when exception raised that is not derived from StandardError' do
      let(:block) { raise_script_error_block }

      it "still rescues and logs" do
        expect(Listen.logger).to receive(:error).with(/Exception rescued in listen-worker_thread:\nScriptError: ruby typo!/)
        subject.join
      end
    end
  end

  describe '.rescue_and_log' do
    it 'rescues and logs nested exceptions' do
      expect(Listen.logger).to receive(:error).
        with(/Exception rescued in method:\nRuntimeError: nested outer\n--- Caused by: ---\nRuntimeError: nested inner\n--- Caused by: ---\nArgumentError: boom!/) do |message|
        expect(message).to_not match(/Thread\.new/)
      end
      described_class.rescue_and_log("method", &raise_nested_exception_block)
    end

    context 'when exception raised that is not derived from StandardError' do
      let(:block) { raise_script_error_block }

      it 'still rescues and logs' do
        expect(Listen.logger).to receive(:error).with(/Exception rescued in method:\nScriptError: ruby typo!/)
        described_class.rescue_and_log("method", &block)
      end
    end
  end
end
