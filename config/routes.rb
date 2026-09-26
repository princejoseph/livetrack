Rails.application.routes.draw do
  # Must stay first so the HyperModel/ActionCable endpoints always match.
  mount Hyperstack::Engine => "/hyperstack"

  root "maps#me"
  get "me"       => "maps#me",       as: :me
  get "everyone" => "maps#everyone", as: :everyone
  get "route"    => "routes#show",     as: :route

  get "up" => "rails/health#show", as: :rails_health_check
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
end
