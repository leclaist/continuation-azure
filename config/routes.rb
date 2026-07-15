Rails.application.routes.draw do
  root "home#index"
  get "/:year",       to: "years#show",   constraints: { year: /\d{4}/ }, as: :year
  get "/:year/:slug", to: "entries#show",                                  as: :entry
  get "/:year/:slug/audio", to: "entries#audio", constraints: { year: /\d{4}/ }, as: :entry_audio

  namespace :admin do
    post "clear_comments", to: "maintenance#clear_comments"
  end
end
