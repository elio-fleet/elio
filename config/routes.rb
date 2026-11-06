Rails.application.routes.draw do
  devise_for :users, controllers: { sessions: "users/sessions", passwords: "users/passwords" }
  resource :two_factor_challenge, only: %i[new create]
  resource :account, only: %i[show] do
    patch :password
    patch :locale
  end
  resource :two_factor, only: %i[new create destroy], path: "account/two_factor", controller: "two_factor_settings" do
    post :backup_codes
  end
  resource :setup, only: %i[new create]
  get "invitations/:token", to: "invitations#show", as: :invitation_acceptance
  post "invitations/:token", to: "invitations#accept"

  # Before `resources :servers`, or /servers/groups would be a server's page.
  resources :server_groups, except: :show, path: "servers/groups"
  resource :server_inventories, only: :create, path: "servers/inventory"
  resource :server_import, only: %i[new create], path: "servers/import" do
    post :preview
  end
  resources :servers do
    resource :ping, only: %i[show create], controller: "server_pings"
    resource :ssh_check, only: :show, controller: "server_ssh_checks"
    resource :inventory, only: :create, controller: "server_inventories"
    resources :packages, only: :index, controller: "server_packages"
    resource :host_key, only: :create, controller: "server_host_keys"
    resources :authorized_keys, only: :index, controller: "server_authorized_keys"
    resource :authorized_key, only: :destroy, controller: "server_authorized_keys"
    resources :authorizations, only: :create, controller: "server_authorizations"
    resources :notes, only: %i[create edit update destroy], controller: "server_notes" do
      post :preview, on: :collection
    end
  end
  resource :server_pings, only: :create, path: "servers/pings"
  resource :server_scans, only: :create, path: "servers/scans"

  resources :public_keys, path: "keys" do
    resources :accesses, only: :create, controller: "public_key_accesses"
    resource :access, only: :destroy, controller: "public_key_accesses"
  end

  resource :settings, only: :show
  namespace :settings do
    resources :users, only: %i[index update] do
      member do
        post :deactivate
        post :reactivate
        post :reset_two_factor
      end
    end
    resources :invitations, only: %i[create destroy]
    resource :security, only: :update
    resource :health_thresholds, only: :update
    resource :language, only: :update
    resource :docker, only: %i[show update], controller: "docker" do
      post :check
    end
    resources :score_providers, only: %i[new create edit update destroy], path: "vulnerabilities/providers" do
      member do
        patch :move
        patch :toggle
        post :test
      end
      post :preview, on: :collection
    end
    resource :vulnerabilities, only: %i[show update] do
      post :refresh
      post :import
      post :scores
    end
    resources :key_rotations, only: %i[create show] do
      member do
        post :retry
        post :finalize
      end
    end
    resource :notifications, only: :show
    resources :notification_channels, except: %i[index show], path: "notifications/channels" do
      post :test, on: :member
    end
    resources :automations, only: %i[index update] do
      post :run, on: :member
    end
    resources :integrations, only: %i[index edit update], param: :kind, path: "extensions" do
      member do
        match :test, via: %i[post patch] # (the button shares the settings form, sent as PATCH)
        post :sync
      end
    end
  end
  resources :activities, only: :index
  resources :tasks, only: %i[index show]
  resources :packages, only: :index
  resources :ports, only: :index
  resources :scheduled_tasks, only: :index, path: "scheduled-tasks"
  resources :vulnerabilities, only: %i[index show], param: :cve, constraints: { cve: /[A-Za-z0-9-]+/ }
  get "docker", to: "docker#index", as: :docker
  # Uptime Kuma extension.
  resources :monitors, only: :index do
    resource :link, only: %i[create destroy], controller: "monitor_links"
  end
  # OVHcloud extension.
  resources :dns_records, only: :index, path: "dns" do
    resource :link, only: %i[create destroy], controller: "dns_links"
  end
  get "ovh", to: "ovh#index", as: :ovh
  resources :ovh_resources, only: [], path: "ovh/resources" do
    resource :link, only: %i[create destroy], controller: "ovh_links"
  end
  scope "settings" do
    resource :ssh_key, only: :create
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Technical view of the background jobs (admins, see JobsDashboardController).
  mount MissionControl::Jobs::Engine, at: "/jobs"

  # Catalogue of the interface components, outside production.
  get "design" => "design#show" if Rails.env.local?

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  root "dashboard#index"
end
