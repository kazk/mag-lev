require 'spec_helper'

class SharedListener
  def user_created(user)
    user.name = 'shared'
  end
end

class WebListener
  def user_created(user)
    user.name = 'web'
  end
end

class AdhocListener
  def user_created(user)
    user.name = 'adhoc'
  end
end

class BrokeListener
  def user_created(user)
    raise "broke"
  end
end

class HaltListener
  def user_created!(user)
    raise "halt"
  end
end

class AsyncListener
  def user_created_async(user)
    # only update if the lister was properly included, in order to check that they are infact attached
    if MagLev.broadcaster.listeners.any? {|l| l.class.name == 'AsyncListener'}
      user.name = 'async'
      user.save!
    end
  end
end

describe MagLev::Broadcaster do
  let(:user) { User.create }
  let(:broadcasted) { MagLev.broadcaster.broadcasted }
  subject(:broadcaster) { MagLev.broadcaster }

  context 'with specified broadcast_mode', listeners: SharedListener do
    MagLev.config.listeners.broadcast_mode = :specified

    describe '#listeners' do
      its(:listeners) { should_not be_empty }
    end

    describe '#broadcast' do
      context 'when only always_enabled groups are active' do
        it 'should dispatch an event to default group ' do
          user.broadcast(:user_created, user).to(SharedListener, WebListener)
          expect(broadcasted.size).to eq 1
          expect(user.name).to eq 'shared'
        end

        it 'should broadcast an event if multiple groups are configured' do
          broadcaster.listen(WebListener) do
            user.broadcast(:user_created, user).to(SharedListener, WebListener, AdhocListener)
            expect(broadcasted.size).to eq 1
            expect(user.name).to eq 'web'
          end
        end

        it 'should support broadcast matcher' do
          expect { user.broadcast(:user_created, user).to(SharedListener) }
            .to broadcast(:user_created).once.to(SharedListener)
        end
      end

      context 'when adhoc listener is used' do
        it 'should use adhoc listener', listeners: AdhocListener do
          user.broadcast(:user_created, user).to(AdhocListener)
          expect(broadcasted.size).to eq 1
          expect(user.name).to eq 'adhoc'
        end
      end

      context 'when async listener is used' do
        it 'should call async listener', listeners: AsyncListener do
          user.broadcast(:user_created, user).to(AsyncListener)
          expect(broadcasted.size).to eq 1
          expect(user.reload.name).to eq 'async'
        end
      end

      context 'error handling' do
        describe 'when non-bang method is used', listeners: [BrokeListener, SharedListener]  do
          it 'should still process the rest of the listener chain' do
            user.broadcast(:user_created, user).to(BrokeListener, SharedListener)
            expect(broadcasted.size).to eq 1
            expect(user.name).to eq 'shared'
          end
        end

        describe 'when bang method is used', listeners: [HaltListener, SharedListener] do
          it 'should not process the rest of the listener chain' do
            expect {
              user.broadcast(:user_created, user).to(HaltListener, SharedListener)
            }.to raise_error

            expect(user.name).to_not eq 'shared'
          end
        end
      end
    end
  end
end