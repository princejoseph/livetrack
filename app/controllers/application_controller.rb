class ApplicationController < ActionController::Base
  # Every visitor gets an anonymous Tracker on first request. The id is kept in
  # Rails' encrypted session cookie, which is what makes it a credential the
  # client cannot forge -- there is no secret column on the trackers table.
  helper_method :current_tracker

  def current_tracker
    @current_tracker ||= find_or_create_tracker
  end

  # Hyperstack calls this to decide what the requesting client may read and
  # write (see app/policies/hyperstack/application_policy.rb).
  def acting_user
    current_tracker
  end

  private

  def find_or_create_tracker
    existing = session[:tracker_id] && Tracker.find_by(id: session[:tracker_id])
    return existing if existing

    Tracker.create!(Tracker.generate_identity).tap do |tracker|
      session[:tracker_id] = tracker.id
    end
  end
end
