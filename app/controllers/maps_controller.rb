class MapsController < ApplicationController
  # Page 1: track this browser's own GPS and draw it live.
  def me
    # Referencing current_tracker here (rather than only in the view) makes sure
    # the session cookie is issued on this request, before the client opens its
    # HyperModel socket and tries to write as this tracker.
    @tracker = current_tracker
  end

  # Page 2: everyone currently tracking, markers moving in real time.
  def everyone
    @tracker = current_tracker
  end
end
