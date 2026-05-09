Rails.application.routes.draw do
  root "home#index"
  get "/:year",       to: "years#show",   constraints: { year: /\d{4}/ }, as: :year
  get "/:year/:slug", to: "entries#show",                                  as: :entry
end
