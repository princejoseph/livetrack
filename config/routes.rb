Rails.application.routes.draw do
  # Must stay first so the HyperModel/ActionCable endpoints always match.
  mount Hyperstack::Engine => "/hyperstack"

  root "maps#me"
  get "me"       => "maps#me",       as: :me
  get "everyone" => "maps#everyone", as: :everyone

  get "up" => "rails/health#show", as: :rails_health_check
end
